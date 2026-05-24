import Foundation

struct AgentSession: Codable {
    let pid: Int
    let cwd: String
    let kind: String
    let startedAt: Int64
    let sessionId: String
    let name: String?
    let status: String?
}

class AgentTracker {
    private weak var bridge: WebViewBridge?
    private var pollTimer: Timer?
    private var nextAgentId: Int = 1
    private var knownSessions: [String: Int] = [:] // sessionId -> agentId
    private var watchers: [Int: TranscriptWatcher] = [:]
    private var agentStates: [Int: AgentState] = [:]
    private let employmentLog = EmploymentLog()
    private var didRunInitialScan: Bool = false

    init(bridge: WebViewBridge) {
        self.bridge = bridge
    }

    func start() {
        NSLog("[AgentTracker] Starting agent polling")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.pollAgentSessions()
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.pollAgentSessions()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        watchers.values.forEach { $0.stop() }
        watchers.removeAll()
    }

    func closeAgent(_ agentId: Int) {
        guard let (sessionId, _) = knownSessions.first(where: { $0.value == agentId }) else { return }
        watchers[agentId]?.stop()
        watchers.removeValue(forKey: agentId)
        knownSessions.removeValue(forKey: sessionId)
        // Do not remove `agentStates` before recording the fire event
        CoffeeBreak.shared.cancelBreakCheck(agentId: agentId)

        if let state = agentStates[agentId] {
            employmentLog.recordFire(name: state.name, role: state.role)
        }

        // Notify webview and then remove state
        sendToWebview(["type": "agentClosed", "id": agentId])
        agentStates.removeValue(forKey: agentId)

            // After recording a fire event, immediately push the updated employment log to the webview
            let all = employmentLog.getAllRecords()
            let mapped = all.map { rec -> [String: Any] in
                let ms = Int64(rec.time.timeIntervalSince1970 * 1000.0)
                return ["event": rec.event.rawValue, "role": rec.role, "name": rec.name, "time": ms]
            }
            sendToWebview(["type": "employmentLog", "records": mapped])
    }

    func handleAgentSeats(_ seats: [String: Any]) {
        let seatsDir = NSHomeDirectory() + "/.pixel-agents"
        try? FileManager.default.createDirectory(atPath: seatsDir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: seats, options: [.prettyPrinted]) {
            try? data.write(to: URL(fileURLWithPath: seatsDir + "/agent-seats.json"))
        }
    }

    private func pollAgentSessions() {
        let claudePath = getClaudePath()
        NSLog("[AgentTracker] Polling with claude path: \(claudePath ?? "nil")")
        guard let claudePath = claudePath else {
            NSLog("[AgentTracker] Claude CLI not found")
            return
        }

        let command = "\(claudePath) agents --json"
        NSLog("[AgentTracker] Executing command: \(command)")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        // 添加输入管道（防止命令等待输入）
        let stdin = Pipe()
        task.standardInput = stdin

        do {
            try task.run()
            NSLog("[AgentTracker] Process started with PID: \(task.processIdentifier)")
        } catch {
            NSLog("[AgentTracker] Failed to run claude agents: \(error)")
            return
        }

        // 关闭输入管道（告诉命令没有更多输入）
        stdin.fileHandleForReading.closeFile()

        // 设置超时（5秒）
        let timeoutItem = DispatchWorkItem { [weak task] in
            task?.terminate()
            NSLog("[AgentTracker] Command timed out after 5 seconds")
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeoutItem)

        // 读取输出（必须在 waitUntilExit 之前）
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        // 取消超时并等待进程退出，以便记录退出状态
        timeoutItem.cancel()
        task.waitUntilExit()
        NSLog("[AgentTracker] claude agents exited with status \(task.terminationStatus)")

        let output = String(data: data, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        if !errorOutput.isEmpty {
            NSLog("[AgentTracker] claude agents stderr: \(errorOutput.prefix(500))")
        }
        NSLog("[AgentTracker] claude agents stdout length: \(data.count), stderr length: \(errorData.count)")
        NSLog("[AgentTracker] claude agents output: \(output.prefix(1000))")

        guard let sessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            NSLog("[AgentTracker] Failed to parse agents JSON — raw output below:\n\(output)")
            return
        }
        NSLog("[AgentTracker] Found \(sessions.count) sessions")

        // Debug: enumerate background sessions found
        var bgIds: [String] = []
        for sessionDict in sessions {
            if let kind = sessionDict["kind"] as? String, kind == "background",
               let sid = sessionDict["sessionId"] as? String {
                bgIds.append(sid)
            }
        }
        NSLog("[AgentTracker] Background sessionIds: \(bgIds)")

        var currentSessionIds = Set<String>()

        for sessionDict in sessions {
            guard let sessionId = sessionDict["sessionId"] as? String,
                  let kind = sessionDict["kind"] as? String else { continue }
            // 暂时禁用 background 过滤，允许检测所有会话类型
            // if kind != "background" { continue }

            currentSessionIds.insert(sessionId)

            if knownSessions[sessionId] == nil {
                let agentId = nextAgentId
                nextAgentId += 1
                knownSessions[sessionId] = agentId

                let name = AgentNames.randomName(for: Localization.shared.currentLanguage)
                let role = AgentRoles.randomRole(for: Localization.shared.currentLanguage)

                let state = AgentState(id: agentId, sessionId: sessionId, name: name, role: role)
                agentStates[agentId] = state

                // Extract startedAt (milliseconds since epoch) from session metadata when available
                var startedAtMs: Int64? = nil
                if let n = sessionDict["startedAt"] as? Int64 {
                    startedAtMs = n
                } else if let d = sessionDict["startedAt"] as? Double {
                    startedAtMs = Int64(d)
                } else if let num = sessionDict["startedAt"] as? NSNumber {
                    startedAtMs = num.int64Value
                } else if let s = sessionDict["startedAt"] as? String, let d = Double(s) {
                    startedAtMs = Int64(d)
                }

                employmentLog.recordHire(name: name, role: role, timeMs: startedAtMs)

                // Send creation messages in a deterministic order
                sendToWebviewSync([
                    "type": "agentCreated",
                    "id": agentId,
                ])


                // Send agent name via AgentTeamInfo (the protocol's way to set agent names)
                sendToWebviewSync([
                    "type": "agentTeamInfo",
                    "id": agentId,
                    "agentName": name,
                    "agentRole": role,
                ])

                // Set initial status to 'waiting' (idle)
                sendToWebviewSync([
                    "type": "agentStatus",
                    "id": agentId,
                    "status": "waiting",
                ])

                // Send welcome banner only for agents created after initial scan
                if didRunInitialScan {
                    sendToWebviewSync([
                        "type": "welcomeBanner",
                        "id": agentId,
                        "name": name,
                        "role": role,
                        "durationMs": 3000,
                    ])
                } else {
                    NSLog("[AgentTracker] Skipping welcomeBanner for initial agent \(agentId): \(name)")
                }

                startWatching(agentId: agentId, sessionId: sessionId, cwd: sessionDict["cwd"] as? String ?? "")
                CoffeeBreak.shared.scheduleBreakCheck(agentId: agentId, bridge: bridge)
                print("[AgentTracker] Agent \(agentId) created: \(name) (\(role))")
                updateAgentCount()
                // Re-send language strings directly (before agentCreated reaches webview)
                bridge?.sendLanguageToWebviewDirect()
            }
        }

        // Mark that the initial seed scan has completed; subsequent polls should show welcome banners
        if !didRunInitialScan {
            didRunInitialScan = true
            NSLog("[AgentTracker] Initial agent scan completed; future new agents will show welcome banners")
        }

        for (sessionId, agentId) in knownSessions {
            if !currentSessionIds.contains(sessionId) {
                watchers[agentId]?.stop()
                watchers.removeValue(forKey: agentId)
                knownSessions.removeValue(forKey: sessionId)
                CoffeeBreak.shared.cancelBreakCheck(agentId: agentId)

                if let state = agentStates[agentId] {
                    employmentLog.recordFire(name: state.name, role: state.role)
                }
                agentStates.removeValue(forKey: agentId)

                sendToWebview(["type": "agentClosed", "id": agentId])
                print("[AgentTracker] Agent \(agentId) closed")
                updateAgentCount()

                    // push updated employment log after fire
                    let all2 = employmentLog.getAllRecords()
                    let mapped2 = all2.map { rec -> [String: Any] in
                        let ms = Int64(rec.time.timeIntervalSince1970 * 1000.0)
                        return ["event": rec.event.rawValue, "role": rec.role, "name": rec.name, "time": ms]
                    }
                    sendToWebview(["type": "employmentLog", "records": mapped2])
            }
        }
    }

    private func startWatching(agentId: Int, sessionId: String, cwd: String) {
        let projectHash = normalizeProjectPath(cwd)
        let homeDir = NSHomeDirectory()
        let jsonlPath = "\(homeDir)/.claude/projects/\(projectHash)/\(sessionId).jsonl"

        guard FileManager.default.fileExists(atPath: jsonlPath) else {
            print("[AgentTracker] JSONL not found at \(jsonlPath), waiting...")
            DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) { [weak self] in
                guard FileManager.default.fileExists(atPath: jsonlPath) else { return }
                self?.startWatcher(agentId: agentId, jsonlPath: jsonlPath)
            }
            return
        }
        startWatcher(agentId: agentId, jsonlPath: jsonlPath)
    }

    private func startWatcher(agentId: Int, jsonlPath: String) {
        let watcher = TranscriptWatcher(agentId: agentId, jsonlPath: jsonlPath, bridge: bridge)
        watchers[agentId] = watcher
        watcher.start()
    }

    private func normalizeProjectPath(_ path: String) -> String {
        return path
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }

    private func getClaudePath() -> String? {
        let nvmPath = NSHomeDirectory() + "/.nvm/versions/node"
        NSLog("[AgentTracker] Checking NVM path: \(nvmPath)")

        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmPath) {
            NSLog("[AgentTracker] Found Node versions: \(versions)")
            let sorted = versions.sorted().reversed()
            for v in sorted {
                let claudeBin = "\(nvmPath)/\(v)/bin/claude"
                let exists = FileManager.default.isExecutableFile(atPath: claudeBin)
                NSLog("[AgentTracker] Checking \(claudeBin): exists=\(exists)")
                if exists {
                    return claudeBin
                }
            }
        } else {
            NSLog("[AgentTracker] NVM path not found or cannot read directory")
        }

        // Fallback: try to find claude in PATH
        NSLog("[AgentTracker] Falling back to 'claude' in PATH")
        return "claude"
    }

    private func sendToWebview(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.sendToWebview(message)
        }
    }

    /// Synchronous send to webview to preserve message ordering when called from background threads.
    private func sendToWebviewSync(_ message: [String: Any]) {
        DispatchQueue.main.sync { [weak self] in
            self?.bridge?.sendToWebview(message)
        }
    }

    private func updateAgentCount() {
        let count = knownSessions.count
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.agentCount = count
        }
    }
}
