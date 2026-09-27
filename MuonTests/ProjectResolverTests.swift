import Foundation
import Testing
@testable import Muon

@Suite struct ProjectResolverTests {
    let projects = ProjectResolver.parse("""
    ~/Work/portfolio\treact-native
    ~/Projects/weather-app\treact-native
    ~/Projects/weather-app-v2\tnode
    ~/Projects/HealthApp\txcode
    ~/Projects/BudgetTracker\tnode
    junk line
    """)

    @Test func parsesLinesWithTypes() {
        #expect(projects.count == 5)
        #expect(projects[0].name == "portfolio")
        #expect(projects[0].path.hasSuffix("/Work/portfolio"))
        #expect(projects[3].type == "xcode")
    }

    @Test func scoringOrder() {
        #expect(ProjectResolver.score(term: "weather-app", name: "weather-app") == 100)
        #expect(ProjectResolver.score(term: "weath", name: "weather-app") == 80)
        #expect(ProjectResolver.score(term: "health", name: "HealthApp") == 80)
        #expect(ProjectResolver.score(term: "tracker", name: "BudgetTracker") == 60)
        #expect(ProjectResolver.score(term: "bgt", name: "BudgetTracker") == 40)
        #expect(ProjectResolver.score(term: "zzz", name: "portfolio") == 0)
    }

    @Test func resolveRanksExactAboveVariants() {
        let r = ProjectResolver(projects: projects)
        let hits = r.resolve("weather-app")
        #expect(hits.map(\.name) == ["weather-app", "weather-app-v2"])
        #expect(r.resolve("nothing here").isEmpty)
    }

    @Test func learnedAliasWinsAndFrecencyBoosts() throws {
        let m = try Memory(path: NSTemporaryDirectory() + "resolver-\(UUID().uuidString).db")
        let r = ProjectResolver(projects: projects)
        m.learnAlias("my site", path: projects[0].path)
        #expect(r.resolve("my site", memory: m).first?.name == "portfolio")
        for _ in 0..<3 { m.bump(kind: "path", name: projects[2].path) }
        #expect(r.resolve("weather-app", memory: m).first?.name == "weather-app")  // exact (100) still beats boosted variant (80+20)
        #expect(r.resolve("weath", memory: m).first?.name == "weather-app-v2")  // both prefix (80); frecency boost decides
    }
}
