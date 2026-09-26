import Foundation
import FoundationModels

/// Every single-step intent the tier-1 router can produce. Names match mac-tools tool names,
/// except `openProject` (resolved by the host to openPath), `complex` and `unknown`.
@Generable
enum ToolName: CaseIterable {
    case openApplication, openProject, openPath, revealInFinder, quitApplication
    case findFiles, searchFiles, searchCode, readFile, listDirectory, listProjects
    case listRunningApps, getSystemStats, moveItems, trashItems
    case complex, unknown
}

@Generable
struct Command {
    @Guide(description: "The single best tool for the request. Use complex when several steps or reasoning are needed. Use unknown when the text is not a request for this assistant.")
    var tool: ToolName

    @Guide(description: "Application name if the request names one (Xcode, Safari, Visual Studio Code, Spotify…); otherwise empty string")
    var app: String

    @Guide(description: "Project, folder or file the user refers to, in the user's own words; otherwise empty string")
    var target: String

    @Guide(description: "Search text, code pattern or Spotlight query for search tools; otherwise empty string")
    var query: String

    @Guide(description: "Confidence that this tool choice is right, 0 to 1")
    var confidence: Double
}

extension ToolName {
    var name: String { String(describing: self) }
}
