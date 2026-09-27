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

    /// A short spoken reply for greetings / small talk, on-device.
    static func chat(_ query: String) async throws -> String {
        let session = LanguageModelSession(instructions: chatInstructions)
        return try await session.respond(to: query).content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let chatInstructions = "You are Muon, a friendly local assistant on this Mac. Reply in one or two short sentences. You can open apps, find and manage files, quit apps, run app menu commands, search the web, and answer quick questions. If greeted, greet back and briefly say what you can do. Do not use markdown."

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
        - webSearch: look something up on the internet (general knowledge, definitions, current events, "search for", "google", "what is / who is" about the world).
        - openInBrowser: open a web page or search results in the browser.
        - largestFiles: the biggest files in a folder (free up disk space).
        - findDuplicates: duplicate files in a folder.
        - listDevices: which iOS simulators / Android emulators / devices are available.
        - jobStatus: status of background jobs or builds ("is the build done", "job status").
        - chat: a greeting, thanks, or small talk ("hi", "hello", "how are you", "thanks"), or a simple conversational question that needs a spoken reply rather than an action on this Mac.
        - complex: needs several tools, filtering, comparison, code understanding, or planning.
        - unknown: unintelligible only.

        Rules: one tool only; anything with "and", "then", conditions, or age/size filters is complex. Keep target in the user's words. Never invent paths. A greeting or chit-chat is chat, never openApplication. Put the thing to look up in query for webSearch.
        Examples: "what is inside ~/Downloads" → listDirectory target "~/Downloads"; "show my projects" → listProjects;
        "open portfolio in xcode" → openProject target "portfolio" app "Xcode"; "find pdfs about tax" → searchFiles query "pdf tax";
        "where is package.json in weather-app" → findFiles target "package.json"; "is my mac hot" → getSystemStats;
        "hi" / "hello" / "how are you" → chat; "thanks" → chat; "search for the tallest mountain" → webSearch query "tallest mountain";
        "what is the capital of Japan" → webSearch query "capital of Japan"; "open youtube.com" → openInBrowser;
        "what's taking space in ~/Downloads" → largestFiles target "~/Downloads"; "find duplicate files in Downloads" → findDuplicates target "Downloads";
        "which simulators do I have" → listDevices; "is my build done" → jobStatus.
        """
        if !c.projects.isEmpty { s += "\nKnown projects: \(c.projects.joined(separator: ", "))." }
        if !c.aliases.isEmpty { s += "\nLearned names: \(c.aliases.joined(separator: ", "))." }
        if !c.apps.isEmpty { s += "\nFrequently used apps: \(c.apps.joined(separator: ", "))." }
        return s
    }
}
