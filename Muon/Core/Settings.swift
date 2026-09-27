import Foundation

/// All user-tunable values. Keys are shared with SettingsView's @AppStorage bindings.
enum Settings {
    static let d = UserDefaults.standard

    enum Key {
        static let lmBaseURL = "lmBaseURL", model = "model", fallbackModel = "fallbackModel", modelTTL = "modelTTL"
        static let nodePath = "nodePath", mcpServerPath = "mcpServerPath", allowedRoots = "allowedRoots"
        static let confidence = "confidenceThreshold", lmsPath = "lmsPath", alwaysAllow = "alwaysAllow"
        static let voiceAutoListen = "voiceAutoListen", speakReplies = "speakReplies"
    }

    static var voiceAutoListen: Bool { d.bool(forKey: Key.voiceAutoListen) }
    static var speakReplies: Bool { d.object(forKey: Key.speakReplies) as? Bool ?? true }

    static var lmBaseURL: String { d.string(forKey: Key.lmBaseURL) ?? "http://127.0.0.1:1234" }
    static var model: String { d.string(forKey: Key.model) ?? "qwen/qwen3.5-9b" }
    static var fallbackModel: String { d.string(forKey: Key.fallbackModel) ?? "qwen/qwen3.5-4b" }
    static var modelTTL: Int { d.object(forKey: Key.modelTTL) as? Int ?? 300 }
    /// Bounded context so LM Studio never JIT-loads with a 100k+ token KV cache.
    static var contextLength: Int { d.object(forKey: "contextLength") as? Int ?? 16384 }
    static var confidenceThreshold: Double { d.object(forKey: Key.confidence) as? Double ?? 0.6 }
    static var lmsPath: String { d.string(forKey: Key.lmsPath) ?? NSHomeDirectory() + "/.lmstudio/bin/lms" }

    static var allowedRoots: [String] {
        d.stringArray(forKey: Key.allowedRoots) ?? ["~/Projects", "~/Work", "~/Downloads", "~/Documents", "~/Desktop"]
    }

    static var nodePath: String {
        if let p = d.string(forKey: Key.nodePath), !p.isEmpty { return p }
        return probeNode() ?? "/usr/local/bin/node"
    }

    static var mcpServerPath: String {
        if let p = d.string(forKey: Key.mcpServerPath), !p.isEmpty { return p }
        let bundled = Bundle.main.resourcePath.map { $0 + "/mac-tools/dist/index.js" }
        if let b = bundled, FileManager.default.fileExists(atPath: b) { return b }
        return NSHomeDirectory() + "/Work/Muon/mac-tools/dist/index.js"
    }

    /// Latest nvm node, then Homebrew, then /usr/local.
    static func probeNode() -> String? {
        let fm = FileManager.default
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvm) {
            let sorted = versions.filter { $0.hasPrefix("v") }.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            for v in sorted where fm.isExecutableFile(atPath: "\(nvm)/\(v)/bin/node") { return "\(nvm)/\(v)/bin/node" }
        }
        for p in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] where fm.isExecutableFile(atPath: p) { return p }
        return nil
    }

    static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }
}
