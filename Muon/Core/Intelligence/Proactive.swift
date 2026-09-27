import AppKit
import Foundation

/// What Muon notices for you, computed lazily when the palette opens (at most once a day) — never in the background.
struct ProactiveSuggestion: Identifiable, Equatable {
    enum Action: Equatable { case query(String), rule(String), undo }
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let action: Action
}

enum Proactive {
    static let ttl: TimeInterval = 24 * 3600
    private static let cacheKey = "proactiveDigest"

    /// Cached suggestions if fresh, else nil.
    static func cached() -> [ProactiveSuggestion]? {
        guard let d = Settings.d.dictionary(forKey: cacheKey), let at = d["at"] as? Double, Date().timeIntervalSince1970 - at < ttl,
              let rows = d["rows"] as? [[String: String]] else { return nil }
        return rows.compactMap(decode) + clipboardSuggestions() + undoSuggestion()
    }

    /// Full refresh: a few cheap read-only tool calls (~1-3 s). Cached for a day.
    static func refresh(memory: Memory?) async -> [ProactiveSuggestion] {
        var rows: [ProactiveSuggestion] = []
        let agent = Agent.shared
        struct Deny: Approver { func approve(_ a: PendingAction) async -> ApprovalDecision { .cancel } }
        let home = NSHomeDirectory()
        // 1. Old screenshots (Desktop + Downloads)
        for folder in Set([VisionTools.screenshotsFolder(), home + "/Downloads", home + "/Desktop"]) {
            let r = await agent.execute("matchFiles", ["folder": folder, "kind": "screenshots", "olderThanDays": 30], approver: Deny()) { _ in }
            let n = r.ok ? r.text.split(separator: "\n").filter { $0.hasPrefix("~") || $0.hasPrefix("/") }.count : 0
            if n >= 5 {
                rows.append(.init(id: "shots-\(folder)", icon: "photo.on.rectangle", title: "Archive \(n) screenshots older than 30 days",
                                  subtitle: "in \(Agent.short(folder)) · one confirmation", action: .query("move the screenshots in \(Agent.short(folder)) older than 30 days into \(Agent.short(folder))/Archive")))
            }
        }
        // 2. Downloads size
        let big = await agent.execute("largestFiles", ["path": home + "/Downloads", "limit": 3], approver: Deny()) { _ in }
        if big.ok, let m = big.text.range(of: #"(\d+(?:\.\d+)?) GB total"#, options: .regularExpression),
           let gb = Double(big.text[m].split(separator: " ").first ?? ""), gb >= 3 {
            rows.append(.init(id: "downloads-size", icon: "externaldrive", title: String(format: "Downloads is using %.1f GB", gb), subtitle: "see the biggest files", action: .query("what is taking space in ~/Downloads")))
        }
        // 3. Duplicates in Downloads
        let dup = await agent.execute("findDuplicates", ["path": home + "/Downloads", "minSizeKB": 512], approver: Deny()) { _ in }
        if dup.ok, let m = dup.text.range(of: #"(\d+(?:\.\d+)?) (MB|GB) reclaimable"#, options: .regularExpression) {
            let parts = dup.text[m].split(separator: " ")
            if let v = Double(parts[0]), (parts[1] == "GB" || v >= 100) {
                rows.append(.init(id: "dups", icon: "doc.on.doc", title: "Reclaim \(parts[0]) \(parts[1]) of duplicate downloads", subtitle: "review the duplicate sets", action: .query("find duplicate files in ~/Downloads")))
            }
        }
        // 4. Recent crashes
        let crashes = CrashLogs.recent(hours: 24, limit: 3)
        if let c = crashes.first {
            let proc = c.summary.split(separator: "\n").first.map { String($0).replacingOccurrences(of: "process: ", with: "") } ?? "an app"
            rows.append(.init(id: "crash", icon: "exclamationmark.triangle", title: "\(proc) crashed\(crashes.count > 1 ? " \(crashes.count) times" : "") recently", subtitle: "get a plain-language explanation", action: .query("why did \(proc) crash")))
        }
        // 5. Habits: a cleanup you've run 3+ times → offer a weekly rule
        if let m = memory {
            for (key, hits) in m.topCached(8) where hits >= 3 && CleanupIntent.parse(key) != nil && !Rules.all.contains(where: { $0.query == key }) {
                rows.append(.init(id: "rule-\(key)", icon: "calendar.badge.clock", title: "Do this every week: “\(key.prefix(48))”", subtitle: "you've run it \(hits) times · runs on Mondays with a notification and undo", action: .rule(key)))
            }
        }
        let payload = rows.map { ["id": $0.id, "icon": $0.icon, "title": $0.title, "subtitle": $0.subtitle, "kind": $0.action.kind, "value": $0.action.value] }
        Settings.d.set(["at": Date().timeIntervalSince1970, "rows": payload], forKey: cacheKey)
        return rows + clipboardSuggestions() + undoSuggestion()
    }

    static func invalidate() { Settings.d.removeObject(forKey: cacheKey) }

    /// Instant, regex-only: what's on the clipboard right now.
    static func clipboardSuggestions() -> [ProactiveSuggestion] {
        guard let t = TextTools.clipboardText(), t.count > 20, t.count < 20_000 else { return [] }
        let firstLine = t.split(separator: "\n").first.map(String.init) ?? t
        if t.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil {
            return [.init(id: "clip-url", icon: "link", title: "Summarize the link on your clipboard", subtitle: String(t.prefix(70)), action: .query("summarize \(t)"))]
        }
        if t.range(of: #"(Error|Exception|Traceback|fatal|Unhandled|error\[|\bat .+\(.+:\d+\)|Thread \d+ Crashed)"#, options: .regularExpression) != nil {
            return [.init(id: "clip-error", icon: "ladybug", title: "Explain the error on your clipboard", subtitle: String(firstLine.prefix(70)), action: .query("explain this"))]
        }
        let nonLatin = t.unicodeScalars.filter { $0.value > 0x24F && !CharacterSet.punctuationCharacters.contains($0) }.count
        if Double(nonLatin) / Double(max(t.count, 1)) > 0.3 {
            return [.init(id: "clip-translate", icon: "character.book.closed", title: "Translate the clipboard to English", subtitle: String(firstLine.prefix(70)), action: .query("translate to english"))]
        }
        if t.count > 600 {
            return [.init(id: "clip-summary", icon: "text.alignleft", title: "Summarize the text on your clipboard", subtitle: "\(t.split(whereSeparator: \.isWhitespace).count) words", action: .query("summarize this"))]
        }
        return []
    }

    static func undoSuggestion() -> [ProactiveSuggestion] {
        guard let u = Undo.last, Date().timeIntervalSince(u.at) < 24 * 3600 else { return [] }
        return [.init(id: "undo", icon: "arrow.uturn.backward", title: "Undo: \(u.title)", subtitle: "\(u.moves.count) item\(u.moves.count == 1 ? "" : "s") · \(RelativeDateTimeFormatter().localizedString(for: u.at, relativeTo: Date()))", action: .undo)]
    }

    private static func decode(_ d: [String: String]) -> ProactiveSuggestion? {
        guard let id = d["id"], let icon = d["icon"], let title = d["title"], let sub = d["subtitle"], let kind = d["kind"], let value = d["value"] else { return nil }
        let action: ProactiveSuggestion.Action = kind == "rule" ? .rule(value) : .query(value)
        return .init(id: id, icon: icon, title: title, subtitle: sub, action: action)
    }
}

extension ProactiveSuggestion.Action {
    var kind: String { switch self { case .query: return "query"; case .rule: return "rule"; case .undo: return "undo" } }
    var value: String { switch self { case .query(let q), .rule(let q): return q; case .undo: return "" } }
}
