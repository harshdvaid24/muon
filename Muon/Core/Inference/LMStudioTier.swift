import AppKit
import Foundation

/// Tier 2: LM Studio (MLX) via the OpenAI-compatible API with tool calling. Model is JIT-loaded and
/// unloaded after `ttl` seconds idle, so it costs RAM only while a request is in flight.
enum LMStudioTier {
    enum LMError: LocalizedError {
        case unreachable, http(Int, String), badResponse, modelMissing(String)
        var errorDescription: String? {
            switch self {
            case .unreachable: return "LM Studio is not reachable at \(Settings.lmBaseURL). Start it with: lms server start"
            case .http(let c, let m): return "LM Studio error \(c): \(m)"
            case .badResponse: return "unexpected LM Studio response"
            case .modelMissing(let m): return "model \(m) is not downloaded. Run: lms get \(m) --mlx"
            }
        }
    }

    static let systemPrompt = """
    You are Muon, a local assistant that operates this Mac through tools. Be brief and concrete.
    Rules: use tools to look before acting; never guess paths; prefer batch tools (moveItems, trashItems) so the user confirms once;
    deleting always means trashItems; if a tool returns an error, explain it and stop. Paths outside the user's allowed folders are refused.
    Developer tasks: to run an app on a device use runOnDevice (listDevices shows names; it runs in the background and notifies);
    for CI or releases use listWorkflows, then triggerWorkflow; use workflowRuns and jobStatus to report progress.
    To free disk space use largestFiles and findDuplicates before suggesting any trashItems.
    When done, answer in plain text with a short summary of what happened. Do not use markdown tables.
    """

    static func isReachable() async -> Bool {
        var req = URLRequest(url: URL(string: Settings.lmBaseURL + "/v1/models")!)
        req.timeoutInterval = 3
        return (try? await URLSession.shared.data(for: req)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
    }

    static func availableModels() async -> [String] {
        var req = URLRequest(url: URL(string: Settings.lmBaseURL + "/v1/models")!)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }
    }

    /// Loaded models per LM Studio's native API (state == "loaded").
    static func loadedModels() async -> [String] {
        var req = URLRequest(url: URL(string: Settings.lmBaseURL + "/api/v0/models")!)
        req.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["data"] as? [[String: Any]] else { return [] }
        return list.filter { ($0["state"] as? String) == "loaded" }.compactMap { $0["id"] as? String }
    }

    /// Starts the LM Studio server if needed (`lms server start`). Returns when reachable or after ~12 s.
    static func ensureServer() async -> Bool {
        if await isReachable() { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Settings.lmsPath)
        p.arguments = ["server", "start"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return false }
        for _ in 0..<12 {
            try? await Task.sleep(for: .seconds(1))
            if await isReachable() { return true }
        }
        return false
    }

    /// Loads the model with a bounded context and TTL (instead of LM Studio's JIT defaults). Best effort.
    static func ensureLoaded(_ model: String, status: (String) -> Void) async {
        if await loadedModels().contains(model) { return }
        status("Loading \(model)…")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Settings.lmsPath)
        p.arguments = ["load", model, "--context-length", String(Settings.contextLength), "--ttl", String(Settings.modelTTL), "-y"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in p.terminationHandler = { _ in cont.resume() } }
    }

    static func unloadAll() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Settings.lmsPath)
        p.arguments = ["unload", "--all"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    /// Plain chat completion (no tools) for writing and document tasks. Picks the model the resource gate allows.
    static func complete(system: String, user: String, status: @escaping (String) -> Void = { _ in }) async throws -> String {
        guard await ensureServer() else { throw LMError.unreachable }
        let gate = ResourceGate.check()
        var model = gate.ok && !gate.useSmall ? Settings.model : Settings.fallbackModel
        let models = await availableModels()
        if !models.isEmpty, !models.contains(model) { model = models.contains(Settings.model) ? Settings.model : (models.first { $0.lowercased().contains("qwen") } ?? model) }
        await ensureLoaded(model, status: status)
        let body: [String: Any] = [
            "model": model, "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0.3, "max_tokens": 2500, "stream": false, "ttl": Settings.modelTTL,
            "reasoning_effort": "none",   // LM Studio: Qwen3.5 ignores enable_thinking; this is what turns reasoning off
        ]
        let resp = try await post("/v1/chat/completions", body)
        guard let msg = (resp["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any], let text = msg["content"] as? String else { throw LMError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Vision: send one or more images (downscaled JPEG) with a prompt to the local VLM.
    static func vision(imagePaths: [String], prompt: String, status: @escaping (String) -> Void) async throws -> String {
        guard await ensureServer() else { throw LMError.unreachable }
        let gate = ResourceGate.check()
        var model = gate.ok && !gate.useSmall ? Settings.model : Settings.fallbackModel
        let models = await availableModels()
        if !models.isEmpty, !models.contains(model) { model = models.first { $0.lowercased().contains("qwen") } ?? model }
        await ensureLoaded(model, status: status)
        status("Looking at the image\(imagePaths.count > 1 ? "s" : "")…")
        var content: [[String: Any]] = [["type": "text", "text": prompt]]
        for p in imagePaths {
            guard let jpeg = jpegData(path: p, maxSide: 1280) else { throw LMError.http(0, "could not read image \(p)") }
            content.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + jpeg.base64EncodedString()]])
        }
        let body: [String: Any] = ["model": model, "messages": [["role": "user", "content": content]], "temperature": 0.2, "max_tokens": 1200,
                                   "stream": false, "ttl": Settings.modelTTL,
                                   "reasoning_effort": "none"]   // LM Studio: Qwen3.5 ignores enable_thinking; this is what turns reasoning off
        let resp = try await post("/v1/chat/completions", body)
        guard let msg = (resp["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any], let text = msg["content"] as? String else { throw LMError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func jpegData(path: String, maxSide: CGFloat) -> Data? {
        guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = CGFloat(cg.width), h = CGFloat(cg.height), scale = min(1, maxSide / max(w, h))
        let size = NSSize(width: w * scale, height: h * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: cg, size: NSSize(width: w, height: h)).draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }

    /// Runs the tool-calling loop. `execute` performs a tool call (with permission) and returns its text.
    static func run(query: String, model: String, tools: [MCPClient.Tool],
                    context: String, status: @escaping (String) -> Void,
                    execute: (String, [String: Any]) async -> String) async throws -> String {
        guard await ensureServer() else { throw LMError.unreachable }
        let models = await availableModels()
        if !models.isEmpty, !models.contains(model) { throw LMError.modelMissing(model) }
        await ensureLoaded(model, status: status)

        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt + "\n" + context],
            ["role": "user", "content": query],
        ]
        let toolDefs: [[String: Any]] = tools.map {
            ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.schema]]
        }
        for step in 0..<8 {
            status(step == 0 ? "Thinking with \(model)…" : "Step \(step + 1)…")
            let body: [String: Any] = [
                "model": model, "messages": messages, "tools": toolDefs, "tool_choice": "auto",
                "temperature": 0.2, "max_tokens": 1500, "stream": false, "ttl": Settings.modelTTL,
                "reasoning_effort": "none",   // LM Studio: Qwen3.5 ignores enable_thinking; this is what turns reasoning off
            ]
            let resp = try await post("/v1/chat/completions", body)
            guard let choice = (resp["choices"] as? [[String: Any]])?.first, let msg = choice["message"] as? [String: Any] else { throw LMError.badResponse }
            var assistant: [String: Any] = ["role": "assistant", "content": (msg["content"] as? String) ?? ""]
            if let calls = msg["tool_calls"] as? [[String: Any]], !calls.isEmpty {
                assistant["tool_calls"] = calls
                messages.append(assistant)
                for call in calls {
                    let fn = call["function"] as? [String: Any] ?? [:]
                    let name = fn["name"] as? String ?? ""
                    let argsRaw = fn["arguments"]
                    var args: [String: Any] = [:]
                    if let s = argsRaw as? String, let d = s.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { args = o }
                    else if let o = argsRaw as? [String: Any] { args = o }
                    status("Running \(name)…")
                    let result = await execute(name, args)
                    if result == Agent.cancelledMarker { return "Cancelled." }
                    messages.append(["role": "tool", "tool_call_id": call["id"] as? String ?? UUID().uuidString, "content": result])
                }
                continue
            }
            return ((msg["content"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "Stopped after 8 steps without a final answer."
    }

    private static func post(_ path: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: Settings.lmBaseURL + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 180
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw LMError.http(code, String(data: data, encoding: .utf8)?.prefix(300).description ?? "") }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw LMError.badResponse }
        return obj
    }
}
