import Foundation

/// Translate app localization files (.json, .strings, .arb) into other languages, keeping placeholders intact.
enum Localization {
    enum Format { case json, strings, arb }
    struct Entry { let key: String; let value: String }

    static let languageCodes: [String: String] = [
        "hindi": "hi", "gujarati": "gu", "marathi": "mr", "bengali": "bn", "bangla": "bn", "tamil": "ta", "telugu": "te", "kannada": "kn",
        "malayalam": "ml", "odia": "or", "oriya": "or", "punjabi": "pa", "urdu": "ur", "spanish": "es", "french": "fr", "german": "de",
        "italian": "it", "portuguese": "pt", "japanese": "ja", "korean": "ko", "chinese": "zh", "arabic": "ar", "russian": "ru",
        "indonesian": "id", "vietnamese": "vi", "thai": "th", "turkish": "tr", "dutch": "nl", "english": "en", "polish": "pl", "swedish": "sv",
    ]

    static func format(for path: String) -> Format? {
        switch (path as NSString).pathExtension.lowercased() { case "json": return .json; case "strings": return .strings; case "arb": return .arb; default: return nil }
    }

    // MARK: Parse / render

    static func entries(_ text: String, format: Format) throws -> [Entry] {
        switch format {
        case .strings:
            let re = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;"#)
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
                guard let k = Range(m.range(at: 1), in: text), let v = Range(m.range(at: 2), in: text) else { return nil }
                return Entry(key: String(text[k]), value: String(text[v]))
            }
        case .json, .arb:
            guard let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw IntelligenceError.noInput("That file is not a JSON object of strings.") }
            var out: [Entry] = []
            func walk(_ o: [String: Any], _ prefix: String) {
                for (k, v) in o.sorted(by: { $0.key < $1.key }) {
                    if format == .arb, k.hasPrefix("@") { continue }
                    if let s = v as? String { out.append(Entry(key: prefix + k, value: s)) }
                    else if let d = v as? [String: Any] { walk(d, prefix + k + ".") }
                }
            }
            walk(obj, "")
            return out
        }
    }

    static func render(_ text: String, format: Format, translations: [String: String]) throws -> String {
        switch format {
        case .strings:
            let re = try NSRegularExpression(pattern: #"("((?:[^"\\]|\\.)*)"\s*=\s*")((?:[^"\\]|\\.)*)("\s*;)"#)
            let ns = text as NSString
            var out = ""; var last = 0
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let key = ns.substring(with: m.range(at: 2))
                out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
                out += ns.substring(with: m.range(at: 1)) + (translations[key].map(escape) ?? ns.substring(with: m.range(at: 3))) + ns.substring(with: m.range(at: 4))
                last = m.range.location + m.range.length
            }
            return out + ns.substring(from: last)
        case .json, .arb:
            guard let obj = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { throw IntelligenceError.noInput("not a JSON object") }
            func walk(_ o: [String: Any], _ prefix: String) -> [String: Any] {
                var r = o
                for (k, v) in o {
                    if format == .arb, k.hasPrefix("@") { continue }
                    if v is String, let t = translations[prefix + k] { r[k] = t }
                    else if let d = v as? [String: Any] { r[k] = walk(d, prefix + k + ".") }
                }
                return r
            }
            let data = try JSONSerialization.data(withJSONObject: walk(obj, ""), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            return String(decoding: data, as: UTF8.self) + "\n"
        }
    }

    private static func escape(_ s: String) -> String { s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") }

    // MARK: Translate

    /// Translates values in numbered batches; placeholders like {name}, %@, %d, {{count}}, $1 are preserved.
    static func translate(_ entries: [Entry], to language: String, translator: (String) async throws -> String) async throws -> [String: String] {
        var out: [String: String] = [:]
        let batches = stride(from: 0, to: entries.count, by: 30).map { Array(entries[$0..<min($0 + 30, entries.count)]) }
        for batch in batches {
            let numbered = batch.enumerated().map { "\($0.offset + 1). \($0.element.value.replacingOccurrences(of: "\n", with: "⏎"))" }.joined(separator: "\n")
            let instruction = "Translate each numbered line into \(language) for a mobile app UI. Keep placeholders exactly as they are: things like {name}, {{count}}, %@, %d, %1$s, $1, <b>…</b>. Keep the numbering and output only the translated lines, one per line, nothing else."
            let result = try await translator("\(instruction)\n\n<<<\n\(numbered)\n>>>")
            let lines = parseNumbered(result)
            for (i, e) in batch.enumerated() {
                if let t = lines[i + 1], !t.isEmpty { out[e.key] = t.replacingOccurrences(of: "⏎", with: "\n") }
                else { out[e.key] = try await translator("Translate into \(language) for a mobile app UI, keeping placeholders unchanged. Output only the translation.\n\n<<<\n\(e.value)\n>>>") }
            }
        }
        return out
    }

    static func parseNumbered(_ s: String) -> [Int: String] {
        var out: [Int: String] = [:]
        for line in s.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard let m = t.range(of: #"^(\d{1,3})[.)]\s*"#, options: .regularExpression), let n = Int(t[m].trimmingCharacters(in: CharacterSet(charactersIn: ".) "))) else { continue }
            out[n] = String(t[m.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return out
    }

    /// en.json → hi.json · en.lproj/Localizable.strings → hi.lproj/Localizable.strings · app_en.arb → app_hi.arb · x.json → x.hi.json
    static func outputPath(source: String, code: String) -> String {
        let dir = (source as NSString).deletingLastPathComponent, name = (source as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        if (dir as NSString).lastPathComponent.hasSuffix(".lproj") {
            return ((dir as NSString).deletingLastPathComponent as NSString).appendingPathComponent("\(code).lproj/\(name)")
        }
        if stem.range(of: #"^[a-z]{2}(-[A-Za-z]{2,4})?$"#, options: .regularExpression) != nil { return (dir as NSString).appendingPathComponent("\(code).\(ext)") }
        if let r = stem.range(of: #"[_-]en$"#, options: .regularExpression) { return (dir as NSString).appendingPathComponent(stem.replacingCharacters(in: r, with: String(stem[r].prefix(1)) + code) + "." + ext) }
        return (dir as NSString).appendingPathComponent("\(stem).\(code).\(ext)")
    }

    // MARK: Intent

    struct Intent: Equatable { let path: String; let languages: [String] }

    /// "translate ~/app/en.json to hindi and gujarati", "localize ~/x.strings into spanish, french"
    static func parseIntent(_ q: String) -> Intent? {
        let lower = q.lowercased()
        guard lower.range(of: #"^(translate|localize|localise|add .*translations? (for|to))"#, options: .regularExpression) != nil,
              let path = PathPolicy.paths(in: q).first, format(for: path) != nil else { return nil }
        let after = lower.replacingOccurrences(of: path.lowercased(), with: " ")
        let langs = languageCodes.keys.filter { after.range(of: #"\b"# + $0 + #"\b"#, options: .regularExpression) != nil && $0 != "english" }.sorted()
        return langs.isEmpty ? nil : Intent(path: path, languages: langs)
    }

    static let tools: [HostTool] = [
        HostTool(name: "translateStringsFile", description: "Translate an app localization file (.json, .strings, .arb) into languages, keeping placeholders. Returns the proposed output files' contents; use writeTextFile to save them.",
                 schema: HostTool.schema([("path", "string", "Source file"), ("languages", "string", "Comma-separated, e.g. 'hindi, gujarati'")], required: ["path", "languages"]), readOnly: true, destructive: false) { a in
            let real = try PathPolicy.resolve(HostTools.string(a, "path"))
            guard let fmt = format(for: real) else { throw IntelligenceError.noInput("Supported: .json, .strings, .arb") }
            let text = try Documents.text(at: real)
            let ents = try entries(text, format: fmt)
            var out: [String] = []
            for lang in HostTools.string(a, "languages").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                let tr = try await translate(ents, to: lang.capitalized) { try await TextTools.generate(instruction: "", input: $0) }
                let code = languageCodes[lang.lowercased()] ?? String(lang.prefix(2)).lowercased()
                out.append("=== \(outputPath(source: real, code: code)) ===\n" + (try render(text, format: fmt, translations: tr)))
            }
            return out.joined(separator: "\n")
        },
    ]
}
