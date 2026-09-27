import Foundation
import Testing
@testable import Muon

@Suite struct AgentLaunchTests {
    @Test func parsesStartPhrases() {
        #expect(AgentLaunch.parse("start agent for kathak app") == AgentLaunch(project: "kathak", command: "claude"))
        #expect(AgentLaunch.parse("start claude code agent for kathak project") == AgentLaunch(project: "kathak", command: "claude"))
        #expect(AgentLaunch.parse("Start Claude Code for kathak") == AgentLaunch(project: "kathak", command: "claude"))
        #expect(AgentLaunch.parse("open codex in weather-app") == AgentLaunch(project: "weather-app", command: "codex"))
        #expect(AgentLaunch.parse("claude for weather-app") == AgentLaunch(project: "weather-app", command: "claude"))
        #expect(AgentLaunch.parse("start a terminal in kathak") == AgentLaunch(project: "kathak", command: ""))
    }

    @Test func leavesOtherRequestsAlone() {
        for q in ["open kathak in vscode", "in safari open a new private window", "start the build for kathak", "run weather-app on iphone 17", "what can you do"] {
            #expect(AgentLaunch.parse(q) == nil, Comment(rawValue: q))
        }
    }

    @Test func confirmCardNamesTheAssistantAndProject() {
        let (title, detail) = Permission.describe(tool: "openTerminal", args: ["project": NSHomeDirectory() + "/Work/kathak", "command": "claude", "app": "terminal"])
        #expect(title == "Start Claude Code for kathak")
        #expect(detail.contains("~/Work/kathak") && detail.contains("Terminal window") && detail.contains("claude"), Comment(rawValue: detail))
        #expect(Permission.risk(named: "openTerminal") == .confirm)
    }
}
