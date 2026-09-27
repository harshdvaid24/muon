import Foundation

/// Optional fast decision engine (github.com/NandhaKishorM/laya, running locally as `laya-serve`).
/// Typed choice / yes-no answers in ~150 ms with calibrated probabilities, plus language detection.
/// Muon uses it as a pre-router hint and for cheap triage; everything works without it.
enum Laya {
    static var baseURL: String { Settings.d.string(forKey: "layaURL") ?? "http://127.0.0.1:8765" }
    static var enabled: Bool { Settings.d.object(forKey: "layaEnabled") as? Bool ?? true }

    private static var health: (at: Date, ok: Bool)?

    static func isReachable() async -> Bool {
        guard enabled, let url = URL(string: baseURL + "/health") else { return false }
        if let h = health, Date().timeIntervalSince(h.at) < 60 { return h.ok }
        var req = URLRequest(url: url); req.timeoutInterval = 1.5
        let ok = (try? await URLSession.shared.data(for: req)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        health = (Date(), ok)
        return ok
    }

    struct RouteHint { let family: String; let probability: Double; let multistep: Double; let multilingual: Bool }

    static let families: [String: String] = [
        "openApplication": "launch, open or switch to an application", "quitApplication": "quit or close an application",
        "findFiles": "find or locate files or folders by name", "searchCode": "search inside source code for text",
        "largestFiles": "what is taking disk space, biggest files", "findDuplicates": "duplicate files",
        "cleanup": "move, archive, trash or delete files", "systemStats": "memory, disk, cpu, battery status",
        "runOnDevice": "build or run an app on a simulator, emulator or phone", "webSearch": "look something up on the internet",
        "writing": "rewrite, fix grammar, translate, summarize or explain text", "screenshot": "read, explain or describe a screenshot or image",
        "transcribe": "transcribe audio or video, meeting notes", "chat": "greeting or small talk", "complex": "a multi-step task that needs planning",
    ]

    static func predict(_ text: String, questions: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + "/v1/systemone") else { throw URLError(.badURL) }
        var req = URLRequest(url: url); req.httpMethod = "POST"; req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["state": ["text": text], "questions": questions])
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw URLError(.badServerResponse) }
        return obj
    }

    static func route(_ text: String) async -> RouteHint? {
        let q: [String: Any] = [
            "tool": ["type": "choice", "instructions": "Which single action does the user want from a Mac assistant?", "criteria": families],
            "multistep": ["type": "noul", "instructions": "Does this request need more than one action or step?"],
        ]
        guard let r = try? await predict(text, questions: q), let a = r["answers"] as? [String: Any],
              let tool = a["tool"] as? [String: Any], let choice = tool["choice"] as? String else { return nil }
        let p = (tool["probability"] as? Double) ?? (tool["confidence"] as? Double) ?? 0
        let multi = ((a["multistep"] as? [String: Any])?["noul"] as? Double) ?? 0
        let model = ((r["routing"] as? [String: Any])?["model"] as? String) ?? "english"
        return RouteHint(family: choice, probability: p, multistep: multi, multilingual: model == "multilingual")
    }

    /// Probability that the answer is yes.
    static func yesNo(_ text: String, _ question: String) async -> Double? {
        guard let r = try? await predict(text, questions: ["q": ["type": "noul", "instructions": question]]),
              let a = (r["answers"] as? [String: Any])?["q"] as? [String: Any] else { return nil }
        return a["noul"] as? Double
    }

    static func classify(_ text: String, _ question: String, _ criteria: [String: String]) async -> (String, Double)? {
        guard let r = try? await predict(text, questions: ["q": ["type": "choice", "instructions": question, "criteria": criteria]]),
              let a = (r["answers"] as? [String: Any])?["q"] as? [String: Any], let c = a["choice"] as? String else { return nil }
        return (c, (a["probability"] as? Double) ?? (a["confidence"] as? Double) ?? 0)
    }
}
