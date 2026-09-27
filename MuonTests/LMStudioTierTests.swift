import Foundation
import Testing
@testable import Muon

@Suite(.serialized) struct LMStudioTierTests {
    @Test func unreachableServerFailsFastWithActionableMessage() async {
        let d = UserDefaults.standard
        let oldURL = d.string(forKey: Settings.Key.lmBaseURL), oldLms = d.string(forKey: Settings.Key.lmsPath)
        d.set("http://127.0.0.1:1", forKey: Settings.Key.lmBaseURL)
        d.set("/usr/bin/false", forKey: Settings.Key.lmsPath)
        defer {
            oldURL.map { d.set($0, forKey: Settings.Key.lmBaseURL) } ?? d.removeObject(forKey: Settings.Key.lmBaseURL)
            oldLms.map { d.set($0, forKey: Settings.Key.lmsPath) } ?? d.removeObject(forKey: Settings.Key.lmsPath)
        }
        let started = Date()
        do {
            _ = try await LMStudioTier.run(query: "x", model: "m", tools: [], context: "", status: { _ in }) { _, _ in "" }
            Issue.record("expected unreachable error")
        } catch {
            #expect(error.localizedDescription.contains("lms server start"))
        }
        #expect(Date().timeIntervalSince(started) < 10)
    }
}
