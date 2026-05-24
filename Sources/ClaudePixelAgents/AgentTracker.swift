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
        agentStates.removeValue(forKey: agentId)
        CoffeeBreak.shared.cancelBreakCheck(agentId: agentId)

        if let state = agentStates[agentId] {
            employmentLog.recordFire(name: state.name, role: state.role)
        }

        sendToWebview(["type": "agentClosed", "id": agentId])
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

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-l", "-c", "\(claudePath) agents --json"]

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        do {
            try task.run()
            task.waitUntilExit()
            NSLog("[AgentTracker] claude agents exited with status \(task.terminationStatus)")
        } catch {
            NSLog("[AgentTracker] Failed to run claude agents: \(error)")
            return
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "nil"
        NSLog("[AgentTracker] claude agents output: \(output.prefix(300))")
        guard let sessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            NSLog("[AgentTracker] Failed to parse agents JSON")
            return
        }
        NSLog("[AgentTracker] Found \(sessions.count) sessions")

        var currentSessionIds = Set<String>()

        for sessionDict in sessions {
            guard let sessionId = sessionDict["sessionId"] as? String,
                  let kind = sessionDict["kind"] as? String,
                  kind == "background" else { continue }

            currentSessionIds.insert(sessionId)

            if knownSessions[sessionId] == nil {
                let agentId = nextAgentId
                nextAgentId += 1
                knownSessions[sessionId] = agentId

                let name = AgentNames.randomName(for: Localization.shared.currentLanguage)
                let role = AgentRoles.randomRole(for: Localization.shared.currentLanguage)

                let state = AgentState(id: agentId, sessionId: sessionId, name: name, role: role)
                agentStates[agentId] = state

                employmentLog.recordHire(name: name, role: role)

                sendToWebview([
                    "type": "agentCreated",
                    "id": agentId,
                ])

                // Send agent name via AgentTeamInfo (the protocol's way to set agent names)
                sendToWebview([
                    "type": "agentTeamInfo",
                    "id": agentId,
                    "agentName": name,
                    "agentRole": role,
                ])

                // Set initial status to 'waiting' (idle)
                sendToWebview([
                    "type": "agentStatus",
                    "id": agentId,
                    "status": "waiting",
                ])

                startWatching(agentId: agentId, sessionId: sessionId, cwd: sessionDict["cwd"] as? String ?? "")
                CoffeeBreak.shared.scheduleBreakCheck(agentId: agentId, bridge: bridge)
                print("[AgentTracker] Agent \(agentId) created: \(name) (\(role))")
                updateAgentCount()
                // Re-send language strings directly (before agentCreated reaches webview)
                bridge?.sendLanguageToWebviewDirect()
            }
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
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmPath) {
            let sorted = versions.sorted().reversed()
            for v in sorted {
                let claudeBin = "\(nvmPath)/\(v)/bin/claude"
                if FileManager.default.isExecutableFile(atPath: claudeBin) {
                    return claudeBin
                }
            }
        }
        return "claude"
    }

    private func sendToWebview(_ message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in
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
