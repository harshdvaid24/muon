import Foundation
import PDFKit

/// Reads documents into plain text for the writing tools: text files, PDFs (text layer), and .docx.
enum Documents {
    static let maxChars = 400_000

    static func text(at real: String, status: @escaping (String) -> Void = { _ in }) throws -> String {
        let ext = (real as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf":
            guard let doc = PDFDocument(url: URL(fileURLWithPath: real)) else { throw IntelligenceError.notFound(real) }
            let s = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if s.count > 40 { return String(s.prefix(maxChars)) }
            return try VisionTools.ocrPDF(doc, status: status)
        case "docx":
            return try docx(real)
        case "png", "jpg", "jpeg", "heic", "tiff", "webp", "gif":
            return try VisionTools.ocr(URL(fileURLWithPath: real))
        default:
            guard let data = FileManager.default.contents(atPath: real) else { throw IntelligenceError.notFound(real) }
            guard data.count < 8_000_000, !data.prefix(4096).contains(0) else { throw IntelligenceError.noInput("\((real as NSString).lastPathComponent) is not a text document.") }
            return String(decoding: data.prefix(maxChars), as: UTF8.self)
        }
    }

    /// .docx is a zip; the body lives in word/document.xml.
    private static func docx(_ real: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", real, "word/document.xml"]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
        var xml = String(decoding: data.prefix(maxChars * 4), as: UTF8.self)
        xml = xml.replacingOccurrences(of: "</w:p>", with: "\n").replacingOccurrences(of: "<w:tab/>", with: "\t")
        let stripped = xml.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        return stripped.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let tools: [HostTool] = [
        HostTool(name: "readDocument", description: "Read a document's text: .pdf (with OCR fallback for scans), .docx, .txt/.md/.csv/.json, or an image (OCR). Use before summarizing or answering questions about a file.",
                 schema: HostTool.schema([("path", "string", "File path")], required: ["path"]), readOnly: true, destructive: false) { a in
            let real = try PathPolicy.resolve(HostTools.string(a, "path"))
            let t = try text(at: real)
            return t.count > 60_000 ? String(t.prefix(60_000)) + "\n…(truncated)" : t
        },
    ]
}
