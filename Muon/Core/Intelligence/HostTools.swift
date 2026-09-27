import Foundation

/// Tools that run inside the app because they need Apple frameworks (Vision, Speech, PDFKit, FoundationModels).
/// They appear to the planner exactly like MCP tools and go through the same permission rules.
struct HostTool {
    let name: String
    let description: String
    let schema: [String: Any]
    let readOnly: Bool
    let destructive: Bool
    let run: ([String: Any]) async throws -> String

    var asMCPTool: MCPClient.Tool {
        MCPClient.Tool(name: name, description: description, schema: schema, readOnly: readOnly, destructive: destructive)
    }

    /// Convenience for a JSON schema of string/number/boolean properties.
    static func schema(_ props: [(String, String, String)], required: [String]) -> [String: Any] {
        var p: [String: Any] = [:]
        for (name, type, desc) in props { p[name] = ["type": type, "description": desc] }
        return ["type": "object", "properties": p, "required": required]
    }
}

enum HostTools {
    static var all: [HostTool] {
        TextTools.tools + Documents.tools + VisionTools.tools + CrashLogs.tools + Transcriber.tools + Receipts.tools
    }

    static func tool(named name: String) -> HostTool? { all.first { $0.name == name } }

    static func string(_ args: [String: Any], _ key: String) -> String {
        (args[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum IntelligenceError: LocalizedError {
    case noInput(String), unavailable(String), tooLong, refused(String), notFound(String)
    var errorDescription: String? {
        switch self {
        case .noInput(let hint): return hint
        case .unavailable(let what): return "\(what) is not available on this Mac."
        case .tooLong: return "That text is too long for the on-device model and LM Studio is not running. Start LM Studio (lms server start) for long inputs."
        case .refused(let why): return "The model declined: \(why)"
        case .notFound(let p): return "Couldn't find \(p)."
        }
    }
}
