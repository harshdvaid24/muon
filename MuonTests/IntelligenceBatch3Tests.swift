import Foundation
import Testing
@testable import Muon

@Suite struct LocalizationTests {
    @Test func parsesAndRendersJSON() throws {
        let src = #"{"greeting":"Hello {name}","menu":{"save":"Save","cancel":"Cancel"},"count":3}"#
        let ents = try Localization.entries(src, format: .json)
        #expect(ents.map(\.key) == ["greeting", "menu.cancel", "menu.save"])
        let out = try Localization.render(src, format: .json, translations: ["greeting": "नमस्ते {name}", "menu.save": "सहेजें"])
        #expect(out.contains("\"greeting\" : \"नमस्ते {name}\"")); #expect(out.contains("\"save\" : \"सहेजें\"")); #expect(out.contains("\"cancel\" : \"Cancel\"")); #expect(out.contains("\"count\" : 3"))
    }
    @Test func parsesAndRendersStrings() throws {
        let src = "/* header */\n\"ok\" = \"OK\";\n\"hello_user\" = \"Hello, %@!\";\n"
        let ents = try Localization.entries(src, format: .strings)
        #expect(ents.count == 2)
        let out = try Localization.render(src, format: .strings, translations: ["hello_user": "नमस्ते, %@!"])
        #expect(out.contains("\"hello_user\" = \"नमस्ते, %@!\";")); #expect(out.contains("\"ok\" = \"OK\";")); #expect(out.hasPrefix("/* header */"))
    }
    @Test func arbSkipsMetadata() throws {
        let ents = try Localization.entries(#"{"@@locale":"en","title":"Home","@title":{"description":"x"}}"#, format: .arb)
        #expect(ents.map(\.key) == ["title"])
    }
    @Test func outputPaths() {
        #expect(Localization.outputPath(source: "/p/locales/en.json", code: "hi") == "/p/locales/hi.json")
        #expect(Localization.outputPath(source: "/p/en.lproj/Localizable.strings", code: "gu") == "/p/gu.lproj/Localizable.strings")
        #expect(Localization.outputPath(source: "/p/l10n/app_en.arb", code: "ta") == "/p/l10n/app_ta.arb")
        #expect(Localization.outputPath(source: "/p/strings.json", code: "hi") == "/p/strings.hi.json")
    }
    @Test func batchTranslateKeepsKeysAndPlaceholders() async throws {
        let ents = [Localization.Entry(key: "a", value: "Hello {name}"), Localization.Entry(key: "b", value: "Bye")]
        let tr = try await Localization.translate(ents, to: "Pig Latin") { prompt in
            // fake translator: echoes numbered lines with a suffix, proving numbering round-trips
            prompt.split(separator: "\n").filter { $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil }.map { "\($0)-x" }.joined(separator: "\n")
        }
        #expect(tr == ["a": "Hello {name}-x", "b": "Bye-x"])
    }
    @Test func intent() {
        #expect(Localization.parseIntent("translate ~/app/en.json to hindi and gujarati") == Localization.Intent(path: "~/app/en.json", languages: ["gujarati", "hindi"]))
        #expect(Localization.parseIntent("translate ~/notes.txt to hindi") == nil)      // not a localization file → writing tool
        #expect(Localization.parseIntent("open ~/app/en.json") == nil)
    }
}

@Suite struct ReceiptTests {
    @Test func fallbackTotalPrefersTotalLine() {
        let t = "ACME STORE\nMilk 2.50\nBread 3.00\nTOTAL 5.50\nPaid card 5.50\nThank you 2026"
        #expect(Receipts.fallbackTotal(t) == 5.5)
        #expect(Receipts.fallbackTotal("Subtotal 1,250.00\nGrand Total 1,475.00 INR") == 1475)
    }
    @Test func receiptsIntent() {
        #expect(MediaIntent.parse("total the receipts in ~/Documents/Receipts") == .receipts("~/Documents/Receipts"))
        #expect(MediaIntent.parse("add up receipts in ~/Downloads/Bills") == .receipts("~/Downloads/Bills"))
    }
}

@Suite struct TranscriptionTests {
    @Test func intents() {
        #expect(MediaIntent.parse("transcribe ~/Downloads/call.m4a") == .transcribe("~/Downloads/call.m4a"))
        #expect(MediaIntent.parse("meeting notes from ~/Downloads/standup.mp4") == .meetingNotes("~/Downloads/standup.mp4"))
    }
    @Test(.timeLimit(.minutes(6))) func transcribesSpokenClip() async throws {
        let dir = NSHomeDirectory() + "/Work/Muon/.sandbox/speech"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let clip = dir + "/clip.aiff"
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = ["-o", clip, "the quick brown fox jumps over the lazy dog"]
        try p.run(); p.waitUntilExit()
        let text = try await Transcriber.transcribe(clip) { _ in }
        let low = text.lowercased()
        #expect(low.contains("quick")); #expect(low.contains("fox")); #expect(low.contains("lazy"))
    }
}
