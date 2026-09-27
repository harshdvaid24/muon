import Foundation
import SQLite3

/// Tiny synchronous SQLite wrapper. Serialized with a lock; safe to call from any thread.
final class SQLite {
    enum Failure: Error { case open(String) }

    private var db: OpaquePointer?
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw Failure.open(String(cString: sqlite3_errmsg(db)))
        }
        sqlite3_exec(db, "PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;", nil, nil, nil)
    }

    deinit { sqlite3_close(db) }

    /// Multiple statements, no parameters (schema setup).
    func exec(_ sql: String) {
        lock.lock(); defer { lock.unlock() }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    @discardableResult
    func run(_ sql: String, _ params: [Any?] = []) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let stmt = prepare(sql, params) else { return false }
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    func rows(_ sql: String, _ params: [Any?] = []) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        guard let stmt = prepare(sql, params) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [[String: Any]] = []
        let n = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<n {
                let name = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(stmt, i))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, i))
                default: break
                }
            }
            out.append(row)
        }
        return out
    }

    private func prepare(_ sql: String, _ params: [Any?]) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return nil }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case nil: sqlite3_bind_null(stmt, idx)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, Self.transient)
            case let v as Bool: sqlite3_bind_int(stmt, idx, v ? 1 : 0)
            default: sqlite3_bind_text(stmt, idx, String(describing: p!), -1, Self.transient)
            }
        }
        return stmt
    }
}
