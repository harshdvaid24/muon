import Foundation

/// "start agent for kathak", "start claude code agent for kathak project", "open codex in weather-app":
/// a terminal in that project with the interactive coding assistant running. The user drives it from there.
struct AgentLaunch: Equatable {
    let project: String
    let command: String   // claude · codex · gemini · aider · "" (just a shell)

    private static let patterns = [
        #"^(?:start|open|launch|run|begin|fire up|spin up)(?: the| a| an| my)?(?: claude(?: code)?| codex| gemini| aider| coding| ai)?(?: agent| session| terminal| shell| cli)?(?: window)?(?: for| in| on| at| inside)(?: the| my)? (.+?)(?: app| project| repo| folder)?$"#,
        #"^(?:claude(?: code)?|codex|gemini|aider)(?: agent| session)? (?:for|in|on) (?:the |my )?(.+?)(?: app| project| repo)?$"#,
    ]

    static func parse(_ raw: String) -> AgentLaunch? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let lower = q.lowercased()
        guard lower.range(of: #"\b(agent|claude|codex|gemini|aider|coding|terminal|shell)\b"#, options: .regularExpression) != nil else { return nil }
        for p in patterns {
            guard let re = try? NSRegularExpression(pattern: p, options: .caseInsensitive),
                  let m = re.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)),
                  let r = Range(m.range(at: 1), in: q) else { continue }
            let project = String(q[r]).trimmingCharacters(in: CharacterSet(charactersIn: " .!,"))
            guard !project.isEmpty else { continue }
            let command = lower.contains("codex") ? "codex" : lower.contains("gemini") ? "gemini" : lower.contains("aider") ? "aider"
                : (lower.contains("claude") || lower.contains("agent") || lower.contains("coding")) ? "claude" : ""
            return AgentLaunch(project: project, command: command)
        }
        return nil
    }

    static func who(_ command: String) -> String {
        command.hasPrefix("claude") ? "Claude Code" : command.hasPrefix("codex") ? "Codex" : command.hasPrefix("gemini") ? "Gemini CLI" : command.hasPrefix("aider") ? "Aider" : "a shell"
    }
}
