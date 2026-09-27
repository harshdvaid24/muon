import Foundation
import Testing
@testable import Muon

@Suite struct HelpTests {
    struct Deny: Approver { func approve(_ a: PendingAction) async -> ApprovalDecision { .cancel } }

    @Test func helpPhrasesMatch() {
        for q in ["help", "What can you do?", "what all can you do", "show me the commands", "list commands", "how do I use this", "what can I ask you", "commands"] {
            #expect(Help.matches(q), Comment(rawValue: q))
        }
        for q in ["help me move the pdfs", "open xcode", "what is the capital of japan", "commands in vscode", "what can you do about my downloads"] {
            #expect(!Help.matches(q), Comment(rawValue: q))
        }
    }

    @Test func catalogCoversEveryGroup() {
        let t = Help.text
        for needle in ["fix grammar", "summarize", "receipts", "crash", "iPhone 17", "every monday", "⌘⇧M", "⌘O", "undo", "screenshot"] {
            #expect(t.localizedCaseInsensitiveContains(needle), Comment(rawValue: needle))
        }
    }

    @Test func agentAnswersHelpWithoutAModel() async {
        let out = await Agent.shared.run("what can you do", approver: Deny()) { _ in }
        #expect(out.tier == 0)
        #expect(out.result?.label == "What Muon can do")
        #expect(out.results.isEmpty)
    }
}

@Suite struct AttachmentTests {
    @Test func composesByKind() throws {
        let dir = NSTemporaryDirectory() + "muon-attach-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let img = dir + "/shot one.png", doc = dir + "/lease.pdf", aud = dir + "/call.m4a"
        for p in [img, doc, aud] { FileManager.default.createFile(atPath: p, contents: Data()) }
        #expect(Attachment.compose(query: "", path: img) == "describe \"\(img)\"")
        #expect(Attachment.compose(query: "explain this", path: img) == "explain this \"\(img)\"")
        #expect(Attachment.compose(query: "which app is this", path: img) == "describe \"\(img)\": which app is this")
        #expect(Attachment.compose(query: "", path: doc) == "summarize \"\(doc)\"")
        #expect(Attachment.compose(query: "fix grammar", path: doc) == "fix grammar \"\(doc)\"")
        #expect(Attachment.compose(query: "who is the tenant", path: doc) == "ask \"\(doc)\": who is the tenant")
        #expect(Attachment.compose(query: "", path: aud) == "transcribe \"\(aud)\"")
        #expect(Attachment.compose(query: "what did they decide", path: aud) == "meeting notes from \"\(aud)\"")
        #expect(Attachment.compose(query: "total the receipts", path: dir) == "total the receipts \"\(dir)\"")
        #expect(Attachment.compose(query: "", path: dir) == "what is inside \"\(dir)\"")
    }

    @Test func composedRequestsParseWithSpacesInPaths() {
        let w = WritingIntent.parse("ask \"/tmp/my docs/lease agreement.pdf\": who is the tenant")
        #expect(w?.source == .file("/tmp/my docs/lease agreement.pdf"))
        #expect(w?.instruction.contains("who is the tenant") == true)
        let s = WritingIntent.parse("summarize \"/tmp/my docs/lease agreement.pdf\"")
        #expect(s?.source == .file("/tmp/my docs/lease agreement.pdf"))
        #expect(WritingIntent.parse("summarize ~/Documents/lease.pdf.")?.source == .file("~/Documents/lease.pdf"))
        #expect(MediaIntent.parse("explain this \"/tmp/my shots/Screenshot 1.png\"") == .explainScreenshot("/tmp/my shots/Screenshot 1.png"))
    }

    @Test func pastedImagesArePruned() throws {
        let dir = NSTemporaryDirectory() + "muon-paste-\(UUID().uuidString)"
        let saved = Attachment.pastedDir
        Attachment.pastedDir = dir
        defer { Attachment.pastedDir = saved; try? FileManager.default.removeItem(atPath: dir) }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        for i in 0..<25 { #expect(Attachment.save(png: png, now: Date(timeIntervalSince1970: 1_700_000_000 + Double(i))) != nil) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir).count == Attachment.keepPasted)
        #expect(throws: Never.self) { try PathPolicy.resolve(dir + "/" + (try FileManager.default.contentsOfDirectory(atPath: dir).sorted().last!)) }
    }
}

@Suite struct VoiceTests {
    @Test func liveTranscriptionWorksOnAFile() async throws {
        let path = NSHomeDirectory() + "/Documents/MuonDemo/Inbox/standup.aiff"
        guard FileManager.default.fileExists(atPath: path) else { return }
        let text = try await LiveTranscription.transcribe(file: path)
        #expect(text.lowercased().contains("stand"), Comment(rawValue: text))
    }
}
