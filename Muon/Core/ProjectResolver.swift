import Foundation

struct Project: Equatable {
    let name: String
    let path: String   // absolute
    let type: String
}

/// Resolves "portfolio" → ~/Work/portfolio using exact/prefix/substring/subsequence scoring, learned aliases and frecency.
struct ProjectResolver {
    var projects: [Project]

    /// Parses `listProjects` output: one "~/Work/portfolio\treact-native" per line.
    static func parse(_ text: String) -> [Project] {
        text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard let p = parts.first, p.hasPrefix("~") || p.hasPrefix("/") else { return nil }
            let abs = Settings.expand(p)
            return Project(name: (abs as NSString).lastPathComponent, path: abs, type: parts.count > 1 ? parts[1] : "other")
        }
    }

    static func score(term: String, name: String) -> Int {
        let t = Memory.normalize(term).replacingOccurrences(of: " ", with: "")
        let n = Memory.normalize(name).replacingOccurrences(of: " ", with: "")
        guard !t.isEmpty, !n.isEmpty else { return 0 }
        if n == t { return 100 }
        if n.hasPrefix(t) { return 80 }
        if n.contains(t) { return 60 }
        var it = n.makeIterator()
        for ch in t { while true { guard let c = it.next() else { return 0 }; if c == ch { break } } }
        return 40
    }

    /// Ranked candidates; empty when nothing matches.
    func resolve(_ term: String, memory: Memory? = nil) -> [Project] {
        var scored: [(Project, Int)] = []
        if let alias = memory?.alias(term), let p = projects.first(where: { $0.path == alias }) ?? Self.projectFromPath(alias) {
            scored.append((p, 200))
        }
        let recent = memory?.top(kind: "path", n: 50) ?? []
        for p in projects {
            let s = Self.score(term: term, name: p.name)
            guard s > 0 else { continue }
            let boost = recent.firstIndex(of: p.path).map { max(0, 20 - $0) } ?? 0
            scored.append((p, s + boost))
        }
        var seen = Set<String>()
        return scored.sorted { $0.1 > $1.1 }.compactMap { seen.insert($0.0.path).inserted ? $0.0 : nil }
    }

    private static func projectFromPath(_ path: String) -> Project? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        return Project(name: (path as NSString).lastPathComponent, path: path, type: isDir.boolValue ? "folder" : "file")
    }
}
