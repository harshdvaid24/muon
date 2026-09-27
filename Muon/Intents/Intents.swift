import AppIntents
import AppKit
import Foundation

/// Approver used when an intent runs from Spotlight/Shortcuts: reuse the palette if the app is up, else deny.
enum IntentApprover {
    @MainActor static func current() -> Approver {
        (NSApp.delegate as? AppDelegate)?.palette ?? DenyApprover()
    }
    struct DenyApprover: Approver {
        func approve(_ action: PendingAction) async -> ApprovalDecision { .cancel }
    }
}

// MARK: Entities

struct ProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Project"
    static var defaultQuery = ProjectQuery()

    var id: String { path }
    let name: String
    let path: String
    let type: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Agent.short(path)) · \(type)")
    }

    init(_ p: Project) { name = p.name; path = p.path; type = p.type }
}

struct ProjectQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ProjectEntity] {
        await Agent.shared.resolver().projects.filter { identifiers.contains($0.path) }.map(ProjectEntity.init)
    }
    func entities(matching string: String) async throws -> [ProjectEntity] {
        await Agent.shared.resolver().resolve(string, memory: Agent.shared.memory).map(ProjectEntity.init)
    }
    func suggestedEntities() async throws -> [ProjectEntity] {
        await Agent.shared.resolver().projects.prefix(20).map(ProjectEntity.init)
    }
}

struct MacroEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Muon Macro"
    static var defaultQuery = MacroQuery()

    var id: String { name }
    let name: String
    let steps: Int

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(steps) steps") }

    init(_ m: Memory.Macro) {
        name = m.name
        steps = (m.stepsJSON.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] })?.count ?? 0
    }
}

struct MacroQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MacroEntity] {
        (Agent.shared.memory?.macros() ?? []).filter { identifiers.contains($0.name) }.map(MacroEntity.init)
    }
    func entities(matching string: String) async throws -> [MacroEntity] {
        (Agent.shared.memory?.macros() ?? []).filter { $0.name.localizedCaseInsensitiveContains(string) }.map(MacroEntity.init)
    }
    func suggestedEntities() async throws -> [MacroEntity] { (Agent.shared.memory?.macros() ?? []).map(MacroEntity.init) }
}

// MARK: Intents

struct OpenProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Project"
    static var description = IntentDescription("Opens one of your project folders in an editor.")
    static var openAppWhenRun = false

    @Parameter(title: "Project") var project: ProjectEntity
    @Parameter(title: "Editor", default: "Visual Studio Code") var editor: String

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$project) in \(\.$editor)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let approver = await IntentApprover.current()
        let r = await Agent.shared.execute("openPath", ["path": project.path, "app": InstalledApps.resolve(editor)], approver: approver) { _ in }
        if r.ok { Agent.shared.memory?.bump(kind: "path", name: project.path) }
        return .result(dialog: "\(r.text)")
    }
}

struct AskMuonIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Muon"
    static var description = IntentDescription("Runs a natural-language request through Muon's local tiers and returns the answer.")
    static var openAppWhenRun = false

    @Parameter(title: "Request") var request: String

    static var parameterSummary: some ParameterSummary { Summary("Ask Muon to \(\.$request)") }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let approver = await IntentApprover.current()
        let out = await Agent.shared.run(request, approver: approver) { _ in }
        var text = out.answer ?? ""
        if !out.suggestions.isEmpty { text += (text.isEmpty ? "" : "\n") + out.suggestions.map { $0.subtitle ?? $0.title }.joined(separator: "\n") }
        if let n = out.note { text += "\n" + n }
        if text.isEmpty { text = out.cancelled ? "Cancelled." : "Done." }
        return .result(value: text, dialog: "\(text)")
    }
}

struct RunMacroIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Muon Macro"
    static var description = IntentDescription("Runs a saved Muon macro (a learned sequence of actions).")
    static var openAppWhenRun = false

    @Parameter(title: "Macro") var macro: MacroEntity

    static var parameterSummary: some ParameterSummary { Summary("Run \(\.$macro)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let approver = await IntentApprover.current()
        let out = await Agent.shared.run(macro.name, approver: approver) { _ in }
        return .result(dialog: "\(out.answer ?? "Done.")")
    }
}

struct MuonShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenProjectIntent(), phrases: ["Open project in \(.applicationName)", "Open \(\.$project) in \(.applicationName)"],
                    shortTitle: "Open Project", systemImageName: "folder")
        AppShortcut(intent: AskMuonIntent(), phrases: ["Ask \(.applicationName)"],
                    shortTitle: "Ask Muon", systemImageName: "sparkle.magnifyingglass")
        AppShortcut(intent: RunMacroIntent(), phrases: ["Run \(\.$macro) in \(.applicationName)"],
                    shortTitle: "Run Macro", systemImageName: "play.circle")
    }
}
