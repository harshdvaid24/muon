import AppKit
import Foundation
import FoundationModels
import PDFKit
import Vision

/// On-device OCR via Vision, plus screenshot helpers and local vision-model calls (LM Studio).
enum VisionTools {
    static let imageExts: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "webp", "gif", "bmp"]

    static func ocr(_ url: URL) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try VNImageRequestHandler(url: url).perform([req])
        return lines(req)
    }

    static func ocr(cgImage: CGImage) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([req])
        return lines(req)
    }

    private static func lines(_ req: VNRecognizeTextRequest) -> String {
        (req.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Scanned PDF: render up to 20 pages and OCR each.
    static func ocrPDF(_ doc: PDFDocument, status: @escaping (String) -> Void) throws -> String {
        var out: [String] = []
        for i in 0..<min(doc.pageCount, 20) {
            guard let page = doc.page(at: i) else { continue }
            status("Reading scanned page \(i + 1) of \(min(doc.pageCount, 20))…")
            let bounds = page.bounds(for: .mediaBox)
            let scale = 1600 / max(bounds.width, 1)
            let image = page.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) { out.append(try ocr(cgImage: cg)) }
        }
        let text = out.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntelligenceError.noInput("No readable text found in that PDF.") }
        return text
    }

    // MARK: Screenshots

    static func screenshotsFolder() -> String {
        if let loc = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !loc.isEmpty { return Settings.expand(loc) }
        return NSHomeDirectory() + "/Desktop"
    }

    static func isScreenshotName(_ name: String) -> Bool {
        name.range(of: #"^(Screen ?[Ss]hot|Simulator Screen ?[Ss]hot|CleanShot|Screen Recording)"#, options: .regularExpression) != nil
    }

    /// Newest screenshot (by name pattern), else newest image, in a folder.
    static func latestScreenshot(in folder: String? = nil) throws -> String {
        let dir = try PathPolicy.resolve(folder ?? screenshotsFolder())
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        func mtime(_ n: String) -> Date { (try? fm.attributesOfItem(atPath: dir + "/" + n)[.modificationDate] as? Date) ?? .distantPast }
        let images = entries.filter { imageExts.contains(($0 as NSString).pathExtension.lowercased()) }
        let shots = images.filter(isScreenshotName)
        guard let best = (shots.isEmpty ? images : shots).max(by: { mtime($0) < mtime($1) }) else { throw IntelligenceError.notFound("a screenshot in \(Agent.short(dir))") }
        return dir + "/" + best
    }

    /// Resolve "latest screenshot" / an image path / a folder's newest image.
    static func imagePath(from spec: String) throws -> String {
        let s = spec.trimmingCharacters(in: .whitespaces).lowercased()
        if s.isEmpty || s.contains("latest") || s.contains("last") || s == "screenshot" || s == "this screenshot" { return try latestScreenshot() }
        let real = try PathPolicy.resolve(spec)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: real, isDirectory: &isDir), isDir.boolValue { return try latestScreenshot(in: real) }
        return real
    }

    @Generable
    struct ShotName {
        @Guide(description: "3 to 6 lowercase words joined by hyphens that say what the screenshot shows (app or site, and the subject). No dates, no numbers unless essential, no file extension.")
        var slug: String
    }

    /// A descriptive filename from OCR text: "2026-08-01-invoice-acme-august.png"
    static func proposeName(for path: String) async throws -> String? {
        let name = (path as NSString).lastPathComponent
        let ext = (path as NSString).pathExtension.lowercased()
        let text = (try? ocr(URL(fileURLWithPath: path))) ?? ""
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 3, FoundationTier.isAvailable else { return nil }
        let session = LanguageModelSession(instructions: "You name screenshot files from the text visible in them. Be specific and short.")
        let r = try await session.respond(to: "Text in the screenshot:\n\(text.prefix(1500))", generating: ShotName.self, options: GenerationOptions(sampling: .greedy))
        var slug = r.content.slug.lowercased().replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        slug = slug.split(separator: "-").prefix(6).joined(separator: "-")
        guard slug.count >= 3 else { return nil }
        let date: String
        if let r = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) { date = String(name[r]) }
        else {
            let m = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? Date()
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; date = f.string(from: m)
        }
        return "\(date)-\(slug).\(ext)"
    }

    /// Proposed renames for screenshots in a folder (newest first, capped). Unique names guaranteed.
    static func proposeRenames(in folder: String, limit: Int = 40, status: @escaping (String) -> Void) async throws -> [(from: String, to: String)] {
        let dir = try PathPolicy.resolve(folder)
        let fm = FileManager.default
        func mtime(_ n: String) -> Date { (try? fm.attributesOfItem(atPath: dir + "/" + n)[.modificationDate] as? Date) ?? .distantPast }
        let shots = ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
            .filter { isScreenshotName($0) && imageExts.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { mtime($0) > mtime($1) }.prefix(limit)
        var out: [(String, String)] = []; var used = Set<String>()
        for (i, n) in shots.enumerated() {
            status("Reading screenshot \(i + 1) of \(shots.count)…")
            guard var newName = try? await proposeName(for: dir + "/" + n) else { continue }
            var k = 2
            while used.contains(newName) || fm.fileExists(atPath: dir + "/" + newName) {
                let base = (newName as NSString).deletingPathExtension, ext = (newName as NSString).pathExtension
                newName = "\(base)-\(k).\(ext)"; k += 1
            }
            used.insert(newName); out.append((dir + "/" + n, newName))
        }
        return out
    }

    // MARK: Local vision model (LM Studio)

    static func describe(_ paths: [String], prompt: String, status: @escaping (String) -> Void) async throws -> String {
        guard await LMStudioTier.isReachable() else { throw IntelligenceError.unavailable("Image understanding needs LM Studio running (lms server start); OCR still works without it") }
        return try await LMStudioTier.vision(imagePaths: paths, prompt: prompt, status: status)
    }

    // MARK: Tools for the planner

    static let tools: [HostTool] = [
        HostTool(name: "extractTextFromImage", description: "Read the text in an image or screenshot (on-device OCR). Path may be 'latest screenshot'.",
                 schema: HostTool.schema([("path", "string", "Image path, or 'latest screenshot'")], required: ["path"]), readOnly: true, destructive: false) { a in
            let p = try imagePath(from: HostTools.string(a, "path"))
            let t = try ocr(URL(fileURLWithPath: p))
            return t.isEmpty ? "No text found in \(Agent.short(p))." : "Text from \(Agent.short(p)):\n\(t)"
        },
        HostTool(name: "describeImage", description: "Describe an image or answer a question about it using the local vision model (needs LM Studio). Path may be 'latest screenshot'.",
                 schema: HostTool.schema([("path", "string", "Image path or 'latest screenshot'"), ("question", "string", "Optional question")], required: ["path"]), readOnly: true, destructive: false) { a in
            let p = try imagePath(from: HostTools.string(a, "path"))
            let q = HostTools.string(a, "question")
            return try await describe([p], prompt: q.isEmpty ? "Describe this image precisely: what it shows, any text, and anything that looks wrong." : q, status: { _ in })
        },
        HostTool(name: "compareImages", description: "Compare two images (e.g. a screenshot against a design) and list the differences, using the local vision model.",
                 schema: HostTool.schema([("path", "string", "First image"), ("path2", "string", "Second image"), ("question", "string", "Optional focus, e.g. 'spacing and colors'")], required: ["path", "path2"]), readOnly: true, destructive: false) { a in
            let p1 = try imagePath(from: HostTools.string(a, "path")), p2 = try imagePath(from: HostTools.string(a, "path2"))
            let q = HostTools.string(a, "question")
            return try await describe([p1, p2], prompt: "Image 1 is the actual result, image 2 is the expected design. List every visible difference (layout, spacing, colors, text, missing or extra elements) as short bullets, most important first." + (q.isEmpty ? "" : " Focus on: \(q)."), status: { _ in })
        },
        HostTool(name: "proposeScreenshotNames", description: "Propose descriptive filenames for screenshots in a folder based on their content (does not rename). Use renameItem to apply.",
                 schema: HostTool.schema([("folder", "string", "Folder (default: where screenshots are saved)")], required: []), readOnly: true, destructive: false) { a in
            let f = HostTools.string(a, "folder")
            let props = try await proposeRenames(in: f.isEmpty ? screenshotsFolder() : f, status: { _ in })
            return props.isEmpty ? "No screenshots to rename." : props.map { "\(($0.from as NSString).lastPathComponent) → \($0.to)" }.joined(separator: "\n")
        },
    ]
}
