import Foundation
import Testing
@testable import Muon

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
