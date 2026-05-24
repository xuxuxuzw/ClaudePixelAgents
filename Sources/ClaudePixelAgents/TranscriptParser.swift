import Foundation

enum TranscriptParser {
    private static var permissionTimers: [Int: Timer] = [:]
    private static var textIdleTimers: [Int: Timer] = [:]
    private static var activeToolIds: [Int: Set<String>] = [:]

    private static let permissionDelay: TimeInterval = 7.0
    private static let textIdleDelay: TimeInterval = 5.0
    private static let permissionExemptTools: Set<String> = [
        "Read", "Glob", "Grep", "WebFetch", "WebSearch", "LS",
    ]

    static func processLine(agentId: Int, line: String, bridge: WebViewBridge?) {
        guard let record = try? JSONSerialization.jsonObject(with: line.data(using: .utf8) ?? Data()) as? [String: Any] else {
            return
        }

        guard let role = record["role"] as? String else { return }

        switch role {
        case "assistant":
            processAssistant(agentId: agentId, record: record, bridge: bridge)
        case "user":
            processUser(agentId: agentId, record: record, bridge: bridge)
        case "system":
            processSystem(agentId: agentId, record: record, bridge: bridge)
        default:
            break
        }
    }

    private static func processAssistant(agentId: Int, record: [String: Any], bridge: WebViewBridge?) {
        guard let message = record["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }

        var hasToolUse = false
        var toolIds: [String] = []

        for block in content {
            guard let type = block["type"] as? String else { continue }

            if type == "tool_use" {
                hasToolUse = true
                let toolId = block["id"] as? String ?? UUID().uuidString
                toolIds.append(toolId)

                if let toolName = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    let status = formatToolStatus(toolName: toolName, input: input)

                    sendToWebview(bridge, message: [
                        "type": "agentToolStart",
                        "id": agentId,
                        "toolId": toolId,
                        "toolName": toolName,
                        "status": status,
                    ])

                    if activeToolIds[agentId] == nil {
                        activeToolIds[agentId] = Set<String>()
                    }
                    activeToolIds[agentId]?.insert(toolId)

                    if !permissionExemptTools.contains(toolName) {
                        startPermissionTimer(agentId: agentId, bridge: bridge)
                    }

                    // Play typing sound for active tools
                    DispatchQueue.main.async {
                        AmbientSound.shared.playTypingSound()
                    }

                    sendToWebview(bridge, message: [
                        "type": "agentStatus",
                        "id": agentId,
                        "status": "active",
                    ])
                }
            }
        }

        if !hasToolUse {
            startTextIdleTimer(agentId: agentId, bridge: bridge)
        }
    }

    private static func processUser(agentId: Int, record: [String: Any], bridge: WebViewBridge?) {
        guard let message = record["message"] as? [String: Any],
              let content = message["content"] else { return }

        if let contentArray = content as? [[String: Any]] {
            for block in contentArray {
                guard let type = block["type"] as? String else { continue }

                if type == "tool_result", let toolUseId = block["tool_use_id"] as? String {
                    cancelPermissionTimer(agentId: agentId)
                    sendToWebview(bridge, message: [
                        "type": "agentToolDone",
                        "id": agentId,
                        "toolId": toolUseId,
                    ])
                    // Play done sound when tool completes
                    DispatchQueue.main.async {
                        AmbientSound.shared.playDoneSound()
                    }
                }
            }
        } else if let text = content as? String, !text.isEmpty {
            cancelPermissionTimer(agentId: agentId)
            cancelTextIdleTimer(agentId: agentId)
            clearAgentActivity(agentId: agentId, bridge: bridge)
        }
    }

    private static func processSystem(agentId: Int, record: [String: Any], bridge: WebViewBridge?) {
        guard let subtype = record["subtype"] as? String else { return }

        if subtype == "turn_duration" {
            cancelPermissionTimer(agentId: agentId)
            cancelTextIdleTimer(agentId: agentId)
            clearAgentActivity(agentId: agentId, bridge: bridge)

            sendToWebview(bridge, message: [
                "type": "agentStatus",
                "id": agentId,
                "status": "waiting",
            ])
        }
    }

    private static func clearAgentActivity(agentId: Int, bridge: WebViewBridge?) {
        activeToolIds[agentId] = nil
        sendToWebview(bridge, message: [
            "type": "agentToolsClear",
            "id": agentId,
        ])
    }

    // MARK: - Timers

    private static func startPermissionTimer(agentId: Int, bridge: WebViewBridge?) {
        cancelPermissionTimer(agentId: agentId)
        permissionTimers[agentId] = Timer.scheduledTimer(withTimeInterval: permissionDelay, repeats: false) { [weak bridge] _ in
            permissionTimers.removeValue(forKey: agentId)
            if activeToolIds[agentId] != nil {
                sendToWebview(bridge, message: [
                    "type": "agentToolPermission",
                    "id": agentId,
                ])
                // Play permission sound
                DispatchQueue.main.async {
                    AmbientSound.shared.playPermissionSound()
                }
            }
        }
    }

    private static func cancelPermissionTimer(agentId: Int) {
        permissionTimers[agentId]?.invalidate()
        permissionTimers.removeValue(forKey: agentId)
    }

    private static func startTextIdleTimer(agentId: Int, bridge: WebViewBridge?) {
        cancelTextIdleTimer(agentId: agentId)
        textIdleTimers[agentId] = Timer.scheduledTimer(withTimeInterval: textIdleDelay, repeats: false) { [weak bridge] _ in
            textIdleTimers.removeValue(forKey: agentId)
            sendToWebview(bridge, message: [
                "type": "agentToolsClear",
                "id": agentId,
            ])
            sendToWebview(bridge, message: [
                "type": "agentStatus",
                "id": agentId,
                "status": "waiting",
            ])
        }
    }

    private static func cancelTextIdleTimer(agentId: Int) {
        textIdleTimers[agentId]?.invalidate()
        textIdleTimers.removeValue(forKey: agentId)
    }

    // MARK: - Formatting

    private static func formatToolStatus(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Read":
            if let filePath = input["file_path"] as? String {
                let name = (filePath as NSString).lastPathComponent
                return "Reading \(name)"
            }
            return "Reading file"
        case "Write":
            if let filePath = input["file_path"] as? String {
                let name = (filePath as NSString).lastPathComponent
                return "Writing \(name)"
            }
            return "Writing file"
        case "Edit":
            if let filePath = input["file_path"] as? String {
                let name = (filePath as NSString).lastPathComponent
                return "Editing \(name)"
            }
            return "Editing file"
        case "Bash":
            if let cmd = input["command"] as? String {
                let truncated = cmd.count > 40 ? String(cmd.prefix(40)) + "..." : cmd
                return "Running \(truncated)"
            }
            return "Running command"
        case "Glob":
            return "Searching files"
        case "Grep":
            return "Searching code"
        case "WebFetch":
            return "Fetching web page"
        case "WebSearch":
            return "Searching web"
        case "Agent", "Task":
            return "Subtask: \(input["description"] as? String ?? "working")"
        default:
            return "Using \(toolName)"
        }
    }

    private static func sendToWebview(_ bridge: WebViewBridge?, message: [String: Any]) {
        DispatchQueue.main.async {
            bridge?.sendToWebview(message)
        }
    }
}
