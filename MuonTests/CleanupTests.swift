import Foundation
import Testing
@testable import Muon

@Suite struct CleanupTests {
    @Test func moveWithTwoPaths() {
        let c = CleanupIntent.parse("move the screenshots in ~/Downloads into ~/Downloads/Archive")
        #expect(c == CleanupIntent(verb: .move, kind: "screenshots", nameContains: nil, olderThanDays: nil, source: "~/Downloads", destination: "~/Downloads/Archive"))
    }

    @Test func trashWithFolderWordAndAge() {
        let c = CleanupIntent.parse("trash zips in downloads older than 3 weeks")
        #expect(c?.verb == .trash)
        #expect(c?.kind == "zips")
        #expect(c?.olderThanDays == 21)
        #expect(c?.source == "downloads")
        #expect(c?.destination == nil)
    }

    @Test func archiveUsesArchiveSubfolder() {
        let c = CleanupIntent.parse("archive the pdfs on my desktop")
        #expect(c?.kind == "pdfs")
        #expect(c?.source == "desktop")
        #expect(c?.destination == CleanupIntent.archiveMarker)
    }

    @Test func kindIsNotReadFromInsidePaths() {
        // "~/Documents" must not make the kind "documents"
        let c = CleanupIntent.parse("move videos in ~/Documents/Clips to ~/Movies/Old")
        #expect(c?.kind == "videos")
        #expect(c?.source == "~/Documents/Clips")
    }

    @Test func notACleanupRequest() {
        #expect(CleanupIntent.parse("open safari") == nil)
        #expect(CleanupIntent.parse("move on") == nil)                       // no kind, no folder
        #expect(CleanupIntent.parse("move the screenshots in ~/Downloads") == nil) // move needs a destination
    }
}
