import Foundation

/// Deterministic parser for file-cleanup requests, so the most common file-changing flow never depends on a
/// small model's planning. Examples:
///   "move the screenshots in ~/Downloads to ~/Downloads/Archive"
///   "trash zips in downloads older than 30 days"
///   "archive the pdfs on my desktop"
struct CleanupIntent: Equatable {
    enum Verb: Equatable { case move, trash }

    var verb: Verb
    var kind: String?
    var nameContains: String?
    var olderThanDays: Int?
    /// Path or folder word the files are in.
    var source: String
    /// Path to move into; nil for trash. "archive" requests use `<source>/Archive`.
    var destination: String?

    static let archiveMarker = "<source>/Archive"

    /// Order matters: first hit wins.
    static let kindWords: [(String, String)] = [
        ("screenshot", "screenshots"), ("screen shot", "screenshots"), ("pdf", "pdfs"),
        ("image", "images"), ("photo", "images"), ("picture", "images"), ("png", "images"), ("jpg", "images"), ("jpeg", "images"),
        ("zip", "zips"), ("video", "videos"), ("movie", "videos"), ("recording", "videos"),
        ("installer", "installers"), ("dmg", "installers"), ("apk", "installers"),
        ("document", "documents"), ("docs", "documents"), ("audio", "audio"), ("mp3", "audio"), ("song", "audio"),
    ]

    static func parse(_ query: String) -> CleanupIntent? {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        let verb: Verb
        let isArchive = lower.hasPrefix("archive ")
        if lower.hasPrefix("move ") || isArchive { verb = .move }
        else if ["trash ", "delete ", "remove ", "bin "].contains(where: lower.hasPrefix) { verb = .trash }
        else { return nil }

        let paths = pathTokens(q)
        // Kind is read from the words only, never from inside a path ("~/Documents" is not "documents").
        var words = lower
        for p in paths { words = words.replacingOccurrences(of: p.lowercased(), with: " ") }
        let kind = kindWords.first { words.contains($0.0) }?.1
        let named = firstMatch(#"(?:named|called)\s+"?([\w .()-]{1,60}?)"?(?:\s+(?:in|from|on|to|into|older)\b|$)"#, in: q)

        var age: Int?
        if let m = firstMatch(#"older than (\d{1,4}) ?(day|week|month|year)s?"#, in: lower, groups: 2), let n = Int(m[0]) {
            age = n * ["day": 1, "week": 7, "month": 30, "year": 365][m[1], default: 1]
        }

        // Source: first path, else a folder word after in/from/on.
        var source = paths.first
        if source == nil, let w = firstMatch(#"\b(?:in|from|on)\s+(?:my\s+|the\s+)?(downloads|desktop|documents)\b"#, in: lower) { source = w }
        guard let src = source, kind != nil || named != nil else { return nil }

        var destination: String?
        if verb == .move {
            if paths.count >= 2 { destination = paths.last }
            else if let w = firstMatch(#"\b(?:to|into)\s+(?:my\s+|the\s+)?(downloads|desktop|documents)\b"#, in: lower) { destination = w }
            else if isArchive || words.contains("archive") { destination = archiveMarker }
            guard destination != nil else { return nil }
        }
        return CleanupIntent(verb: verb, kind: kind, nameContains: named, olderThanDays: age, source: src, destination: destination)
    }

    /// `~/…` and `/…` tokens in order of appearance.
    static func pathTokens(_ s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?<![\w])(~/|/)[^\s,;]+"#) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
            Range(m.range, in: s).map { String(s[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".?!'\"")) }
        }
    }

    private static func firstMatch(_ pattern: String, in s: String) -> String? {
        firstMatch(pattern, in: s, groups: 1)?.first
    }

    private static func firstMatch(_ pattern: String, in s: String, groups: Int) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (1...groups).compactMap { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
    }
}
