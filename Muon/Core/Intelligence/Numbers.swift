import Foundation

/// Exact arithmetic for "largest transaction", "smallest payment", "how much in total" over statement-like text.
/// Small models misread tables; these facts are computed from the text and handed to the model to explain.
enum Numbers {
    struct Amount { let value: Double; let text: String; let line: String; var context: String = "" }
    struct Wants { var largest = false, smallest = false, total = false }

    private static let amountRe = try! NSRegularExpression(pattern: #"(?<![\d.,])(?:\d{1,3}(?:,\d{3})+(?:\.\d{1,2})?|\d+\.\d{2})(?![\d,])"#)

    static func wants(_ q: String) -> Wants? {
        let l = q.lowercased()
        var w = Wants()
        w.largest = l.range(of: #"\b(largest|biggest|highest|max(imum)?|most expensive|top)\b"#, options: .regularExpression) != nil
        w.smallest = l.range(of: #"\b(smallest|lowest|min(imum)?|cheapest|least)\b"#, options: .regularExpression) != nil
        w.total = l.range(of: #"\b(total|sum|altogether|in all|how much (did|have|was|were)|add up|overall spend)\b"#, options: .regularExpression) != nil
        return (w.largest || w.smallest || w.total) ? w : nil
    }

    /// Summary rows of a statement are not transactions.
    private static let summaryRow = try! NSRegularExpression(pattern: #"(?i)\b(total|sub-?total|opening|closing|balance forward|brought forward|carried forward|b/f|c/f|summary|grand total)\b"#)

    static func isSummaryRow(_ line: String) -> Bool { summaryRow.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil }

    private static let headerWords: Set<String> = ["date", "description", "amount", "balance", "particulars", "debit", "credit", "cheque", "deposit", "withdrawal", "withdrawals", "deposits",
                                                    "narration", "details", "value", "txn", "transaction", "no", "no.", "ref", "sl", "dr", "cr", "type", "mode", "remarks", "closing", "opening"]

    /// A column-header line ("Date Description Amount Balance") is not a description.
    static func isHeaderLine(_ line: String) -> Bool {
        let words = line.lowercased().split(whereSeparator: { $0 == " " || $0 == "/" }).map(String.init)
        return !words.isEmpty && words.allSatisfy { headerWords.contains($0) }
    }

    /// Amounts per line, in order; each carries the line directly above when that line is a description (letters, no amounts, not a header).
    static func amounts(in text: String) -> [[Amount]] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
        var out: [[Amount]] = []
        var previousDescription = ""
        for line in lines {
            let ns = line as NSString
            let found = amountRe.matches(in: line, range: NSRange(location: 0, length: ns.length)).compactMap { m -> Amount? in
                let t = ns.substring(with: m.range)
                guard let v = Double(t.replacingOccurrences(of: ",", with: "")), v > 0 else { return nil }
                return Amount(value: v, text: t, line: line, context: previousDescription)
            }
            previousDescription = found.isEmpty && line.count > 3 && line.rangeOfCharacter(from: .letters) != nil && !isHeaderLine(line) && !isSummaryRow(line) ? line : ""
            out.append(found)
        }
        return out
    }

    /// Sentences that state amounts or superlatives are dropped from a model's narrative when the figures were computed exactly.
    static func withoutFigures(_ narrative: String) -> String {
        let parts = narrative.replacingOccurrences(of: "\n", with: " ").components(separatedBy: ". ")
        let kept = parts.filter { s in
            s.range(of: #"\d{1,3}(,\d{3})+|\d+\.\d{2}|\b(largest|smallest|biggest|highest|lowest|total|maximum|minimum)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
        }
        let joined = kept.joined(separator: ". ").trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "" : (joined.hasSuffix(".") ? joined : joined + ".")
    }

    static let header = "Exact figures, computed from the document text:"

    /// A short block of exact facts for the question, or nil when the question does not ask for any.
    static func facts(question: String, text: String) -> String? {
        guard let w = wants(question) else { return nil }
        let rows = amounts(in: text).filter { !$0.isEmpty }
        guard rows.count >= 3 else { return nil }
        let multi = rows.filter { $0.count >= 2 }
        let tableLike = multi.count >= 3 && multi.count * 2 >= rows.count
        let q = question.lowercased()
        let aboutBalance = q.contains("balance")
        let aboutMoves = q.range(of: #"\b(transaction|payment|debit|credit|withdraw|deposit|spent|spend|paid|received|purchase|transfer|expense|charge)"#, options: .regularExpression) != nil
        let pool: [Amount]
        if tableLike, aboutBalance { pool = multi.compactMap(\.last) }
        else if tableLike, aboutMoves { pool = multi.filter { !isSummaryRow($0[0].line) }.flatMap { Array($0.dropLast()) } }   // trailing figure = running balance; single-figure lines are balances too
        else { pool = rows.flatMap { $0 } }
        guard !pool.isEmpty else { return nil }
        func short(_ s: String) -> String { s.count > 90 ? String(s.prefix(90)) + "…" : s }
        func where_(_ a: Amount) -> String { a.context.isEmpty || a.line.contains(a.context) ? short(a.line) : short(a.context) + " · " + short(a.line) }
        var lines: [String] = [header]
        if w.largest {
            for (i, a) in pool.sorted(by: { $0.value > $1.value }).prefix(3).enumerated() {
                lines.append("- \(i == 0 ? "Largest" : "Next largest") amount: \(a.text) — \(where_(a))")
            }
        }
        if w.smallest, let a = pool.min(by: { $0.value < $1.value }) { lines.append("- Smallest amount: \(a.text) — \(where_(a))") }
        if w.total {
            let sum = pool.reduce(0) { $0 + $1.value }
            let f = NumberFormatter(); f.numberStyle = .decimal; f.minimumFractionDigits = 2; f.maximumFractionDigits = 2
            lines.append("- Total of \(pool.count) amounts\(tableLike && aboutMoves ? " (running balances excluded)" : ""): \(f.string(from: NSNumber(value: sum)) ?? String(sum))")
        }
        return lines.joined(separator: "\n")
    }
}
