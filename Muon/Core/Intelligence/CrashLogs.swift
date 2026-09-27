import Foundation

/// Recent crash reports for "why did my app crash". Reads only ~/Library/Logs/DiagnosticReports (*.ips), read-only,
/// last 48 hours, at most 5 files: a deliberate, narrow exception to the protected-folder rule.
enum CrashLogs {
    static let dir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"

    struct Report { let file: String; let date: Date; let summary: String }

    static func recent(app: String? = nil, hours: Double = 48, limit: Int = 5) -> [Report] {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        let names = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".ips") || $0.hasSuffix(".crash") }
        var reports: [Report] = []
        for n in names {
            if let app, !n.lowercased().hasPrefix(app.lowercased()) { continue }
            let p = dir + "/" + n
            guard let m = (try? fm.attributesOfItem(atPath: p)[.modificationDate]) as? Date, m > cutoff,
                  let data = fm.contents(atPath: p), data.count < 4_000_000 else { continue }
            reports.append(Report(file: n, date: m, summary: summarize(String(decoding: data.prefix(600_000), as: UTF8.self))))
        }
        return Array(reports.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// Compact view of an .ips report: process, exception, termination reason and the faulting thread's top frames.
    static func summarize(_ raw: String) -> String {
        let parts = raw.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let body = try? JSONSerialization.jsonObject(with: Data(parts[1].utf8)) as? [String: Any] else {
            return raw.split(separator: "\n").prefix(40).joined(separator: "\n")
        }
        var out: [String] = []
        if let p = body["procName"] as? String { out.append("process: \(p)") }
        if let e = body["exception"] as? [String: Any] { out.append("exception: \(e["type"] ?? "?") \(e["signal"] ?? "") \(e["codes"] ?? "")") }
        if let t = body["termination"] as? [String: Any] { out.append("termination: \(t["indicator"] ?? "") \(t["reasons"] ?? "")") }
        if let ex = body["exceptionReason"] as? [String: Any], let s = ex["composedMessage"] as? String { out.append("reason: \(s)") }
        if let asi = body["asi"] as? [String: Any] { for (k, v) in asi { out.append("\(k): \((v as? [String])?.joined(separator: " | ") ?? "\(v)")") } }
        if let ft = body["faultingThread"] as? Int, let threads = body["threads"] as? [[String: Any]], ft < threads.count,
           let frames = threads[ft]["frames"] as? [[String: Any]], let images = body["usedImages"] as? [[String: Any]] {
            out.append("crashed thread \(ft):")
            for f in frames.prefix(12) {
                let idx = f["imageIndex"] as? Int ?? -1
                let img = idx >= 0 && idx < images.count ? (images[idx]["name"] as? String ?? "?") : "?"
                out.append("  \(img)  \(f["symbol"] as? String ?? "+\(f["imageOffset"] ?? 0)")")
            }
        }
        return out.joined(separator: "\n")
    }

    static let tools: [HostTool] = [
        HostTool(name: "recentCrashes", description: "Recent crash reports (last 48 h) for an app or all apps: process, exception, reason and the crashed thread's top frames. Use with explainText to diagnose.",
                 schema: HostTool.schema([("app", "string", "Process name filter, e.g. 'MyApp' (optional)")], required: []), readOnly: true, destructive: false) { a in
            let app = HostTools.string(a, "app")
            let r = recent(app: app.isEmpty ? nil : app)
            if r.isEmpty { return "No crash reports in the last 48 hours\(app.isEmpty ? "" : " for \(app)")." }
            let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
            return r.map { "— \($0.file) · \(f.string(from: $0.date))\n\($0.summary)" }.joined(separator: "\n\n")
        },
    ]
}
