import Foundation
import Testing
@testable import Muon

@Suite struct ProjectResolverTests {
    let projects = ProjectResolver.parse("""
    ~/Work/kathak\treact-native
    ~/Projects/thandaai\treact-native
    ~/Projects/thandaai-1\tnode
    ~/Projects/VaidyaApp\txcode
    ~/Projects/MoneyAiTracker\tnode
    junk line
    """)

    @Test func parsesLinesWithTypes() {
        #expect(projects.count == 5)
        #expect(projects[0].name == "kathak")
        #expect(projects[0].path.hasSuffix("/Work/kathak"))
        #expect(projects[3].type == "xcode")
    }

    @Test func scoringOrder() {
        #expect(ProjectResolver.score(term: "thandaai", name: "thandaai") == 100)
        #expect(ProjectResolver.score(term: "thand", name: "thandaai") == 80)
        #expect(ProjectResolver.score(term: "vaidya", name: "VaidyaApp") == 80)
        #expect(ProjectResolver.score(term: "tracker", name: "MoneyAiTracker") == 60)
        #expect(ProjectResolver.score(term: "mat", name: "MoneyAiTracker") == 40)
        #expect(ProjectResolver.score(term: "zzz", name: "kathak") == 0)
    }

    @Test func resolveRanksExactAboveVariants() {
        let r = ProjectResolver(projects: projects)
        let hits = r.resolve("thandaai")
        #expect(hits.map(\.name) == ["thandaai", "thandaai-1"])
        #expect(r.resolve("nothing here").isEmpty)
    }

    @Test func learnedAliasWinsAndFrecencyBoosts() throws {
        let m = try Memory(path: NSTemporaryDirectory() + "resolver-\(UUID().uuidString).db")
        let r = ProjectResolver(projects: projects)
        m.learnAlias("dance app", path: projects[0].path)
        #expect(r.resolve("dance app", memory: m).first?.name == "kathak")
        for _ in 0..<3 { m.bump(kind: "path", name: projects[2].path) }
        #expect(r.resolve("thandaai", memory: m).first?.name == "thandaai")  // exact (100) still beats boosted variant (80+20)
        #expect(r.resolve("thanda", memory: m).first?.name == "thandaai-1")  // both prefix (80); frecency boost decides
    }
}
