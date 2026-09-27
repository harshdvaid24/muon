import Foundation
import Testing
@testable import MacAgent

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
        for g in ["hi", "Hello", "hey there", "thanks", "what can you do"] {
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
