import Foundation
import Testing
@testable import Muon

@Suite struct PermissionTests {
    @Test func unknownToolNeverAuto() {
        #expect(Permission.risk(named: "doesNotExist") == .confirm)
    }

    @Test func alwaysKeyRequiresOneSharedFolder() {
        let same = Permission.alwaysKey(tool: "trashItems", args: ["paths": ["~/Downloads/a.zip", "~/Downloads/b.zip"]])
        #expect(same == "trashItems|\(NSHomeDirectory())/Downloads")
        let mixed = Permission.alwaysKey(tool: "trashItems", args: ["paths": ["~/Downloads/a.zip", "~/Documents/b.zip"]])
        #expect(mixed == nil)
        let single = Permission.alwaysKey(tool: "renameItem", args: ["path": "~/Work/x/file.txt", "newName": "y"])
        #expect(single == "renameItem|\(NSHomeDirectory())/Work/x")
        #expect(Permission.alwaysKey(tool: "quitApplication", args: ["name": "Safari"]) == nil)
    }

    @Test func describeSummarizesBatches() {
        let d = Permission.describe(tool: "trashItems", args: ["paths": ["~/Downloads/a.zip", "~/Downloads/b.zip"]])
        #expect(d.title == "Move 2 items to Trash")
        #expect(d.detail.contains("~/Downloads/a.zip"))
    }
}
