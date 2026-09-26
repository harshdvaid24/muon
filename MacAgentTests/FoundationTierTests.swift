import Foundation
import Testing
@testable import MacAgent

@Suite struct FoundationTierTests {
    let ctx = RoutingContext(aliases: ["kathak → ~/Work/kathak"], apps: ["Xcode", "Visual Studio Code"], projects: ["kathak", "thandaai", "VaidyaApp", "MacAgent"])

    func route(_ q: String) async throws -> Command? {
        guard FoundationTier.isAvailable else { return nil }
        return try await FoundationTier.route(q, context: ctx)
    }

    @Test func openApp() async throws {
        guard let c = try await route("open xcode") else { return }
        #expect(c.tool == .openApplication)
        #expect(c.app.lowercased().contains("xcode"))
    }

    @Test func openProjectInEditor() async throws {
        guard let c = try await route("open kathak in vs code") else { return }
        #expect([.openProject, .openPath].contains(c.tool))
        #expect(c.target.lowercased().contains("kathak"))
    }

    @Test func searchByTopic() async throws {
        guard let c = try await route("find pdfs about invoices") else { return }
        #expect([.searchFiles, .findFiles].contains(c.tool))
    }

    @Test func memoryQuestion() async throws {
        guard let c = try await route("which apps are using the most memory") else { return }
        #expect([.listRunningApps, .getSystemStats].contains(c.tool))
    }

    @Test func quitApp() async throws {
        guard let c = try await route("quit spotify") else { return }
        #expect(c.tool == .quitApplication)
        #expect(c.app.lowercased().contains("spotify"))
    }

    @Test func multiStepIsComplex() async throws {
        guard let c = try await route("move screenshots older than 30 days into an archive folder") else { return }
        #expect([.complex, .moveItems].contains(c.tool))
    }

    @Test func gibberishIsUnknownOrLowConfidence() async throws {
        guard let c = try await route("  ???  ") else { return }
        #expect(c.tool == .unknown || c.confidence < 0.6)
    }
}
