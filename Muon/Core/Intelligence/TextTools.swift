import AppKit
import Foundation
import FoundationModels

/// Everyday writing help on any text, on-device first: rewrite, fix, shorten, translate, summarize, explain, reply, extract.
enum TextTools {
    static let system = """
    You are a precise writing assistant. Output only the finished result: no preamble, no commentary, no quotation marks around it.
    Keep the author's meaning, facts, names and formatting (paragraphs, lists, line breaks) unless the instruction says otherwise.
    Never add information that is not in the text.
    """

    /// Roughly 4 characters per token. The on-device model has a ~4k context, so keep inputs under ~2,200 tokens there.
    static let onDeviceInputLimit = 8_800

    static func generate(instruction: String, input: String, status: @escaping (String) -> Void = { _ in }) async throws -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw IntelligenceError.noInput("There's no text to work on. Copy some text (⌘C) or name a file, then ask again.") }
        if text.count <= onDeviceInputLimit, FoundationTier.isAvailable {
            status("Writing on-device…")
            do { return try await onDevice(instruction: instruction, input: text) }
            catch let e as LanguageModelSession.GenerationError {
                switch e {
                case .exceededContextWindowSize, .unsupportedLanguageOrLocale: break   // fall through to the local model
                case .guardrailViolation, .refusal: if await LMStudioTier.isReachable() { break } else { throw IntelligenceError.refused("the on-device model won't handle this text; start LM Studio to use the local model instead.") }
                default: throw e
                }
            }
        }
        // Medium text (a few pages) is faster in on-device parts than waiting for LM Studio to load a model;
        // when the local model is already loaded, it gets the whole text for a better answer.
        let lmUp = await LMStudioTier.isReachable()
        let lmLoaded = lmUp ? !(await LMStudioTier.loadedModels()).isEmpty : false
        if FoundationTier.isAvailable, text.count <= 4 * onDeviceInputLimit, !lmLoaded {
            status("Working in parts, on-device…")
            return try await chunked(instruction: instruction, input: text)
        }
        if lmUp {
            status("Writing with the local model…")
            return try await LMStudioTier.complete(system: system, user: "\(instruction)\n\n<<<\n\(text)\n>>>", status: status)
        }
        guard FoundationTier.isAvailable else { throw IntelligenceError.unavailable("Apple Intelligence") }
        status("Long text: working in parts…")
        return try await chunked(instruction: instruction, input: text)
    }

    private static func onDevice(instruction: String, input: String) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        let r = try await session.respond(to: "\(instruction)\n\n<<<\n\(input)\n>>>", options: GenerationOptions(temperature: 0.3))
        return clean(r.content)
    }

    static let chunkLimit = 6_000

    /// Paragraph-aligned chunks; paragraphs longer than a chunk are split by line, then by length (PDF tables).
    static func chunks(of input: String, limit: Int = chunkLimit) -> [String] {
        var units: [String] = []
        for para in input.components(separatedBy: "\n\n") {
            if para.count <= limit { units.append(para); continue }
            for line in para.split(separator: "\n", omittingEmptySubsequences: true).map(String.init) {
                if line.count <= limit { units.append(line); continue }
                var rest = Substring(line)
                while !rest.isEmpty { units.append(String(rest.prefix(limit))); rest = rest.dropFirst(limit) }
            }
        }
        var out: [String] = []; var cur = ""
        for u in units {
            if cur.count + u.count + 1 > limit, !cur.isEmpty { out.append(cur); cur = "" }
            cur += (cur.isEmpty ? "" : "\n") + u
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    /// One part through the on-device model; dense text (tables, numbers) can overflow the window even at the
    /// chunk limit, so an overflowing part is split in half and retried, down to a few hundred characters.
    private static func mapPart(_ instruction: String, _ part: String) async throws -> [String] {
        do { return [try await onDevice(instruction: instruction, input: part)] }
        catch let e as LanguageModelSession.GenerationError {
            guard case .exceededContextWindowSize = e, part.count > 600 else { throw e }
            var out: [String] = []
            for half in chunks(of: part, limit: max(600, part.count / 2 + 1)) { out += try await mapPart(instruction, half) }
            return out
        }
    }

    static let mergeInstruction = "These are partial results from parts of one document, in order. Combine them into one final answer to the original request, in the same format and as brief as the parts. Keep every distinct fact once. If the request asks for a largest, smallest, earliest, latest, count or total, work it out across all parts and state the single answer."

    /// Map over chunks, then merge summaries, analyses and answers into one result.
    private static func chunked(instruction: String, input: String) async throws -> String {
        var parts: [String] = []
        for c in chunks(of: input) { parts += try await mapPart(instruction, c) }
        if parts.count == 1 { return parts[0] }
        let joined = parts.joined(separator: "\n\n")
        let lower = instruction.lowercased()
        let merge = lower.contains("summar") || lower.contains("analy") || lower.contains("brief") || lower.contains("answer") || lower.contains("explain")
        guard merge else { return joined }
        let merged = joined.count > onDeviceInputLimit ? try await chunked(instruction: mergeInstruction, input: joined) : joined
        return try await onDevice(instruction: mergeInstruction + " Original request: \(instruction)", input: merged)
    }

    static func clean(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<<<") { t = String(t.dropFirst(3)) }
        if t.hasSuffix(">>>") { t = String(t.dropLast(3)) }
        if t.count > 2, t.first == "\"", t.last == "\"" { t = String(t.dropFirst().dropLast()) }
        // Small models sprinkle Markdown; the palette shows plain text.
        t = t.replacingOccurrences(of: #"(?m)^#{1,6}\s*"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\*\*(.+?)\*\*"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^\s*[-*]\s+"#, with: "• ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(?m)^[ \t]*```[^\n]*\n?"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Clipboard

    static func clipboardText() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Tools for the planner

    static let tools: [HostTool] = [
        HostTool(name: "rewriteText", description: "Rewrite text per an instruction (tone, length, clarity, grammar). Returns only the rewritten text.",
                 schema: HostTool.schema([("text", "string", "The text"), ("instruction", "string", "e.g. 'make it professional', 'fix grammar', 'shorten to 3 sentences'")], required: ["text", "instruction"]),
                 readOnly: true, destructive: false) { a in try await generate(instruction: HostTools.string(a, "instruction"), input: HostTools.string(a, "text")) },
        HostTool(name: "summarizeText", description: "Summarize text. Optional length: 'one line', 'short', 'detailed', 'bullets'.",
                 schema: HostTool.schema([("text", "string", "The text"), ("length", "string", "one line | short | detailed | bullets")], required: ["text"]),
                 readOnly: true, destructive: false) { a in try await generate(instruction: WritingIntent.summaryInstruction(HostTools.string(a, "length")), input: HostTools.string(a, "text")) },
        HostTool(name: "translateText", description: "Translate text to a language, keeping formatting.",
                 schema: HostTool.schema([("text", "string", "The text"), ("language", "string", "Target language, e.g. Hindi, Spanish")], required: ["text", "language"]),
                 readOnly: true, destructive: false) { a in try await generate(instruction: "Translate into \(HostTools.string(a, "language")). Output only the translation.", input: HostTools.string(a, "text")) },
        HostTool(name: "explainText", description: "Explain text, code or an error message in plain language, with the likely fix if it is an error.",
                 schema: HostTool.schema([("text", "string", "The text, code or error")], required: ["text"]),
                 readOnly: true, destructive: false) { a in try await generate(instruction: WritingIntent.explainInstruction, input: HostTools.string(a, "text")) },
    ]
}
