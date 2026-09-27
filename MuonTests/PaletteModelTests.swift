import Foundation
import Testing
@testable import Muon

@MainActor @Suite struct PaletteModelTests {
    final class Box { var value = "" }

    private func model() -> PaletteModel {
        let m = PaletteModel()
        m.history = ["open xcode", "fix grammar", "what is inside ~/Downloads"]
        return m
    }

    @Test func arrowsCycleRecentRequestsThroughTheDraft() {
        let m = model()
        m.query = "dra"
        m.moveSelection(1); #expect(m.query == "open xcode")
        m.moveSelection(1); #expect(m.query == "fix grammar")
        m.moveSelection(-1); #expect(m.query == "open xcode")
        m.moveSelection(-1); #expect(m.query == "dra")                          // back to what was typed
        m.moveSelection(-1); #expect(m.query == "what is inside ~/Downloads")   // wraps to the oldest
    }

    @Test func editedRecallBecomesTheDraft() {
        let m = model()
        m.moveSelection(1)
        m.query = "open xcode now"
        m.moveSelection(1); #expect(m.query == "open xcode")
        m.moveSelection(-1); #expect(m.query == "open xcode now")
    }

    @Test func idleRowsAreNavigableReturnRunsAndTabEdits() {
        let m = model()
        let ran = Box()
        m.idleRows = [.init(icon: "a", title: "one", subtitle: nil, section: "For you") { ran.value += "one" },
                      .init(icon: "b", title: "two", subtitle: nil, section: "Recent", fill: "two") { ran.value += "two" }]
        #expect(m.showsIdle)
        m.moveSelection(1); #expect(m.selection == 1)
        m.moveSelection(1); #expect(m.selection == 0)                          // wraps
        m.moveSelection(-1)
        m.handleReturn(); #expect(ran.value == "two")
        #expect(m.editSelection()); #expect(m.query == "two"); #expect(!m.showsIdle)
        #expect(!m.editSelection())
    }

    @Test func attachmentIsComposedIntoTheRequest() async {
        let m = PaletteModel()
        let got = Box()
        m.handler = { got.value = $0 }
        m.attachment = "/tmp/x.png"
        m.query = "explain this"
        m.submit()
        for _ in 0..<100 where got.value.isEmpty { try? await Task.sleep(for: .milliseconds(20)) }
        #expect(got.value == "explain this \"/tmp/x.png\"")
        #expect(m.attachment == "/tmp/x.png")   // stays for follow-up questions
    }
}
