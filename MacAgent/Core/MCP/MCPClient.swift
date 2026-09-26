import Foundation

/// Minimal MCP client over stdio (newline-delimited JSON-RPC). Spawns `node mac-tools` on demand,
/// exits it after 5 minutes idle so the agent costs nothing while unused.
final class MCPClient {
    static let shared = MCPClient()

    struct Tool {
        let name: String
        let description: String
        let schema: [String: Any]
        let readOnly: Bool
        let destructive: Bool
    }

    enum MCPError: LocalizedError {
        case notRunning, timeout(String), rpc(String), badResponse
        var errorDescription: String? {
            switch self {
            case .notRunning: return "tool server is not running"
            case .timeout(let m): return "tool server timed out on \(m)"
            case .rpc(let m): return m
            case .badResponse: return "unexpected tool server response"
            }
        }
    }

    private(set) var tools: [Tool] = []
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private let lock = NSLock()
    private var idleWork: DispatchWorkItem?
    private let idleSeconds: TimeInterval = 300
    private var starting: Task<Void, Error>?

    var isRunning: Bool { process?.isRunning ?? false }

    func ensureStarted() async throws {
        if isRunning { touch(); return }
        if let starting { try await starting.value; return }
        let t = Task { try await start() }
        starting = t
        defer { starting = nil }
        try await t.value
    }

    func tool(named name: String) -> Tool? { tools.first { $0.name == name } }

    /// Calls a tool. Returns the joined text content and whether the server flagged an error.
    func call(_ name: String, args: [String: Any]) async throws -> (text: String, isError: Bool) {
        try await ensureStarted()
        let result = try await request("tools/call", params: ["name": name, "arguments": args], timeout: 60)
        let content = (result["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        return (content, (result["isError"] as? Bool) ?? false)
    }

    func stop() {
        lock.lock()
        let procs = process; process = nil; stdinHandle = nil; tools = []
        let waiting = pending; pending = [:]
        lock.unlock()
        idleWork?.cancel(); idleWork = nil
        procs?.terminate()
        for (_, c) in waiting { c.resume(throwing: MCPError.notRunning) }
    }

    // MARK: Private

    private func start() async throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: Settings.nodePath)
        p.arguments = [Settings.mcpServerPath]
        var env = ProcessInfo.processInfo.environment
        env["MACAGENT_ALLOWED_ROOTS"] = Settings.allowedRoots.joined(separator: ":")
        p.environment = env
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = Self.stderrHandle()
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            self?.receive(d)
        }
        p.terminationHandler = { [weak self] _ in self?.stop() }
        try p.run()
        lock.lock(); process = p; stdinHandle = inPipe.fileHandleForWriting; buffer = Data(); lock.unlock()
        _ = try await request("initialize", params: [
            "protocolVersion": "2025-06-18", "capabilities": [:],
            "clientInfo": ["name": "MacAgent", "version": "0.1.0"],
        ], timeout: 15)
        send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        let list = try await request("tools/list", timeout: 15)
        tools = (list["tools"] as? [[String: Any]] ?? []).map { t in
            let ann = t["annotations"] as? [String: Any] ?? [:]
            return Tool(name: t["name"] as? String ?? "", description: t["description"] as? String ?? "",
                        schema: t["inputSchema"] as? [String: Any] ?? ["type": "object"],
                        readOnly: ann["readOnlyHint"] as? Bool ?? false, destructive: ann["destructiveHint"] as? Bool ?? false)
        }
        touch()
    }

    private func touch() {
        idleWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.stop() }
        idleWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + idleSeconds, execute: w)
    }

    private func request(_ method: String, params: [String: Any] = [:], timeout: TimeInterval) async throws -> [String: Any] {
        lock.lock(); let id = nextID; nextID += 1; lock.unlock()
        return try await withCheckedThrowingContinuation { cont in
            lock.lock(); pending[id] = cont; lock.unlock()
            send(["jsonrpc": "2.0", "id": id, "method": method, "params": params])
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self else { return }
                self.lock.lock(); let c = self.pending.removeValue(forKey: id); self.lock.unlock()
                c?.resume(throwing: MCPError.timeout(method))
            }
        }
    }

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj), let h = stdinHandle else { return }
        h.write(data + Data([0x0A]))
    }

    private func receive(_ data: Data) {
        lock.lock(); buffer.append(data)
        var lines: [Data] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer.subdata(in: buffer.startIndex..<nl))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        lock.unlock()
        for line in lines where !line.isEmpty {
            guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let id = msg["id"] as? Int else { continue }
            lock.lock(); let cont = pending.removeValue(forKey: id); lock.unlock()
            guard let cont else { continue }
            if let err = msg["error"] as? [String: Any] {
                cont.resume(throwing: MCPError.rpc(err["message"] as? String ?? "tool error"))
            } else if let result = msg["result"] as? [String: Any] {
                cont.resume(returning: result)
            } else {
                cont.resume(throwing: MCPError.badResponse)
            }
        }
    }

    private static func stderrHandle() -> FileHandle {
        let dir = NSHomeDirectory() + "/Library/Application Support/MacAgent"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = dir + "/mcp-stderr.log"
        if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
        let h = FileHandle(forWritingAtPath: path) ?? .nullDevice
        h.seekToEndOfFile()
        return h
    }
}
