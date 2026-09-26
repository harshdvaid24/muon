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
