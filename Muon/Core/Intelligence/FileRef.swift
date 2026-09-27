import Foundation

/// A file named without a path: "sampleStatement.pdf from downloads", "check the lease.pdf in documents".
/// Resolves the name to a real file (folder word first, else Downloads/Documents/Desktop, then every allowed
/// folder; case-insensitive; a few levels deep) and rewrites the request with the quoted path in its place.
enum FileRef {
    static let exts: Set<String> = ["pdf", "docx", "doc", "txt", "md", "markdown", "csv", "json", "rtf", "html", "htm", "log", "xml", "yml", "yaml", "xlsx", "pptx",
                                    "png", "jpg", "jpeg", "heic", "tiff", "webp", "gif", "m4a", "mp3", "wav", "aiff", "aif", "caf", "mov", "mp4", "m4v", "aac", "flac"]
    static let skipDirs: Set<String> = ["node_modules", ".git", "Pods", "build", "DerivedData", "Library", ".Trash"]

    struct Match: Equatable { let path: String; let rewritten: String }

    static var defaultFolders: [String] {
        var seen = Set<String>()
        return (["~/Downloads", "~/Documents", "~/Desktop"] + Settings.allowedRoots).map(Settings.expand).filter { seen.insert($0).inserted }
    }

    static func rewrite(_ q: String, folderWords: [String: String] = Agent.folderWords, folders: [String]? = nil) -> Match? {
        guard PathPolicy.paths(in: q).isEmpty else { return nil }   // an explicit path is already there
        guard let extRe = try? NSRegularExpression(pattern: #"\.([A-Za-z0-9]{2,5})(?![\w/.])"#) else { return nil }
        let ns = q as NSString
        // the folder phrase, if any: "from downloads", "in my documents folder"
        var searchIn: [String]? = folders
        var phraseRange: NSRange?
        if let fr = try? NSRegularExpression(pattern: #"(?i)\b(?:from|in|inside|on|under)\s+(?:my\s+)?(?:the\s+)?([a-z]+)(?:\s+folder)?\b"#) {
            for m in fr.matches(in: q, range: NSRange(location: 0, length: ns.length)) {
                let word = ns.substring(with: m.range(at: 1)).lowercased()
                let key = word.hasSuffix("s") ? word : word + "s"   // download → downloads
                if let f = folderWords[word] ?? folderWords[key] { searchIn = [Settings.expand(f)]; phraseRange = m.range; break }
            }
        }
        for m in extRe.matches(in: q, range: NSRange(location: 0, length: ns.length)) {
            let ext = ns.substring(with: m.range(at: 1)).lowercased()
            guard exts.contains(ext) else { continue }
            // the name is the words before the extension; try the longest run first, existence decides
            let before = ns.substring(to: m.range.location)
            let words = before.split(separator: " ", omittingEmptySubsequences: false)
            for k in stride(from: min(words.count, 6), through: 1, by: -1) {
                let stem = words.suffix(k).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " \"'“”‘’,;:("))
                guard !stem.isEmpty, !stem.contains("/") else { continue }
                let name = stem + "." + ns.substring(with: m.range(at: 1))
                guard let found = find(name, in: searchIn ?? defaultFolders) else { continue }
                let nameStart = m.range.location + m.range.length - (name as NSString).length
                var out = ns.replacingCharacters(in: NSRange(location: nameStart, length: (name as NSString).length), with: "\"\(found)\"")
                if let pr = phraseRange, pr.location > nameStart {
                    let shifted = NSRange(location: pr.location + ((found as NSString).length + 2 - (name as NSString).length), length: pr.length)
                    out = (out as NSString).replacingCharacters(in: shifted, with: "")
                } else if let pr = phraseRange {
                    out = (out as NSString).replacingCharacters(in: pr, with: "")
                }
                out = out.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: " ,", with: ",").trimmingCharacters(in: .whitespaces)
                return Match(path: found, rewritten: out)
            }
        }
        return nil
    }

    /// Exact name in the folder, then case-insensitive, then a few levels down.
    static func find(_ name: String, in folders: [String]) -> String? {
        let fm = FileManager.default
        let wanted = name.lowercased()
        for folder in folders where fm.fileExists(atPath: folder + "/" + name) {
            // APFS matches case-insensitively; return the entry's real spelling.
            let real = (try? fm.contentsOfDirectory(atPath: folder))?.first { $0.lowercased() == wanted } ?? name
            return folder + "/" + real
        }
        for folder in folders {
            let base = URL(fileURLWithPath: folder).resolvingSymlinksInPath().path
            guard let e = fm.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var checked = 0
            for case let url as URL in e {
                checked += 1
                if checked > 4000 { break }
                if e.level > 3 { e.skipDescendants(); continue }
                if skipDirs.contains(url.lastPathComponent) { e.skipDescendants(); continue }
                if url.lastPathComponent.lowercased() == wanted {
                    let p = url.resolvingSymlinksInPath().path
                    return p.hasPrefix(base + "/") ? folder + p.dropFirst(base.count) : p
                }
            }
        }
        return nil
    }

    /// "check / analyse / brief / review / what's in" wants the document read, unless the verb is open/show/reveal.
    static func wantsAnalysis(_ q: String) -> Bool {
        let lower = q.lowercased()
        if lower.range(of: #"^(open|show|reveal|launch|preview|play)\b"#, options: .regularExpression) != nil { return false }
        return lower.range(of: #"\b(analy[sz]e|analysis|review|check|go through|look at|brief|overview|summar|gist|tl;?dr|what('s| is) (in|inside|it about)|read|explain|key points|highlights)\b"#, options: .regularExpression) != nil
    }

    static func analysisInstruction(_ ask: String) -> String {
        WritingIntent.analysisInstruction + " The user asked: “\(ask)”. Follow that wording for length and focus."
    }
}
