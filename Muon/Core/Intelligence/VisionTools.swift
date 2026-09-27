import Foundation
import PDFKit
import Vision

/// On-device OCR via the Vision framework.
enum VisionTools {
    static func ocr(_ url: URL) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url)
        try handler.perform([req])
        let obs = (req.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }
        return obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func ocr(cgImage: CGImage) throws -> String {
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        try VNImageRequestHandler(cgImage: cgImage).perform([req])
        return (req.results ?? []).sorted { $0.boundingBox.minY > $1.boundingBox.minY }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
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
}
