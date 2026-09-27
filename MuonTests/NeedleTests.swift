import Foundation
import Testing
@testable import Muon

@Suite struct NeedleTests {
    @Test func parsesServerReply() {
        let data = Data(#"{"calls":[{"name":"openApplication","arguments":{"name":"Xcode"}}],"confidence":0.94,"reasoning":"x","ms":48,"engine":"Needle 3"}"#.utf8)
        let c = Needle.parse(data)
        #expect(c == Needle.Call(tool: "openApplication", args: ["name": "Xcode"], confidence: 0.94, ms: 48, reasoning: "x"))
        #expect(Needle.parse(Data(#"{"calls":[],"confidence":0.1}"#.utf8)) == nil)
    }

    @Test func neverRoutesDestructiveToolsAndIsOffByDefault() {
        for t in ["moveItems", "trashItems", "renameItem", "writeTextFile", "runCodingAgent", "openTerminal", "runMenuCommand", "triggerWorkflow"] {
            #expect(!Needle.routable.contains(t), Comment(rawValue: t))
        }
        #expect(Needle.routable.contains("getSystemStats"))
        #expect(Needle.threshold >= 0.9)
    }
}
