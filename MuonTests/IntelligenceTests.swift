import Foundation
import Testing
@testable import Muon

@Suite struct WritingIntentTests {
    @Test func grammarFixFromClipboard() {
        let w = WritingIntent.parse("fix grammar")
        #expect(w?.source == .clipboard)
        #expect(w?.instruction.contains("grammar") == true)
    }
    @Test func toneRewrite() {
        #expect(WritingIntent.parse("make this professional")?.label == "Professional version")
        #expect(WritingIntent.parse("rewrite it in a friendly tone")?.instruction.contains("friendly") == true)
    }
    @Test func translateWithInlineText() {
        let w = WritingIntent.parse("translate to hindi: good morning, how are you?")
        #expect(w?.source == .inline("good morning, how are you?"))
        #expect(w?.instruction.contains("Hindi") == true)
    }
    @Test func summarizeFileSource() {
        let w = WritingIntent.parse("summarize ~/Documents/notes.txt as bullets")
        #expect(w?.source == .file("~/Documents/notes.txt"))
        #expect(w?.instruction.contains("bullet") == true)
    }
    @Test func replyAndExtract() {
        #expect(WritingIntent.parse("reply saying I'll be there at 5")?.instruction.contains("I'll be there at 5") == true)
        #expect(WritingIntent.parse("extract the action items")?.label == "Action Items")
    }
    @Test func notWriting() {
        #expect(WritingIntent.parse("open xcode") == nil)
        #expect(WritingIntent.parse("find duplicate files in downloads") == nil)
        #expect(WritingIntent.parse("what is taking space in ~/Downloads") == nil)
    }
}

@Suite struct PathPolicyTests {
    @Test func allowedAndDenied() throws {
        let home = NSHomeDirectory()
        #expect(try PathPolicy.resolve("~/Downloads") == PathPolicy.canonical(home + "/Downloads"))
        #expect(throws: PathPolicy.Failure.self) { try PathPolicy.resolve("~/Library/Preferences") }
        #expect(throws: PathPolicy.Failure.self) { try PathPolicy.resolve("~/Downloads/../.ssh/id_ed25519", mustExist: false) }
        #expect(throws: PathPolicy.Failure.self) { try PathPolicy.resolve("/etc/hosts") }
        #expect(throws: PathPolicy.Failure.self) { try PathPolicy.resolve("~/Movies") }
    }
    @Test func newPathResolvesThroughParent() throws {
        let p = try PathPolicy.resolve("~/Downloads/muon-new-file.txt", mustExist: false)
        #expect(p.hasSuffix("/Downloads/muon-new-file.txt"))
    }
    @Test func firstPathToken() {
        #expect(PathPolicy.firstPath(in: "summarize ~/Documents/a b.pdf now") == "~/Documents/a")
        #expect(PathPolicy.firstPath(in: "no paths here") == nil)
    }
}

@Suite(.enabled(if: FoundationTier.isAvailable, "on-device model unavailable")) struct TextToolsLiveTests {
    @Test func fixesGrammarOnDevice() async throws {
        let out = try await TextTools.generate(instruction: "Fix grammar, spelling and punctuation. Change nothing else.", input: "i has went to the store yesterday and buyed three apple")
        let low = out.lowercased()
        #expect(low.contains("went") || low.contains("gone"))
        #expect(low.contains("bought"))
        #expect(!low.contains("<<<"))
    }
    @Test func translatesInline() async throws {
        let out = try await TextTools.generate(instruction: "Translate into Spanish. Output only the translation.", input: "Good morning")
        #expect(out.lowercased().contains("buen"))
    }
}
