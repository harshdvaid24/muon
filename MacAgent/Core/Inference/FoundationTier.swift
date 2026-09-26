import Foundation
import FoundationModels

struct RoutingContext {
    var aliases: [String] = []
    var apps: [String] = []
    var projects: [String] = []
}

/// Tier 1: Apple's on-device model. Zero app RAM (OS-managed), ~0.5 s, guided generation into `Command`.
enum FoundationTier {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static var unavailableReason: String? {
        if case .unavailable(let reason) = SystemLanguageModel.default.availability { return String(describing: reason) }
        return nil
    }

    static func route(_ query: String, context: RoutingContext) async throws -> Command {
        let session = LanguageModelSession(instructions: instructions(context))
        let response = try await session.respond(to: query, generating: Command.self, options: GenerationOptions(sampling: .greedy))
        return response.content
    }

    static func instructions(_ c: RoutingContext) -> String {
        var s = """
        You classify one request to a macOS assistant into exactly one tool call. Reply only with the structured result.

        Tools:
        - openApplication: launch or switch to an app.
        - openProject: open a project folder or workspace in an editor (app = editor if named, else Visual Studio Code).
        - openPath: open a specific file or folder with its default app.
        - revealInFinder: show a file or folder in Finder.
        - quitApplication: quit an app.
        - findFiles: find files or folders by name.
        - searchFiles: find files by content, topic, kind or date (Spotlight).
        - searchCode: search inside source code for text or a pattern.
        - readFile: show the contents of one file.
        - listDirectory: list what is inside a folder.
        - listProjects: list the user's projects.
        - listRunningApps: running apps and their memory use.
        - getSystemStats: RAM, CPU, disk, battery, temperature.
        - moveItems: move files into a folder.
        - trashItems: delete files (they go to the Trash).
        - complex: needs several tools, filtering, comparison, code understanding, or planning.
        - unknown: not a request for this assistant, or unintelligible.

        Rules: one tool only; anything with "and", "then", conditions, or age/size filters is complex. Keep target in the user's words. Never invent paths.
        """
        if !c.projects.isEmpty { s += "\nKnown projects: \(c.projects.joined(separator: ", "))." }
        if !c.aliases.isEmpty { s += "\nLearned names: \(c.aliases.joined(separator: ", "))." }
        if !c.apps.isEmpty { s += "\nFrequently used apps: \(c.apps.joined(separator: ", "))." }
        return s
    }
}
