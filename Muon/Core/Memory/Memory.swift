import CryptoKit
import Foundation

/// Tier-0 memory: bounded SQLite tables that make repeated work free.
/// Every table is capped at `rowLimit` rows by frecency; nothing here ever grows unbounded.
final class Memory {
    struct CachedIntent { var tool: String; var argsJSON: String }
    struct Alias { var term: String; var path: String }
    struct Macro { var name: String; var stepsJSON: String; var hits: Int }

    var rowLimit = 300
    var now: () -> Date = { Date() }
    private let db: SQLite
    private static let staleDays = 90.0
    private static let halfLifeDays = 14.0

    static var defaultPath: String { NSHomeDirectory() + "/Library/Application Support/Muon/memory.db" }

    init(path: String = Memory.defaultPath) throws {
        db = try SQLite(path: path)
        db.exec("""
        CREATE TABLE IF NOT EXISTS intent_cache(key TEXT PRIMARY KEY, tool TEXT NOT NULL, args_json TEXT NOT NULL, hits INTEGER NOT NULL DEFAULT 1, last_used REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS aliases(term TEXT PRIMARY KEY, path TEXT NOT NULL, hits INTEGER NOT NULL DEFAULT 1, last_used REAL NOT NULL);
        CREATE TABLE IF NOT EXISTS usage(kind TEXT NOT NULL, name TEXT NOT NULL, hits INTEGER NOT NULL DEFAULT 1, last_used REAL NOT NULL, PRIMARY KEY(kind, name));
        CREATE TABLE IF NOT EXISTS macros(name TEXT PRIMARY KEY, steps_json TEXT NOT NULL, hits INTEGER NOT NULL DEFAULT 0, last_used REAL NOT NULL);
        """)
        prune()
    }

    // MARK: Normalization

    static func normalize(_ q: String) -> String {
        let scalars = q.lowercased().unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    // MARK: Intent cache

    func cacheLookup(_ q: String) -> CachedIntent? {
        let key = Self.normalize(q)
        guard let r = db.rows("SELECT tool, args_json FROM intent_cache WHERE key = ?", [key]).first,
              let tool = r["tool"] as? String, let args = r["args_json"] as? String else { return nil }
        db.run("UPDATE intent_cache SET hits = hits + 1, last_used = ? WHERE key = ?", [ts(), key])
        return CachedIntent(tool: tool, argsJSON: args)
    }

    func cacheStore(_ q: String, tool: String, argsJSON: String) {
        let key = Self.normalize(q)
        guard !key.isEmpty else { return }
        db.run("""
        INSERT INTO intent_cache(key, tool, args_json, hits, last_used) VALUES(?, ?, ?, 1, ?)
        ON CONFLICT(key) DO UPDATE SET tool = excluded.tool, args_json = excluded.args_json, hits = hits + 1, last_used = excluded.last_used
        """, [key, tool, argsJSON, ts()])
        evict(table: "intent_cache", keys: ["key"])
    }

    func cacheInvalidate(_ q: String) { db.run("DELETE FROM intent_cache WHERE key = ?", [Self.normalize(q)]) }

    /// Most-used cached requests (by frecency) with their hit counts.
    func topCached(_ n: Int) -> [(key: String, hits: Int)] {
        ranked(db.rows("SELECT key, hits, last_used FROM intent_cache")).prefix(n).compactMap { r in
            guard let k = r["key"] as? String else { return nil }
            return (k, (r["hits"] as? Int) ?? 1)
        }
    }

    // MARK: Aliases (term → path)

    func alias(_ term: String) -> String? {
        let key = Self.normalize(term)
        guard let r = db.rows("SELECT path FROM aliases WHERE term = ?", [key]).first, let p = r["path"] as? String else { return nil }
        db.run("UPDATE aliases SET hits = hits + 1, last_used = ? WHERE term = ?", [ts(), key])
        return p
    }

    func learnAlias(_ term: String, path: String) {
        let key = Self.normalize(term)
        guard !key.isEmpty else { return }
        db.run("""
        INSERT INTO aliases(term, path, hits, last_used) VALUES(?, ?, 1, ?)
        ON CONFLICT(term) DO UPDATE SET path = excluded.path, hits = hits + 1, last_used = excluded.last_used
        """, [key, path, ts()])
        evict(table: "aliases", keys: ["term"])
    }

    func topAliases(_ n: Int) -> [Alias] {
        ranked(db.rows("SELECT term, path, hits, last_used FROM aliases")).prefix(n)
            .compactMap { r in (r["term"] as? String).flatMap { t in (r["path"] as? String).map { Alias(term: t, path: $0) } } }
    }

    // MARK: Usage frecency (apps, paths, sequences)

    func bump(kind: String, name: String) {
        db.run("""
        INSERT INTO usage(kind, name, hits, last_used) VALUES(?, ?, 1, ?)
        ON CONFLICT(kind, name) DO UPDATE SET hits = hits + 1, last_used = excluded.last_used
        """, [kind, name, ts()])
        evict(table: "usage", keys: ["kind", "name"], scope: ("kind", kind))
    }

    func top(kind: String, n: Int) -> [String] {
        ranked(db.rows("SELECT name, hits, last_used FROM usage WHERE kind = ?", [kind])).prefix(n).compactMap { $0["name"] as? String }
    }

    /// Counts how often a tool sequence has recurred. Returns the new count.
    func noteSequence(_ sequence: String) -> Int {
        let key = Self.digest(sequence)
        bump(kind: "seq", name: key)
        return (db.rows("SELECT hits FROM usage WHERE kind = 'seq' AND name = ?", [key]).first?["hits"] as? Int) ?? 1
    }

    static func digest(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Macros

    func macros() -> [Macro] {
        db.rows("SELECT name, steps_json, hits FROM macros ORDER BY hits DESC, name ASC").compactMap { r in
            guard let n = r["name"] as? String, let s = r["steps_json"] as? String else { return nil }
            return Macro(name: n, stepsJSON: s, hits: (r["hits"] as? Int) ?? 0)
        }
    }

    func macro(named name: String) -> Macro? {
        db.rows("SELECT name, steps_json, hits FROM macros WHERE lower(name) = lower(?)", [name]).first.flatMap { r in
            guard let n = r["name"] as? String, let s = r["steps_json"] as? String else { return nil }
            return Macro(name: n, stepsJSON: s, hits: (r["hits"] as? Int) ?? 0)
        }
    }

    func saveMacro(name: String, stepsJSON: String) {
        db.run("""
        INSERT INTO macros(name, steps_json, hits, last_used) VALUES(?, ?, 0, ?)
        ON CONFLICT(name) DO UPDATE SET steps_json = excluded.steps_json, last_used = excluded.last_used
        """, [name, stepsJSON, ts()])
        evict(table: "macros", keys: ["name"])
    }

    func touchMacro(_ name: String) { db.run("UPDATE macros SET hits = hits + 1, last_used = ? WHERE name = ?", [ts(), name]) }
    func deleteMacro(_ name: String) { db.run("DELETE FROM macros WHERE name = ?", [name]) }

    // MARK: Housekeeping

    /// Drop rows untouched for `staleDays`.
    func prune() {
        let cutoff = ts() - Self.staleDays * 86400
        for t in ["intent_cache", "aliases", "usage", "macros"] { db.run("DELETE FROM \(t) WHERE last_used < ?", [cutoff]) }
    }

    // MARK: Private

    private func ts() -> Double { now().timeIntervalSince1970 }

    private func frecency(_ r: [String: Any]) -> Double {
        let hits = Double((r["hits"] as? Int) ?? 1)
        let age = max(0, ts() - ((r["last_used"] as? Double) ?? 0)) / 86400
        return hits * pow(0.5, age / Self.halfLifeDays)
    }

    private func ranked(_ rows: [[String: Any]]) -> [[String: Any]] {
        rows.sorted { frecency($0) > frecency($1) }
    }

    private func evict(table: String, keys: [String], scope: (column: String, value: String)? = nil) {
        let scopeSQL = scope.map { " WHERE \($0.column) = ?" } ?? ""
        let scopeArgs: [Any?] = scope.map { [$0.value] } ?? []
        let count = (db.rows("SELECT COUNT(*) AS c FROM \(table)\(scopeSQL)", scopeArgs).first?["c"] as? Int) ?? 0
        guard count > rowLimit else { return }
        let cols = (keys + ["hits", "last_used"]).joined(separator: ", ")
        let victims = ranked(db.rows("SELECT \(cols) FROM \(table)\(scopeSQL)", scopeArgs)).suffix(count - rowLimit)
        let whereClause = keys.map { "\($0) = ?" }.joined(separator: " AND ")
        for v in victims { db.run("DELETE FROM \(table) WHERE \(whereClause)", keys.map { v[$0] }) }
    }
}
