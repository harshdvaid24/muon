import Foundation

/// Deterministic parser for writing requests, so "fix grammar" or "translate to hindi" never depends on a model
/// guessing the intent. The text comes from the clipboard, an inline "…: text", or a file path in the request.
struct WritingIntent: Equatable {
    enum Source: Equatable { case clipboard, inline(String), file(String) }
    var instruction: String
    var label: String
    var source: Source

    static let explainInstruction = "Explain this in plain language for a smart non-expert. If it is an error or stack trace, say what went wrong, the most likely cause, and the fix, in that order. Be brief."

    static let analysisInstruction = "Analyse this document. Start with a 2-4 sentence brief of what it is and what it says. Then list the key facts, figures, dates, amounts and parties as short bullets starting with '- '. End with anything unusual or worth attention, or 'Nothing unusual.'"

    static func summaryInstruction(_ length: String) -> String {
        switch length.lowercased() {
        case "one line", "one-line", "1 line", "tldr", "tl;dr": return "Summarize in one sentence."
        case "bullets", "bullet points", "points": return "Summarize as 3-7 short bullet points, each starting with '- '."
        case "detailed", "long": return "Write a detailed summary covering every main point, in short paragraphs."
        default: return "Summarize in 2-4 sentences."
        }
    }

    // ordered: first match wins
    private static let rules: [(pattern: String, make: ([String]) -> (String, String))] = [
        (#"^(fix|correct|proofread)( the| my)?( grammar| spelling| typos| this| it| text)*$"#, { _ in ("Fix grammar, spelling and punctuation. Change nothing else.", "Fixed") }),
        (#"^(tl;?dr|summari[sz]e)( this| it| the clipboard| text)?( (in one line|in one sentence|as bullets|in bullets|as bullet points|briefly|in detail))?$"#, { g in (summaryInstruction(g[3].lowercased().trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "in ", with: "").replacingOccurrences(of: "as ", with: "")), "Summary") }),
        (#"^(give me |)(a |the |quick |short )*(brief|overview|gist|rundown|summary)( of (this|it|the (file|document|pdf|text)))?$"#, { _ in (summaryInstruction("short"), "Brief") }),
        (#"^(analy[sz]e|review|assess|go through|look at)( this| it)?( (file|document|pdf|statement|report|contract|text))?( and (give me|write) (a |the )?(brief|summary|overview))?$"#, { _ in (analysisInstruction, "Analysis") }),
        (#"^(make|rewrite)( this| it| the text)?( sound| to be| in a| as| more)? ?(professional|formal|casual|friendly|polite|confident|concise|clear|simple|warm|neutral|direct|persuasive)( tone)?$"#, { g in ("Rewrite in a \(g[3].lowercased()) tone. Keep the meaning.", "\(g[3].capitalized) version") }),
        (#"^(shorten|condense|make (this|it) shorter|make (this|it) (more )?concise)$"#, { _ in ("Shorten to about half the length. Keep every key point.", "Shorter") }),
        (#"^(expand|elaborate|make (this|it) longer)( on this| this)?$"#, { _ in ("Expand with more detail and smoother flow, keeping the same facts.", "Expanded") }),
        (#"^(simplify|make (this|it) simpler|explain like i'?m five|eli5)$"#, { _ in ("Rewrite in simple, plain language a 12-year-old would understand.", "Simplified") }),
        (#"^(bullet ?points|bullets|turn (this|it) into bullets|as bullets)$"#, { _ in ("Turn this into short bullet points, each starting with '- '.", "Bullets") }),
        (#"^(translate|convert)( this| it| the text)?( to| into) ([a-z][a-z -]{1,30}?)$"#, { g in ("Translate into \(g[3].capitalized). Output only the translation.", "Translation (\(g[3].capitalized))") }),
        (#"^(explain|what does this mean|what is this|explain this (error|code|message))( this| it| this error| this code)?$"#, { _ in (explainInstruction, "Explanation") }),
        (#"^(reply|respond|answer)( to (this|it))?( (saying|that|with|:) ?(.+))?$"#, { g in ("Draft a reply to this message" + (g[5].isEmpty ? "." : ", following this guidance: \(g[5])."), "Reply") }),
        (#"^(extract|list|pull out)( the| all)? (dates|amounts|numbers|emails|email addresses|names|action items|todos|tasks|links|urls|phone numbers|key points)( from (this|it|the text))?$"#, { g in ("Extract all the \(g[2].lowercased()) from the text as a plain list, one per line. If none, say 'None found'.", "\(g[2].capitalized)") }),
        (#"^(what does( it| this| that| the (file|document|pdf|page|text))? say about|what does( it| this| the (file|document|pdf))? say regarding|does (it|this) mention|find in (it|this)|look for)\s+(.+)$"#, { g in ("Using only the text, answer: what does it say about \(g.last ?? "")? Quote the relevant part briefly and be specific. If it says nothing about that, say so.", "About \(g.last ?? "")") }),
        (#"^(ask|question)[:]?\s+(.+)$"#, { g in ("Using only the text, answer this question briefly and specifically: \(g[1])", "Answer") }),
        (#"^(draft|write)( an?| the)? (email|message|note|tweet|post)( about| saying| that)? (.+)$"#, { g in ("Write a \(g[2]) about: \(g[4]). Be natural and concise.", "\(g[2].capitalized) draft") }),
    ]

    static func parse(_ raw: String) -> WritingIntent? {
        var q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.contains("://") { return nil }
        // "translate to french: hello there" → inline text after the first colon
        var inline: String?
        if let colon = q.firstIndex(of: ":") {
            let head = String(q[..<colon]).trimmingCharacters(in: .whitespaces)
            let tail = String(q[q.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            // A short head, or one that is mostly a file path ("ask \"~/My Docs/lease.pdf\": who pays").
            if !tail.isEmpty, !head.contains(" http"), head.count < 60 || !PathPolicy.paths(in: head).isEmpty { inline = tail; q = head }
        }
        // file source: "summarize ~/Documents/x.txt", quoted paths may contain spaces
        var file: String?
        if let p = PathPolicy.paths(in: q).first {
            file = p
            q = q.replacingOccurrences(of: "\"\(p)\"", with: "").replacingOccurrences(of: p, with: "")
                .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        }
        // "ask ~/x.txt: who is the owner" → the file is the source and the text after the colon is the question.
        if let f = file, let inl = inline, q.range(of: #"^(ask|question)$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            q += " " + inl; inline = nil; file = f
        }
        // Match case-insensitively on the original text so guidance like "I'll be there at 5" keeps its case.
        let base = q.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: CharacterSet(charactersIn: " .!?"))
        for rule in rules {
            guard let re = try? NSRegularExpression(pattern: rule.pattern, options: .caseInsensitive),
                  let m = re.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)) else { continue }
            let groups = (1..<m.numberOfRanges).map { i in Range(m.range(at: i), in: base).map { String(base[$0]) } ?? "" }
            let (instruction, label) = rule.make(groups)
            let source: Source = file.map { .file($0) } ?? inline.map { .inline($0) } ?? .clipboard
            return WritingIntent(instruction: instruction, label: label, source: source)
        }
        return nil
    }
}
