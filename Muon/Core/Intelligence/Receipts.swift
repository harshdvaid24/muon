import Foundation
import FoundationModels

/// Receipts and invoices → an expense table + CSV, from OCR plus on-device extraction.
enum Receipts {
    @Generable
    struct Fields {
        @Guide(description: "Merchant or store name")
        var merchant: String
        @Guide(description: "Date as YYYY-MM-DD if visible, otherwise empty")
        var date: String
        @Guide(description: "The grand total paid, as a number")
        var total: Double
        @Guide(description: "3-letter currency code such as INR, USD, EUR; empty if not shown")
        var currency: String
    }

    struct Row { let file: String; let merchant: String; let date: String; let total: Double; let currency: String }

    /// Regex fallback: the largest amount on a line mentioning total/amount/paid, else the largest amount.
    static func fallbackTotal(_ text: String) -> Double? {
        let re = try! NSRegularExpression(pattern: #"(\d{1,3}(?:[,\s]\d{3})*(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)"#)
        func amounts(_ s: String) -> [Double] {
            re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in Range(m.range, in: s).flatMap { Double(s[$0].replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: "")) } }
        }
        let lines = text.split(separator: "\n").map(String.init)
        let totalLines = lines.filter { $0.range(of: #"total|amount|paid|grand"#, options: [.regularExpression, .caseInsensitive]) != nil }
        if let t = totalLines.flatMap(amounts).max() { return t }
        return lines.flatMap(amounts).max()
    }

    static func extract(_ text: String) async throws -> Fields {
        if FoundationTier.isAvailable {
            let session = LanguageModelSession(instructions: "Extract receipt fields exactly as printed. The total is the final amount paid.")
            if let r = try? await session.respond(to: "Receipt text:\n\(text.prefix(3000))", generating: Fields.self, options: GenerationOptions(sampling: .greedy)) {
                if r.content.total > 0 { return r.content }
            }
        }
        return Fields(merchant: text.split(separator: "\n").first.map(String.init) ?? "?", date: "", total: fallbackTotal(text) ?? 0, currency: "")
    }

    static func total(folder: String, status: @escaping (String) -> Void) async throws -> (rows: [Row], summary: String, csv: String) {
        let dir = try PathPolicy.resolve(folder)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter {
            let e = ($0 as NSString).pathExtension.lowercased(); return VisionTools.imageExts.contains(e) || e == "pdf"
        }.sorted().prefix(60)
        guard !names.isEmpty else { throw IntelligenceError.noInput("No receipt images or PDFs in \(Agent.short(dir)).") }
        var rows: [Row] = []
        for (i, n) in names.enumerated() {
            status("Reading receipt \(i + 1) of \(names.count)…")
            guard let text = try? Documents.text(at: dir + "/" + n), !text.isEmpty else { continue }
            let f = try await extract(text)
            rows.append(Row(file: n, merchant: f.merchant, date: f.date, total: f.total, currency: f.currency.uppercased()))
        }
        var byCurrency: [String: Double] = [:]
        for r in rows { byCurrency[r.currency.isEmpty ? "?" : r.currency, default: 0] += r.total }
        let table = rows.map { String(format: "%10.2f %-4@  %-12@ %@ — %@", $0.total, $0.currency.isEmpty ? "" : $0.currency, $0.date, $0.merchant, $0.file) }.joined(separator: "\n")
        let totals = byCurrency.map { String(format: "%@ %.2f", $0.key == "?" ? "" : $0.key, $0.value) }.joined(separator: " · ")
        let csv = "file,merchant,date,total,currency\n" + rows.map { "\"\($0.file)\",\"\($0.merchant.replacingOccurrences(of: "\"", with: "\"\""))\",\($0.date),\($0.total),\($0.currency)" }.joined(separator: "\n") + "\n"
        return (rows, "\(rows.count) receipts · total \(totals)\n\(table)", csv)
    }

    static let tools: [HostTool] = [
        HostTool(name: "totalReceipts", description: "Read every receipt image/PDF in a folder (OCR + extraction) and return merchant, date, total and currency per receipt plus the sum. Returns CSV text after the table; use writeTextFile to save it.",
                 schema: HostTool.schema([("folder", "string", "Folder with receipts")], required: ["folder"]), readOnly: true, destructive: false) { a in
            let r = try await total(folder: HostTools.string(a, "folder"), status: { _ in })
            return r.summary + "\n\nCSV:\n" + r.csv
        },
    ]
}
