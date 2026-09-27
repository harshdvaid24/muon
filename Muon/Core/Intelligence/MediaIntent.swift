import Foundation

/// Deterministic parser for screenshot/image/web/crash requests.
enum MediaIntent: Equatable {
    case ocr(String)                      // image spec ("latest screenshot" or path)
    case explainScreenshot(String)
    case describe(String, String)         // spec, question
    case compare(String, String)
    case renameScreenshots(String?)       // folder
    case webPage(String, String)          // url, instruction
    case crash(String?)                   // app filter
    case transcribe(String)               // audio/video path
    case meetingNotes(String)
    case receipts(String)                 // folder

    static func parse(_ raw: String) -> MediaIntent? {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()
        // web pages
        if let r = q.range(of: #"https?://[^\s]+"#, options: .regularExpression) {
            let url = String(q[r]).trimmingCharacters(in: CharacterSet(charactersIn: ".,)"))
            let rest = q.replacingCharacters(in: r, with: "").lowercased()
            let instruction: String
            if rest.contains("bullet") { instruction = WritingIntent.summaryInstruction("bullets") }
            else if let m = rest.range(of: #"(what does it say about|what does .* say about|about|regarding)\s+(.+)$"#, options: .regularExpression) {
                let topic = String(rest[m]).replacingOccurrences(of: #"^(what does it say about|what does .* say about|about|regarding)\s+"#, with: "", options: .regularExpression)
                instruction = "Using only the page text, answer: what does it say about \(topic)? Be specific and brief."
            } else if rest.contains("summar") || rest.contains("tldr") || rest.trimmingCharacters(in: .whitespaces).isEmpty || rest.contains("read") {
                instruction = WritingIntent.summaryInstruction("short")
            } else { instruction = "Using only the page text, answer this: \(rest.trimmingCharacters(in: .whitespaces))" }
            return .webPage(url, instruction)
        }
        let paths = PathPolicy.paths(in: q)
        if let p = paths.first, Transcriber.audioExts.contains((p as NSString).pathExtension.lowercased()) {
            if lower.range(of: #"meeting|notes|action items|summar"#, options: .regularExpression) != nil { return .meetingNotes(p) }
            if lower.range(of: #"^(transcribe|transcription|what was said|write down|convert .* to text)"#, options: .regularExpression) != nil { return .transcribe(p) }
        }
        if lower.range(of: #"(total|sum|add up|tally|expense report).*receipts?|receipts?.*(total|sum|add up)"#, options: .regularExpression) != nil, let p = paths.first { return .receipts(p) }
        // rename screenshots
        if lower.range(of: #"^(rename|name|auto-?name)( the| my| all)? screenshots"#, options: .regularExpression) != nil {
            return .renameScreenshots(paths.first)
        }
        // compare two images
        if lower.hasPrefix("compare"), paths.count >= 2 { return .compare(paths[0], paths[1]) }
        if lower.hasPrefix("compare"), lower.contains("screenshot"), paths.count == 1 { return .compare("latest screenshot", paths[0]) }
        // crash
        if let m = lower.range(of: #"^(why did|why does|why is)( my)?\s*(.*?)\s*(crash|crashing|crashed|quit unexpectedly)"#, options: .regularExpression) {
            let app = String(lower[m]).replacingOccurrences(of: #"^(why did|why does|why is)( my)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s*(crash|crashing|crashed|quit unexpectedly).*$"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            return .crash(app.isEmpty || app == "app" || app == "the app" || app == "mac" ? nil : app)
        }
        if lower.range(of: #"^(show|list|check)( the| recent| latest)? crash(es| reports| logs)?"#, options: .regularExpression) != nil { return .crash(nil) }
        // screenshot / image
        let mentionsShot = lower.contains("screenshot") || lower.contains("screen shot")
        let spec = paths.first ?? (mentionsShot ? "latest screenshot" : "")
        if lower.range(of: #"^(explain|what('s| is) wrong (with|in)|what does this error|debug)"#, options: .regularExpression) != nil, mentionsShot || (!paths.isEmpty && VisionTools.imageExts.contains(((paths.first ?? "") as NSString).pathExtension.lowercased())) {
            return .explainScreenshot(spec)
        }
        if lower.range(of: #"^(read|ocr|copy|extract|get)( the| all)?( text)?( from| in| of)?"#, options: .regularExpression) != nil, mentionsShot || isImage(paths.first) {
            return .ocr(spec)
        }
        if lower.range(of: #"^(describe|what('s| is) in|what do you see in|look at|analy[sz]e)"#, options: .regularExpression) != nil, mentionsShot || isImage(paths.first) {
            let question = q.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            return .describe(spec, question)
        }
        return nil
    }

    private static func isImage(_ p: String?) -> Bool {
        guard let p else { return false }
        return VisionTools.imageExts.contains((p as NSString).pathExtension.lowercased())
    }
}
