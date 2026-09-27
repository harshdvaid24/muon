import Foundation
import Testing
@testable import Muon

@Suite struct FileRefTests {
    private func workspace() throws -> String {
        let dir = NSTemporaryDirectory() + "muon-fileref-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/deeper/inside", withIntermediateDirectories: true)
        for n in ["sample statement.pdf", "Report Q3.docx", "deeper/inside/notes.md"] { FileManager.default.createFile(atPath: dir + "/" + n, contents: Data()) }
        return dir
    }

    @Test func bareNameWithFolderWordResolvesAndRewrites() throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(atPath: dir) }
        let m = FileRef.rewrite("check sample statement.pdf from downloads, analyse it and give me brief", folderWords: ["downloads": dir])
        #expect(m?.path == dir + "/sample statement.pdf")
        #expect(m?.rewritten == "check \"\(dir)/sample statement.pdf\", analyse it and give me brief")
    }

    @Test func caseInsensitiveDeepAndUnnamedFolder() throws {
        let dir = try workspace(); defer { try? FileManager.default.removeItem(atPath: dir) }
        #expect(FileRef.rewrite("summarize report q3.DOCX", folders: [dir])?.path == dir + "/Report Q3.docx")
        #expect(FileRef.rewrite("what is in notes.md", folders: [dir])?.path == dir + "/deeper/inside/notes.md")
        #expect(FileRef.rewrite("summarize missing.pdf in downloads", folderWords: ["downloads": dir]) == nil)
        #expect(FileRef.rewrite("summarize ~/Documents/lease.pdf", folders: [dir]) == nil)   // explicit paths are left alone
        #expect(FileRef.rewrite("open xcode", folders: [dir]) == nil)
    }

    @Test func analysisVerbsAndOpenVerbs() {
        #expect(FileRef.wantsAnalysis("check x.pdf from downloads, analyse it and give me brief"))
        #expect(FileRef.wantsAnalysis("what is in x.pdf"))
        #expect(!FileRef.wantsAnalysis("open x.pdf from downloads"))
        #expect(!FileRef.wantsAnalysis("reveal x.pdf in finder"))
    }

    @Test func writingRulesCoverAnalysisAndBrief() {
        #expect(WritingIntent.parse("analyse this")?.label == "Analysis")
        #expect(WritingIntent.parse("review this document and give me a brief")?.label == "Analysis")
        #expect(WritingIntent.parse("give me a brief")?.label == "Brief")
        #expect(WritingIntent.parse("quick summary of this")?.label == "Brief")
        #expect(WritingIntent.parse("analyse \"/tmp/a b/x.pdf\"")?.source == .file("/tmp/a b/x.pdf"))
    }
}
