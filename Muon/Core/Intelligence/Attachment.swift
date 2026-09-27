import AppKit
import Foundation
import UniformTypeIdentifiers

/// A file attached to the palette (drop, ⌘O, or a pasted image/file). Its path is composed into the request the way a
/// typed path would be, so every parser and tool sees an ordinary path.
enum Attachment {
    static var pastedDir = NSHomeDirectory() + "/Library/Application Support/Muon/Pasted"
    static let keepPasted = 20

    enum Kind { case image, audio, document, folder, other }

    static func kind(of path: String) -> Kind {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue { return .folder }
        let ext = (path as NSString).pathExtension.lowercased()
        if VisionTools.imageExts.contains(ext) { return .image }
        if Transcriber.audioExts.contains(ext) { return .audio }
        if ["pdf", "docx", "txt", "md", "markdown", "csv", "json", "rtf", "html", "htm", "log", "xml", "yml", "yaml"].contains(ext) { return .document }
        return .other
    }

    /// The request to run for what the user typed plus the attached file.
    static func compose(query: String, path: String) -> String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let quoted = "\"\(path)\""
        let lower = q.lowercased()
        switch kind(of: path) {
        case .image:
            if q.isEmpty { return "describe \(quoted)" }
            if lower.range(of: #"^(explain|what('s| is) wrong|what does this error|debug|read|ocr|copy|extract|get|describe|what('s| is) in|what do you see|look at|analy[sz]e|compare|rename)"#, options: .regularExpression) != nil { return "\(q) \(quoted)" }
            return "describe \(quoted): \(q)"
        case .audio:
            if q.isEmpty || lower.hasPrefix("transcri") || lower.hasPrefix("what was said") { return "transcribe \(quoted)" }
            return "meeting notes from \(quoted)"
        case .folder:
            return q.isEmpty ? "what is inside \(quoted)" : "\(q) \(quoted)"
        case .document, .other:
            if q.isEmpty { return "summarize \(quoted)" }
            if WritingIntent.parse(q) != nil { return "\(q) \(quoted)" }
            return "ask \(quoted): \(q)"
        }
    }

    /// How a past request reads in the Recent list: home as ~, pasted images by name only.
    static func displayTitle(forRequest q: String) -> String {
        var t = q
        if let re = try? NSRegularExpression(pattern: "\"?" + NSRegularExpression.escapedPattern(for: pastedDir) + "/[^\" ]+\"?") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "(pasted image)")
        }
        return t.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static func icon(for path: String) -> String {
        switch kind(of: path) {
        case .image: return "photo"
        case .audio: return "waveform"
        case .folder: return "folder"
        case .document, .other: return "doc.text"
        }
    }

    /// A file from the pasteboard: a copied file first, else a copied image saved to disk. Nil when it is plain text.
    static func fromPasteboard(_ pb: NSPasteboard = .general) -> String? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let u = urls.first, FileManager.default.fileExists(atPath: u.path) { return u.path }
        if pb.string(forType: .string) != nil { return nil }
        guard let image = NSImage(pasteboard: pb) else { return nil }
        return save(image: image)
    }

    /// Saves an image as PNG under `pastedDir`, keeping only the newest `keepPasted`.
    static func save(image: NSImage) -> String? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return save(png: png)
    }

    static func save(png: Data, now: Date = Date()) -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: pastedDir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"
        let path = "\(pastedDir)/pasted-\(f.string(from: now)).png"
        guard fm.createFile(atPath: path, contents: png) else { return nil }
        prune()
        return path
    }

    static func prune() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: pastedDir) else { return }
        let sorted = names.filter { $0.hasPrefix("pasted-") }.sorted()
        for old in sorted.dropLast(keepPasted) { try? fm.removeItem(atPath: "\(pastedDir)/\(old)") }
    }
}
