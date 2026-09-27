import Foundation

enum ApprovalDecision { case allow, allowAlways, cancel }

enum Risk { case auto, confirm, destructive }

struct PendingAction {
    let icon: String
    let tool: String
    let args: [String: Any]
    let title: String
    let detail: String
    let destructive: Bool
    /// Set when "always allow" is offered: "tool|parentFolder".
    let alwaysKey: String?
    let alwaysLabel: String?
}

protocol Approver {
    func approve(_ action: PendingAction) async -> ApprovalDecision
}

/// Host-side permission policy. The MCP server enforces paths; this decides when to ask the user.
enum Permission {
    /// Not read-only, but safe: they only reveal or focus things.
    static let autoAllowed: Set<String> = ["openApplication", "openPath", "revealInFinder", "ping"]

    static func risk(_ tool: MCPClient.Tool) -> Risk {
        if tool.destructive { return .destructive }
        if tool.readOnly || autoAllowed.contains(tool.name) { return .auto }
        return .confirm
    }

    /// Unknown tools (not in tools/list) default to confirm — never auto.
    static func risk(named name: String) -> Risk {
        guard let t = MCPClient.shared.tool(named: name) else { return .confirm }
        return risk(t)
    }

    static func alwaysKey(tool: String, args: [String: Any]) -> String? {
        guard let folder = folder(in: args) else { return nil }
        return "\(tool)|\(folder)"
    }

    static func isAlwaysAllowed(_ key: String?) -> Bool {
        guard let key else { return false }
        return (Settings.d.stringArray(forKey: Settings.Key.alwaysAllow) ?? []).contains(key)
    }

    static func rememberAlways(_ key: String?) {
        guard let key else { return }
        var list = Settings.d.stringArray(forKey: Settings.Key.alwaysAllow) ?? []
        if !list.contains(key) { list.append(key); Settings.d.set(list, forKey: Settings.Key.alwaysAllow) }
    }

    /// The folder an "always allow" grant covers: the parent shared by every source path, or nil (→ always ask).
    static func folder(in args: [String: Any]) -> String? {
        if let paths = args["paths"] as? [String], !paths.isEmpty {
            let parents = Set(paths.map { (Settings.expand($0) as NSString).deletingLastPathComponent })
            return parents.count == 1 ? parents.first : nil
        }
        if let p = args["path"] as? String { return (Settings.expand(p) as NSString).deletingLastPathComponent }
        return nil
    }

    /// SF Symbol per tool, shown on the confirm card.
    static func icon(for tool: String) -> String {
        switch tool {
        case "moveItems", "copyItems", "createFolder": return "folder.fill.badge.plus"
        case "trashItems": return "trash.fill"
        case "renameItem": return "pencil"
        case "quitApplication": return "xmark.app.fill"
        case "killProcess": return "bolt.slash.fill"
        default: return "checkmark.shield.fill"
        }
    }

    static func describe(tool: String, args: [String: Any]) -> (title: String, detail: String) {
        func short(_ p: String) -> String { p.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        let paths = (args["paths"] as? [String] ?? []).map(short)
        switch tool {
        case "moveItems": return ("Move \(paths.count) item\(paths.count == 1 ? "" : "s") to \(short(args["destinationFolder"] as? String ?? "?"))", paths.joined(separator: "\n"))
        case "copyItems": return ("Copy \(paths.count) item\(paths.count == 1 ? "" : "s") to \(short(args["destinationFolder"] as? String ?? "?"))", paths.joined(separator: "\n"))
        case "trashItems": return ("Move \(paths.count) item\(paths.count == 1 ? "" : "s") to Trash", paths.joined(separator: "\n"))
        case "renameItem": return ("Rename \(short(args["path"] as? String ?? "?"))", "→ \(args["newName"] as? String ?? "?")")
        case "createFolder": return ("Create folder", short(args["path"] as? String ?? "?"))
        case "quitApplication": return ("Quit \(args["name"] as? String ?? "app")", "It may ask you to save unsaved work.")
        case "killProcess": return ("Force-terminate process \(args["pid"] ?? "?")", "Unsaved work in that process will be lost.")
        default:
            let detail = args.map { "\($0.key): \(short(String(describing: $0.value)))" }.sorted().joined(separator: "\n")
            return ("Run \(tool)", detail)
        }
    }
}
