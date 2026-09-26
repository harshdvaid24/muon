import Foundation
import Testing
@testable import MacAgent

@Suite struct MemoryTests {
    func fresh() throws -> Memory {
        try Memory(path: NSTemporaryDirectory() + "macagent-test-\(UUID().uuidString).db")
    }

    @Test func normalizeCollapsesCaseWhitespacePunctuation() {
        #expect(Memory.normalize("  Open  KATHAK, please!! ") == "open kathak please")
        #expect(Memory.normalize("???") == "")
    }

    @Test func intentCacheRoundTripAndInvalidate() throws {
        let m = try fresh()
        m.cacheStore("Open Kathak", tool: "openPath", argsJSON: #"{"path":"~/Work/kathak"}"#)
        let hit = m.cacheLookup("open kathak")
        #expect(hit?.tool == "openPath")
        #expect(hit?.argsJSON.contains("kathak") == true)
        m.cacheInvalidate("OPEN KATHAK")
        #expect(m.cacheLookup("open kathak") == nil)
    }

    @Test func aliasLearnAndRecall() throws {
        let m = try fresh()
        #expect(m.alias("kathak") == nil)
        m.learnAlias("kathak", path: "/Users/x/Work/kathak")
        m.learnAlias("Kathak", path: "/Users/x/Work/kathak")
        #expect(m.alias("kathak") == "/Users/x/Work/kathak")
        #expect(m.topAliases(5).first?.term == "kathak")
    }

    @Test func evictionKeepsHighestFrecency() throws {
        let m = try fresh()
        m.rowLimit = 5
        for i in 0..<5 { m.learnAlias("t\(i)", path: "/p\(i)") }
        for _ in 0..<10 { m.learnAlias("t0", path: "/p0") }
        m.learnAlias("t5", path: "/p5") // 6th distinct → evicts lowest
        #expect(m.topAliases(10).count == 5)
        #expect(m.alias("t0") == "/p0")
        #expect(m.alias("t5") == "/p5")
    }

    @Test func pruneRemovesStaleRows() throws {
        let m = try fresh()
        m.now = { Date(timeIntervalSinceNow: -100 * 86400) }
        m.learnAlias("old", path: "/o")
        m.cacheStore("old query", tool: "x", argsJSON: "{}")
        m.now = { Date() }
        m.learnAlias("new", path: "/n")
        m.prune()
        #expect(m.alias("old") == nil)
        #expect(m.cacheLookup("old query") == nil)
        #expect(m.alias("new") == "/n")
    }

    @Test func usageFrecencyOrdersTop() throws {
        let m = try fresh()
        for _ in 0..<3 { m.bump(kind: "app", name: "Xcode") }
        m.bump(kind: "app", name: "Safari")
        m.bump(kind: "path", name: "/x")
        #expect(m.top(kind: "app", n: 5) == ["Xcode", "Safari"])
    }

    @Test func sequencesCountAndMacrosPersist() throws {
        let m = try fresh()
        #expect(m.noteSequence("a|b") == 1)
        #expect(m.noteSequence("a|b") == 2)
        #expect(m.noteSequence("a|b") == 3)
        m.saveMacro(name: "morning", stepsJSON: #"[{"tool":"openApplication","args":{"name":"Xcode"}}]"#)
        #expect(m.macros().map(\.name) == ["morning"])
        #expect(m.macro(named: "Morning")?.stepsJSON.contains("Xcode") == true)
    }
}
