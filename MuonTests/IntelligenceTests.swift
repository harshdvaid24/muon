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

@Suite struct DocumentQATests {
    @Test func questionAboutAFile() {
        let w = WritingIntent.parse("what does ~/Documents/lease.pdf say about the deposit")
        #expect(w?.source == .file("~/Documents/lease.pdf"))
        #expect(w?.instruction.contains("the deposit") == true)
        #expect(w?.label == "About the deposit")
        #expect(WritingIntent.parse("ask ~/notes.txt: who is the owner")?.source == .file("~/notes.txt"))
    }
    @Test func markdownStripped() {
        #expect(TextTools.clean("### Fix\n**Run** pod install\n- one\n- two") == "Fix\nRun pod install\n• one\n• two")
    }
    @Test func longParagraphsAreSplitIntoChunks() {
        let table = (0..<400).map { "16 Jun 19  UPI/DR/\($0)  ATM WDL  1,500.00" }.joined(separator: "\n")   // one paragraph, ~16k chars
        let cs = TextTools.chunks(of: table)
        #expect(cs.count >= 3)
        #expect(cs.allSatisfy { $0.count <= TextTools.chunkLimit })
        #expect(cs.joined(separator: "\n") == table)
        #expect(TextTools.chunks(of: "short") == ["short"])
    }

    /// Digit-dense text overflows the on-device window well under the character limit; the parts path must cope.
    @Test(.timeLimit(.minutes(3))) func denseTableIsAnsweredInParts() async throws {
        guard FoundationTier.isAvailable else { return }
        let rows = (0..<220).map { i in "0\(i % 28 + 1) Jun 19  UPI/DR/\(100000 + i * 7)/PAYTM  \(i == 150 ? "67,148.00" : String(format: "%.2f", Double(i * 37 % 1900) + 5))  \(String(format: "%.2f", 120000.0 - Double(i) * 310))" }
        let text = "Account statement\n" + rows.joined(separator: "\n")
        let question = "Using only the text, answer this question briefly and specifically: what is the largest transaction?"
        let facts = try #require(Numbers.facts(question: question, text: text))
        #expect(facts.contains("Largest amount: 67,148.00"), Comment(rawValue: facts))
        let answer = try await TextTools.generate(instruction: question + "\n\n" + facts, input: text)
        #expect(answer.contains("67,148") || answer.contains("67148"), Comment(rawValue: answer))
    }

    @Test func numbersFactsExcludeRunningBalancesForTransactionQuestions() {
        let text = """
        Date  Description  Amount  Balance
        16 Jun 19  ATM WDL  1,500.00  112,953.65
        NEFT CR FROM ACME LTD
        67,148.00  180,101.65
        01 Jul 19  UPI  20,000.00  160,101.65
        05 Jul 19  UPI  300.00  159,801.65
        TOTAL 88,948.00 0.00 159,801.65
        """
        let f = Numbers.facts(question: "find the largest transaction", text: text)!
        #expect(f.contains("Largest amount: 67,148.00 — NEFT CR FROM ACME LTD · 67,148.00 180,101.65"), Comment(rawValue: f))
        #expect(f.contains("Next largest amount: 20,000.00 — 01 Jul 19 UPI 20,000.00 160,101.65"), Comment(rawValue: f))   // no stale description
        #expect(!f.contains("Date Description Amount Balance ·"), Comment(rawValue: f))   // headers are not descriptions
        #expect(!f.contains("88,948.00 —"))   // the TOTAL row is not a transaction
        #expect(Numbers.withoutFigures("This is a bank statement for June. The largest transaction was 14,000 INR. It lists purchases and withdrawals.") == "This is a bank statement for June. It lists purchases and withdrawals.")
        let b = Numbers.facts(question: "what was the highest balance", text: text)!
        #expect(b.contains("Largest amount: 180,101.65"))
        let t = Numbers.facts(question: "how much did I spend in total", text: text)!
        #expect(t.contains("Total of 4 amounts (running balances excluded): 88,948.00"))
        #expect(Numbers.facts(question: "summarize this", text: text) == nil)
        #expect(Numbers.facts(question: "largest", text: "no numbers here") == nil)
    }

    @Test func codeFencesStripped() {
        #expect(TextTools.clean("Use `map` here:\n```javascript\nconst a = 1\n```\ndone") == "Use map here:\nconst a = 1\ndone")
    }
}
