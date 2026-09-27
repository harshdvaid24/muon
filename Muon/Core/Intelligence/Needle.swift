import Foundation

/// Optional, experimental: Needle 3 (cactus-needle), a 121M-parameter 2-bit tool-calling model served locally by
/// scripts/needle-serve.py. About 50 ms per decision. Used only when it is confident, and only for tools that
/// cannot change anything without a confirmation card. Settings › Needle turns it on; the footer shows when it answered.
enum Needle {
    static var baseURL: String { Settings.d.string(forKey: "needleURL") ?? "http://127.0.0.1:8766" }
    static var enabled: Bool { Settings.d.bool(forKey: "needleEnabled") }
    static var threshold: Double { Settings.d.object(forKey: "needleThreshold") as? Double ?? 0.9 }

    /// The simple routing set the on-device model also uses, minus anything that moves or deletes files.
    static let routable: Set<String> = ["openApplication", "openPath", "revealInFinder", "quitApplication", "findFiles", "searchFiles", "searchCode", "readFile",
                                        "listDirectory", "listProjects", "listRunningApps", "getSystemStats", "webSearch", "openInBrowser", "largestFiles",
                                        "findDuplicates", "listDevices", "jobStatus", "listMenus"]

    struct Call: Equatable {
        let tool: String
        let args: [String: String]
        let confidence: Double
        let ms: Int
        let reasoning: String
        var anyArgs: [String: Any] { args }
    }

    private static var health: (at: Date, ok: Bool)?

    static func isReachable() async -> Bool {
        guard enabled, let url = URL(string: baseURL + "/health") else { return false }
        if let h = health, Date().timeIntervalSince(h.at) < 30 { return h.ok }
        var req = URLRequest(url: url); req.timeoutInterval = 1.5
        let ok = (try? await URLSession.shared.data(for: req)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        health = (Date(), ok)
        return ok
    }

    static func route(_ q: String, tools: [MCPClient.Tool]) async -> Call? {
        guard enabled, let url = URL(string: baseURL + "/v1/route") else { return nil }
        let toolsJSON: [[String: Any]] = tools.filter { routable.contains($0.name) }.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] }
        guard !toolsJSON.isEmpty, let body = try? JSONSerialization.data(withJSONObject: ["query": q, "tools": toolsJSON]) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.timeoutInterval = 6; req.httpBody = body
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return parse(data)
    }

    /// The first call in a server reply; string arguments only (every routable tool takes strings).
    static func parse(_ data: Data) -> Call? {
        guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let calls = o["calls"] as? [[String: Any]],
              let first = calls.first, let name = first["name"] as? String else { return nil }
        var args: [String: String] = [:]
        for (k, v) in first["arguments"] as? [String: Any] ?? [:] { args[k] = v as? String ?? (v as? NSNumber).map { $0.stringValue } ?? String(describing: v) }
        return Call(tool: name, args: args, confidence: o["confidence"] as? Double ?? 0, ms: o["ms"] as? Int ?? 0, reasoning: o["reasoning"] as? String ?? "")
    }
}
