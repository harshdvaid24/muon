import Foundation

/// Scheduled automations you created from a suggestion or by asking ("every monday archive the screenshots…").
/// Only deterministic cleanup requests can become rules, so a rule can never do something a model dreamed up.
struct Rule: Codable, Identifiable, Equatable {
    enum Schedule: Codable, Equatable {
        case daily(hour: Int)
        case weekly(weekday: Int, hour: Int)   // 1 = Sunday … 7 = Saturday (Calendar)
        var label: String {
            switch self {
            case .daily(let h): return "every day at \(h):00"
            case .weekly(let d, let h): return "every \(Calendar.current.weekdaySymbols[d - 1]) at \(h):00"
            }
        }
    }
    var id: String
    var query: String
    var schedule: Schedule
    var lastRun: Date?
    var enabled = true
    var createdAt = Date()
}

enum Rules {
    static var path: String { NSHomeDirectory() + "/Library/Application Support/Muon/rules.json" }
    static let maxRules = 50

    static var all: [Rule] {
        guard let d = FileManager.default.contents(atPath: path), let r = try? JSONDecoder().decode([Rule].self, from: d) else { return [] }
        return r
    }

    static func save(_ rules: [Rule]) {
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(Array(rules.prefix(maxRules))) { try? d.write(to: URL(fileURLWithPath: path)) }
    }

    @discardableResult
    static func add(query: String, schedule: Rule.Schedule) -> Rule {
        var rules = all.filter { $0.query != query }
        let r = Rule(id: UUID().uuidString.prefix(8).lowercased(), query: query, schedule: schedule)
        rules.append(r); save(rules); return r
    }

    static func remove(id: String) { save(all.filter { $0.id != id }) }

    /// "every monday at 9 move the screenshots in ~/Downloads into ~/Downloads/Archive" · "every day archive the pdfs on my desktop"
    static func parse(_ q: String) -> (query: String, schedule: Rule.Schedule)? {
        let lower = q.lowercased()
        guard let m = lower.range(of: #"^(every|each)\s+(day|daily|week|weekly|monday|tuesday|wednesday|thursday|friday|saturday|sunday)(\s+(morning|evening|at\s+(\d{1,2})(?::00)?\s*(am|pm)?))?[,:]?\s*"#, options: .regularExpression) else { return nil }
        let head = String(lower[m]); let rest = String(q[m.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard CleanupIntent.parse(rest) != nil else { return nil }
        var hour = 9
        if head.contains("evening") { hour = 18 }
        if let h = head.range(of: #"at\s+(\d{1,2})"#, options: .regularExpression), let n = Int(lower[h].filter(\.isNumber)) { hour = head.contains("pm") && n < 12 ? n + 12 : n }
        let days = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if let i = days.firstIndex(where: { head.contains($0) }) { return (rest, .weekly(weekday: i + 1, hour: hour)) }
        if head.contains("week") { return (rest, .weekly(weekday: 2, hour: hour)) }
        return (rest, .daily(hour: hour))
    }

    /// Rules whose next run time has passed since their last run.
    static func due(now: Date = Date(), calendar: Calendar = .current) -> [Rule] {
        all.filter { $0.enabled && isDue($0, now: now, calendar: calendar) }
    }

    static func isDue(_ r: Rule, now: Date, calendar: Calendar) -> Bool {
        let last = r.lastRun ?? r.createdAt
        switch r.schedule {
        case .daily(let hour):
            guard let todayRun = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) else { return false }
            let target = todayRun <= now ? todayRun : calendar.date(byAdding: .day, value: -1, to: todayRun)!
            return target > last
        case .weekly(let weekday, let hour):
            var comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
            comps.weekday = weekday; comps.hour = hour
            guard let thisWeek = calendar.date(from: comps) else { return false }
            let target = thisWeek <= now ? thisWeek : calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek)!
            return target > last
        }
    }

    /// Runs due rules without prompting (the user approved them when created); records undo; notifies.
    static func runDue(agent: Agent) async {
        struct Auto: Approver { func approve(_ a: PendingAction) async -> ApprovalDecision { .allow } }
        for var rule in due() {
            guard let intent = CleanupIntent.parse(rule.query) else { continue }
            let out = await agent.runCleanup(intent, approver: Auto()) { _ in }
            rule.lastRun = Date()
            save(all.map { $0.id == rule.id ? rule : $0 })
            if let r = out?.results.first, r.ok, r.tool == "moveItems", let paths = r.args["paths"] as? [String], let dest = r.args["destinationFolder"] as? String {
                Undo.record(title: rule.query, moves: paths.map { Undo.Move(from: $0, to: (dest as NSString).appendingPathComponent(($0 as NSString).lastPathComponent)) })
            }
            let msg = out?.answer?.split(separator: "\n").first.map(String.init) ?? "done"
            Notifier.notify(title: "Muon rule ran", body: "\(rule.query.prefix(60)) — \(msg). Open Muon to undo.")
        }
    }
}

/// Reversible record of the last automated move/rename, so "undo" is always one word away.
enum Undo {
    struct Move: Codable { let from: String; let to: String }
    struct Record: Codable { let title: String; let moves: [Move]; let at: Date }
    static var path: String { NSHomeDirectory() + "/Library/Application Support/Muon/undo.json" }

    static var last: Record? {
        guard let d = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: d)
    }
    static func record(title: String, moves: [Move]) {
        guard !moves.isEmpty, let d = try? JSONEncoder().encode(Record(title: title, moves: moves, at: Date())) else { return }
        try? d.write(to: URL(fileURLWithPath: path))
    }
    static func clear() { try? FileManager.default.removeItem(atPath: path) }

    /// Plan for reversing the last record: (currentPath, originalFolder) per item that still exists.
    static func plan(_ r: Record) -> [(from: String, toFolder: String)] {
        r.moves.filter { FileManager.default.fileExists(atPath: $0.to) }.map { ($0.to, ($0.from as NSString).deletingLastPathComponent) }
    }
}

enum Notifier {
    static func notify(title: String, body: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", "display notification \(json(body)) with title \(json(title))"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? p.run()
    }
    private static func json(_ s: String) -> String { (try? String(decoding: JSONSerialization.data(withJSONObject: [s]), as: UTF8.self).dropFirst().dropLast()).map(String.init) ?? "\"\"" }
}
