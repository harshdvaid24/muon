import Foundation

struct ActionResult {
    let tool: String
    let args: [String: Any]
    let text: String
    let ok: Bool
    var cancelled = false
}

/// A clickable row offered to the user (disambiguation or file results).
struct Suggestion {
    let icon: String
    let title: String
    let subtitle: String?
    let section: String
    let tool: String
    let args: [String: Any]
    let learnAlias: (term: String, path: String)?
}

struct AgentOutput {
    var tier = 0
    var answer: String?
    var suggestions: [Suggestion] = []
    var results: [ActionResult] = []
    var note: String?
    var cancelled = false
    var model: String?
}

/// Orchestrates the tiers: memory → on-device model → LM Studio. Learns after every success.
final class Agent {
    static let shared = Agent()

    let memory: Memory? = try? Memory()
    private(set) var lastResults: [ActionResult] = []
    private var projectsCache: [Project]?

    // MARK: Entry

    /// Phrases the 3B router cannot serve with one tool; they skip straight to tier 2.
    static let complexMarkers = [" and then ", " and which ", " which of ", " older than ", " newer than ", " larger than ", " bigger than ",
                                 " smaller than ", " duplicate", " clean up ", " cleanup ", " organize ", " organise ", " compare ", " how many ",
                                 " count ", " why ", " explain ", " summarize ", " summarise ", " what does ", " total size ", " each of "]
    static let notUnderstood = "I didn't understand that. Try: open <app>, find <files>, open <project> in <editor>, quit <app>, or ask about memory/disk. Prefix with “agent:” to force the larger model."
    static let cancelledMarker = "[[cancelled]]"

    func run(_ query: String, approver: Approver, status: @escaping (String) -> Void, forceTier: Int? = nil) async -> AgentOutput {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var out = AgentOutput()
        var forceTier = forceTier
        if q.lowercased().hasPrefix("agent:") { q = String(q.dropFirst(6)).trimmingCharacters(in: .whitespaces); forceTier = 2 }
        guard !q.isEmpty, !Memory.normalize(q).isEmpty else { out.answer = Self.notUnderstood; return out }

        if let macro = macro(for: q) {
            return await runMacro(macro, approver: approver, status: status)
        }

        let lower = " " + q.lowercased() + " "
        let looksComplex = Self.complexMarkers.contains { lower.contains($0) }
        if forceTier == 2 || (looksComplex && forceTier == nil) {
            return finish(await tier2(q, approver: approver, status: status, out: out), query: q)
        }

        if let cached = memory?.cacheLookup(q), let args = Self.parseArgs(cached.argsJSON) {
            status("From memory…")
            let r = await execute(cached.tool, args, approver: approver, status: status)
            if r.cancelled { out.cancelled = true; return out }
            if r.ok {
                out.tier = 0; out.results = [r]
                render(r, into: &out)
                return finish(out, query: q)
            }
            memory?.cacheInvalidate(q)
        }

        if FoundationTier.isAvailable {
            status("Understanding…")
            if let cmd = try? await FoundationTier.route(q, context: await routingContext()) {
                let confident = cmd.confidence >= Settings.confidenceThreshold
                if cmd.tool == .unknown {
                    out.tier = 1
                    out.answer = Self.notUnderstood
                    return out
                }
                if confident, cmd.tool != .complex {
                    out.tier = 1
                    if let handled = await handle(cmd, query: q, approver: approver, status: status, out: out) {
                        return finish(handled, query: q)
                    }
                }
            }
        }

        return finish(await tier2(q, approver: approver, status: status, out: out), query: q)
    }

    // MARK: Tier 1 → tool mapping

    private func handle(_ c: Command, query: String, approver: Approver, status: @escaping (String) -> Void, out: AgentOutput) async -> AgentOutput? {
        var out = out
        let target = c.target.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchText = c.query.trimmingCharacters(in: .whitespacesAndNewlines)

        switch c.tool {
        case .openApplication, .quitApplication:
            let raw = c.app.isEmpty ? target : c.app
            guard !raw.isEmpty else { return nil }
            let name = InstalledApps.resolve(raw)
            let tool = c.tool == .openApplication ? "openApplication" : "quitApplication"
            return await single(tool, ["name": name], query: query, out: out, approver: approver, status: status) {
                self.memory?.bump(kind: "app", name: name)
            }

        case .openProject, .openPath, .revealInFinder:
            let tool = c.tool == .revealInFinder ? "revealInFinder" : "openPath"
            var args: [String: Any] = [:]
            if c.tool == .openProject { args["app"] = c.app.isEmpty ? "Visual Studio Code" : InstalledApps.resolve(c.app) }
            else if !c.app.isEmpty, c.tool == .openPath { args["app"] = InstalledApps.resolve(c.app) }
            let term = target.isEmpty ? searchText : target
            guard !term.isEmpty else { return nil }
            if term.hasPrefix("~") || term.hasPrefix("/") {
                args["path"] = Settings.expand(term)
                return await single(tool, args, query: query, out: out, approver: approver, status: status) {
                    self.memory?.bump(kind: "path", name: Settings.expand(term))
                }
            }
            let resolver = await self.resolver()
            let candidates = resolver.resolve(term, memory: memory)
            let scores = candidates.map { ProjectResolver.score(term: term, name: $0.name) }
            let strong = (candidates.count == 1 && scores[0] >= 60) || (scores.count > 1 && scores[0] >= 80 && scores[1] < scores[0]) || memory?.alias(term) != nil
            if let first = candidates.first, strong {
                args["path"] = first.path
                return await single(tool, args, query: query, out: out, approver: approver, status: status) {
                    self.memory?.learnAlias(term, path: first.path)
                    self.memory?.bump(kind: "path", name: first.path)
                }
            }
            if !candidates.isEmpty {
                let verb = c.tool == .revealInFinder ? "Reveal" : "Open"
                let inApp = (args["app"] as? String).map { " in \($0)" } ?? ""
                out.suggestions = candidates.prefix(6).map { p in
                    var a = args; a["path"] = p.path
                    return Suggestion(icon: Self.icon(forType: p.type), title: "\(verb) \(p.name)\(inApp)", subtitle: "\(Self.short(p.path)) · \(p.type)",
                                      section: "Projects", tool: tool, args: a, learnAlias: (term, p.path))
                }
                return out
            }
            let found = await execute("findFiles", ["name": term], approver: approver, status: status)
            out.results = [found]
            render(found, into: &out, openWith: args["app"] as? String, aliasTerm: term)
            if out.suggestions.isEmpty { out.answer = "Nothing named like “\(term)” found." }
            return out

        case .findFiles:
            let name = target.isEmpty ? searchText : target
            guard !name.isEmpty else { return nil }
            return await single("findFiles", ["name": name], query: query, out: out, approver: approver, status: status)

        case .searchFiles:
            let text = searchText.isEmpty ? target : searchText
            guard !text.isEmpty else { return nil }
            return await single("searchFiles", ["query": text], query: query, out: out, approver: approver, status: status)

        case .searchCode:
            let pattern = searchText.isEmpty ? target : searchText
            guard !pattern.isEmpty else { return nil }
            var args: [String: Any] = ["pattern": pattern]
            if !target.isEmpty, target != pattern, let p = await resolver().resolve(target, memory: memory).first { args["scope"] = p.path }
            return await single("searchCode", args, query: query, out: out, approver: approver, status: status)

        case .readFile:
            guard !target.isEmpty else { return nil }
            if target.hasPrefix("~") || target.hasPrefix("/") {
                return await single("readFile", ["path": Settings.expand(target)], query: query, out: out, approver: approver, status: status)
            }
            let found = await execute("findFiles", ["name": target], approver: approver, status: status)
            out.results = [found]; render(found, into: &out)
            return out

        case .listDirectory:
            var path = target
            if path.isEmpty { return await single("listProjects", [:], query: query, out: out, approver: approver, status: status) }
            if !(path.hasPrefix("~") || path.hasPrefix("/")) {
                guard let p = await resolver().resolve(path, memory: memory).first else { return nil }
                path = p.path
            }
            return await single("listDirectory", ["path": Settings.expand(path)], query: query, out: out, approver: approver, status: status)

        case .listProjects: return await single("listProjects", [:], query: query, out: out, approver: approver, status: status)
        case .listRunningApps: return await single("listRunningApps", [:], query: query, out: out, approver: approver, status: status)
        case .getSystemStats: return await single("getSystemStats", [:], query: query, out: out, approver: approver, status: status)
        case .moveItems, .trashItems, .complex, .unknown: return nil
        }
    }

    private func single(_ tool: String, _ args: [String: Any], query: String, out: AgentOutput, approver: Approver,
                        status: @escaping (String) -> Void, learn: (() -> Void)? = nil) async -> AgentOutput {
        var out = out
        let r = await execute(tool, args, approver: approver, status: status)
        out.results = [r]
        if r.cancelled { out.cancelled = true; return out }
        if r.ok {
            if Permission.risk(named: tool) == .auto { memory?.cacheStore(query, tool: tool, argsJSON: Self.json(args)) }
            learn?()
        }
        render(r, into: &out, openWith: args["app"] as? String)
        return out
    }

    // MARK: Tier 2

    private func tier2(_ q: String, approver: Approver, status: @escaping (String) -> Void, out: AgentOutput) async -> AgentOutput {
        var out = out
        out.tier = 2
        let gate = ResourceGate.check()
        guard gate.ok else {
            out.answer = "Skipped the larger model to protect your Mac: \(gate.reason ?? "resources are tight"). Try a simpler request."
            return out
        }
        do {
            try await MCPClient.shared.ensureStarted()
        } catch {
            out.answer = "Tool server failed to start: \(error.localizedDescription)"
            return out
        }
        let tools = MCPClient.shared.tools.filter { $0.name != "ping" }
        let projects = await resolver().projects
        let context = "Home folder: \(NSHomeDirectory()). Allowed folders: \(Settings.allowedRoots.joined(separator: ", ")). "
            + "Known projects: " + projects.prefix(40).map { "\($0.name) (\(Self.short($0.path)), \($0.type))" }.joined(separator: "; ") + "."
        var results: [ActionResult] = []
        func attempt(_ model: String) async throws -> String {
            try await LMStudioTier.run(query: q, model: model, tools: tools, context: context, status: status) { name, args in
                let r = await self.execute(name, args, approver: approver, status: status)
                results.append(r)
                return r.cancelled ? Self.cancelledMarker : (r.ok ? r.text : "Error: \(r.text)")
            }
        }
        var model = gate.useSmall ? Settings.fallbackModel : Settings.model
        do {
            var answer: String
            do { answer = try await attempt(model) }
            catch LMStudioTier.LMError.modelMissing(let m) where m == Settings.fallbackModel {
                model = Settings.model
                answer = try await attempt(model)
            }
            out.results = results
            out.model = model
            out.answer = answer.isEmpty ? "Done." : answer
            out.cancelled = results.contains { $0.cancelled }
            if gate.useSmall, model == Settings.fallbackModel { out.note = "Used \(model) because \(gate.reason ?? "memory is tight")." }
            if results.count == 1, results[0].ok, Permission.risk(named: results[0].tool) == .auto {
                memory?.cacheStore(q, tool: results[0].tool, argsJSON: Self.json(results[0].args))
            }
        } catch {
            out.results = results
            out.answer = "Couldn't use the local model: \(error.localizedDescription)"
        }
        return out
    }

    // MARK: Execution with permission

    func execute(_ tool: String, _ args: [String: Any], approver: Approver, status: @escaping (String) -> Void) async -> ActionResult {
        do { try await MCPClient.shared.ensureStarted() }
        catch { return ActionResult(tool: tool, args: args, text: "Tool server failed to start: \(error.localizedDescription)", ok: false) }
        let risk = Permission.risk(named: tool)
        if risk != .auto {
            let key = risk == .confirm ? Permission.alwaysKey(tool: tool, args: args) : nil
            if !Permission.isAlwaysAllowed(key) {
                let (title, detail) = Permission.describe(tool: tool, args: args)
                let folder = Permission.folder(in: args).map { ($0 as NSString).lastPathComponent }
                let pending = PendingAction(icon: Permission.icon(for: tool), tool: tool, args: args, title: title, detail: detail, destructive: risk == .destructive,
                                            alwaysKey: key, alwaysLabel: key != nil ? "Always allow in \(folder ?? "this folder")" : nil)
                switch await approver.approve(pending) {
                case .cancel: return ActionResult(tool: tool, args: args, text: "Cancelled.", ok: false, cancelled: true)
                case .allowAlways: Permission.rememberAlways(key)
                case .allow: break
                }
            }
        }
        status("Running \(tool)…")
        do {
            let (text, isError) = try await MCPClient.shared.call(tool, args: args)
            return ActionResult(tool: tool, args: args, text: text, ok: !isError)
        } catch {
            return ActionResult(tool: tool, args: args, text: error.localizedDescription, ok: false)
        }
    }

    /// Runs a suggestion the user picked and learns the alias.
    func runSuggestion(_ s: Suggestion, approver: Approver, status: @escaping (String) -> Void) async -> ActionResult {
        let r = await execute(s.tool, s.args, approver: approver, status: status)
        if r.ok {
            if let a = s.learnAlias { memory?.learnAlias(a.term, path: a.path) }
            if let p = s.args["path"] as? String { memory?.bump(kind: "path", name: p) }
        }
        return r
    }

    // MARK: Macros

    func macro(for q: String) -> Memory.Macro? {
        guard let memory else { return nil }
        if let m = memory.macro(named: q) { return m }
        let lower = q.lowercased()
        if lower.hasPrefix("run ") { return memory.macro(named: String(q.dropFirst(4))) }
        return nil
    }

    func saveMacro(named name: String) -> String {
        let steps = lastResults.filter { $0.ok }.map { ["tool": $0.tool, "args": $0.args] }
        guard !steps.isEmpty, let memory else { return "Nothing to save yet. Run some actions first, then: save macro <name>." }
        memory.saveMacro(name: name, stepsJSON: Self.json(steps))
        return "Saved macro “\(name)” with \(steps.count) step\(steps.count == 1 ? "" : "s"). Run it by typing its name."
    }

    private func runMacro(_ m: Memory.Macro, approver: Approver, status: @escaping (String) -> Void) async -> AgentOutput {
        var out = AgentOutput()
        out.tier = 0
        guard let data = m.stepsJSON.data(using: .utf8), let steps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            out.answer = "Macro “\(m.name)” is corrupted."; return out
        }
        for step in steps {
            guard let tool = step["tool"] as? String else { continue }
            let r = await execute(tool, step["args"] as? [String: Any] ?? [:], approver: approver, status: status)
            out.results.append(r)
            if r.cancelled { out.cancelled = true; break }
        }
        memory?.touchMacro(m.name)
        let okCount = out.results.filter(\.ok).count
        out.answer = "Macro “\(m.name)”: \(okCount)/\(steps.count) steps done." + (out.results.filter { !$0.ok }.map { "\n\($0.tool): \($0.text)" }.joined())
        return out
    }

    // MARK: Learning hooks

    private func finish(_ out: AgentOutput, query: String) -> AgentOutput {
        var out = out
        lastResults = out.results.filter(\.ok)
        if lastResults.count >= 2, let memory {
            let hash = lastResults.map { "\($0.tool):\(Self.json($0.args))" }.joined(separator: "|")
            if memory.noteSequence(hash) == 3 {
                out.note = (out.note.map { $0 + " " } ?? "") + "You've done this \(lastResults.count)-step sequence 3 times. Save it: type “save macro <name>”."
            }
        }
        return out
    }

    // MARK: Context

    private func routingContext() async -> RoutingContext {
        let projects = await resolver().projects
        return RoutingContext(
            aliases: memory?.topAliases(15).map { "\($0.term) → \(Self.short($0.path))" } ?? [],
            apps: memory?.top(kind: "app", n: 10) ?? [],
            projects: Array(projects.prefix(40).map(\.name)))
    }

    func resolver() async -> ProjectResolver {
        if let cached = projectsCache { return ProjectResolver(projects: cached) }
        var projects: [Project] = []
        if let (text, isError) = try? await MCPClient.shared.call("listProjects", args: [:]), !isError {
            projects = ProjectResolver.parse(text)
        }
        projectsCache = projects
        return ProjectResolver(projects: projects)
    }

    func refreshProjects() { projectsCache = nil }

    // MARK: Rendering

    private func render(_ r: ActionResult, into out: inout AgentOutput, openWith app: String? = nil, aliasTerm: String? = nil) {
        guard r.ok else { out.answer = r.text; return }
        var textLines: [String] = []
        for line in r.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let pathPart = line.split(separator: "\t").first.map(String.init) ?? line
            let display = pathPart.split(separator: ":").first.map(String.init) ?? pathPart   // "file:line:text" → file
            if (display.hasPrefix("~/") || display.hasPrefix("/")), out.suggestions.count < 20, r.tool != "listDirectory", r.tool != "readFile" {
                let abs = Settings.expand(display)
                var isDir: ObjCBool = false
                let exists = FileManager.default.fileExists(atPath: abs, isDirectory: &isDir)
                var args: [String: Any] = ["path": abs]
                if let app { args["app"] = app }
                let type = line.split(separator: "\t").count > 1 ? String(line.split(separator: "\t")[1]) : (isDir.boolValue ? "folder" : "file")
                let subtitle = pathPart == display ? Self.short(abs) : String(line.dropFirst(pathPart.count + 1).prefix(90))
                if exists {
                    let section = r.tool == "listProjects" ? "Projects" : (isDir.boolValue ? "Folders" : "Files")
                    out.suggestions.append(Suggestion(icon: Self.icon(forType: type), title: (abs as NSString).lastPathComponent + (isDir.boolValue ? "/" : ""),
                                                      subtitle: r.tool == "listProjects" ? "\(Self.short(abs)) · \(type)" : subtitle, section: section,
                                                      tool: "openPath", args: args, learnAlias: aliasTerm.map { ($0, abs) }))
                    continue
                }
            }
            textLines.append(line)
        }
        let rest = textLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        out.answer = rest.isEmpty ? nil : rest
        if out.suggestions.isEmpty, out.answer == nil { out.answer = r.text }
    }

    // MARK: Helpers

    static func short(_ p: String) -> String { p.hasPrefix(NSHomeDirectory()) ? "~" + p.dropFirst(NSHomeDirectory().count) : p }

    static func icon(forType t: String) -> String {
        switch t {
        case "react-native", "node", "nextjs", "react": return "shippingbox.fill"
        case "xcode", "xcode-workspace", "swift-package": return "hammer.fill"
        case "android": return "smartphone"
        case "python": return "chevron.left.forwardslash.chevron.right"
        case "file": return "doc.text.fill"
        default: return "folder.fill"
        }
    }

    static func json(_ obj: Any) -> String {
        (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func parseArgs(_ s: String) -> [String: Any]? {
        s.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
}
