import Foundation
import Testing
@testable import Muon

@Suite struct AgentTests {
    struct Deny: Approver { func approve(_ a: PendingAction) async -> ApprovalDecision { .cancel } }

    @Test func gibberishNeverRunsATool() async {
        let out = await Agent.shared.run("  ???  ", approver: Deny()) { _ in }
        #expect(out.results.isEmpty)
        #expect(out.suggestions.isEmpty)
        #expect(out.answer == Agent.notUnderstood)
        #expect(out.tier == 0)
    }

    @Test func complexMarkersAreWordBounded() {
        let lower = " discount code for why-not "
        #expect(!Agent.complexMarkers.contains { lower.contains($0) })
        #expect(Agent.complexMarkers.contains { " how many pdfs ".contains($0) })
    }
}

@Suite struct GreetingTests {
    struct Deny: Approver { func approve(_ a: PendingAction) async -> ApprovalDecision { .cancel } }

    @Test func greetingSetCoversCommonHellos() {
        for g in ["hi", "Hello", "hey there", "thanks", "who are you"] {
            #expect(Agent.greetings.contains(Memory.normalize(g)), "\(g) should be a greeting")
        }
        #expect(!Agent.greetings.contains(Memory.normalize("open xcode")))
    }

    @Test func greetingNeverRunsATool() async {
        let out = await Agent.shared.run("hi", approver: Deny()) { _ in }
        #expect(out.results.isEmpty)
        #expect(out.suggestions.isEmpty)
        // On-device model may or may not be available in CI; either a chat answer or nothing, never a tool.
    }
}

@Suite struct ScopeAndRoutingTests {
    @Test func explicitPathInQueryWins() async {
        let s = await Agent.shared.resolveScope("weather-app", query: "search code for TODO in ~/Documents/MuonDemo please")
        #expect(s == NSHomeDirectory() + "/Documents/MuonDemo")
    }

    @Test func folderWordsMapToHomeFolders() async {
        #expect(await Agent.shared.resolveScope("Downloads", query: "biggest files in downloads") == NSHomeDirectory() + "/Downloads")
        #expect(await Agent.shared.resolveScope("my desktop", query: "x") == NSHomeDirectory() + "/Desktop")
        #expect(await Agent.shared.resolveScope("", query: "no scope here") == nil)
    }

    @Test func devRequestsEscalateToPlanner() {
        for q in ["In my-app, fix the login crash and run it on iPhone 17", "run the app on pixel 9", "trigger the release workflow in my-app"] {
            let lower = " " + q.lowercased() + " "
            #expect(Agent.complexMarkers.contains { lower.contains($0) }, "\(q) should go to tier 2")
        }
        for simple in [" find duplicate files in downloads ", " which simulators do i have "] {
            #expect(!Agent.complexMarkers.contains { simple.contains($0) }, "\(simple) has its own tool")
        }
    }
}
