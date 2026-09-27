import Foundation

/// Host-side mirror of mac-tools' path policy, for tools that read files inside the app (OCR, PDF, audio, text).
enum PathPolicy {
    enum Failure: LocalizedError {
        case empty, missing(String), protected(String), outside(String)
        var errorDescription: String? {
            switch self {
            case .empty: return "empty path"
            case .missing(let p): return "path does not exist: \(Agent.short(p))"
            case .protected(let p): return "path is protected: \(Agent.short(p))"
            case .outside(let p): return "path is outside allowed folders (\(Settings.allowedRoots.joined(separator: ", "))): \(Agent.short(p))"
            }
        }
    }

    static let deniedRoots = ["~/Library", "~/.ssh", "~/.gnupg", "~/.aws", "~/.config", "~/.docker", "~/.kube",
                              "/System", "/private", "/usr", "/bin", "/sbin", "/Library", "/etc", "/var", "/Applications"]

    static func canonical(_ p: String) -> String {
        URL(fileURLWithPath: Settings.expand(p)).standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func under(_ p: String, _ root: String) -> Bool { p == root || p.hasPrefix(root + "/") }

    /// Real path if allowed; throws otherwise. New (non-existent) paths resolve through the nearest existing ancestor.
    static func resolve(_ input: String, mustExist: Bool = true) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw Failure.empty }
        let abs = URL(fileURLWithPath: Settings.expand(trimmed)).standardizedFileURL.path
        var real: String
        if FileManager.default.fileExists(atPath: abs) {
            real = canonical(abs)
        } else {
            if mustExist { throw Failure.missing(abs) }
            var base = abs; var tail: [String] = []
            while !FileManager.default.fileExists(atPath: base) {
                let parent = (base as NSString).deletingLastPathComponent
                if parent == base { throw Failure.missing(abs) }
                tail.insert((base as NSString).lastPathComponent, at: 0); base = parent
            }
            real = ([canonical(base)] + tail).joined(separator: "/")
        }
        if deniedRoots.map(canonical).contains(where: { under(real, $0) }) { throw Failure.protected(real) }
        guard Settings.allowedRoots.map(canonical).contains(where: { under(real, $0) }) else { throw Failure.outside(real) }
        return real
    }

    /// Every `~/…` or `/…` token in free text, in order.
    static func paths(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"(?<![\w:/])(~/|/)[^\s,;'":]+"#) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            Range(m.range, in: text).map { String(text[$0]).trimmingCharacters(in: CharacterSet(charactersIn: ".?!:")) }
        }
    }

    /// First `~/…` or `/…` token in free text, if any.
    static func firstPath(in text: String) -> String? {
        guard let r = text.range(of: #"(?<![\w])(~/|/)[^\s,;'":]+"#, options: .regularExpression) else { return nil }
        return String(text[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".?!:"))
    }
}
