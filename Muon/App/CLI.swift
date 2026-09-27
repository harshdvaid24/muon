import AppKit
import Foundation

/// Headless mode for scripts and tests: `Muon --query "open xcode" [--yes]`.
enum CLI {
    static var active = false

    struct YesApprover: Approver {
        let yes: Bool
        func approve(_ a: PendingAction) async -> ApprovalDecision {
            print("confirm: \(a.title)\n\(a.detail)\n→ \(yes ? "allowed (--yes)" : "cancelled (pass --yes to allow)")")
            return yes ? .allow : .cancel
        }
    }

    /// Returns true when the process should run headless; the caller still starts the run loop.
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--suggest") {
            active = true
            Task {
                let rows = await Proactive.refresh(memory: Agent.shared.memory)
                for r in rows { print("• \(r.title) — \(r.subtitle)  [\(r.action.kind) \(r.action.value)]") }
                if rows.isEmpty { print("nothing to suggest right now") }
                MCPClient.shared.stop(); exit(0)
            }
            return true
        }
        if args.contains("--diagnose") {
            active = true
            Task {
                let lm = await LMStudioTier.isReachable()
                let rows: [(String, String)] = [
                    ("Muon", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"),
                    ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
                    ("Apple Intelligence", FoundationTier.isAvailable ? "available" : (FoundationTier.unavailableReason ?? "unavailable")),
                    ("Node", FileManager.default.isExecutableFile(atPath: Settings.nodePath) ? Settings.nodePath : "MISSING — brew install node"),
                    ("Tool server", FileManager.default.fileExists(atPath: Settings.mcpServerPath) ? Settings.mcpServerPath : "MISSING"),
                    ("LM Studio", lm ? "reachable at \(Settings.lmBaseURL)" : "not running (optional)"),
                    ("Shortcut", HotKey.currentCombo.label),
                    ("Allowed folders", Settings.allowedRoots.joined(separator: " ")),
                ]
                for (k, v) in rows { print(k.padding(toLength: 20, withPad: " ", startingAt: 0) + v) }
                exit(0)
            }
            return true
        }
        guard let i = args.firstIndex(of: "--query"), i + 1 < args.count else { return false }
        active = true
        let query = args[i + 1]
        let yes = args.contains("--yes")
        let force = args.firstIndex(of: "--tier").flatMap { args.indices.contains($0 + 1) ? Int(args[$0 + 1]) : nil }
        Task {
            let started = Date()
            let out = await Agent.shared.run(query, approver: YesApprover(yes: yes), status: { print("… \($0)") }, forceTier: force)
            print("tier=\(out.tier) ms=\(Int(Date().timeIntervalSince(started) * 1000))")
            for r in out.results { print("tool=\(r.tool) ok=\(r.ok)\(r.cancelled ? " cancelled" : "") args=\(Agent.json(r.args))") }
            for s in out.suggestions { print("suggest: \(s.title) — \(s.subtitle ?? "") [\(s.tool) \(Agent.json(s.args))]") }
            if let r = out.result { print("result (\(r.label) · \(r.source)):\n\(r.text)") }
            if let a = out.answer { print("answer:\n\(a)") }
            if let n = out.note { print("note: \(n)") }
            MCPClient.shared.stop()
            exit(0)
        }
        return true
    }
}
