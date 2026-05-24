import Foundation

class TranscriptWatcher {
    let agentId: Int
    let jsonlPath: String
    private weak var bridge: WebViewBridge?

    private var fileHandle: FileHandle?
    private var timer: Timer?
    private var lineBuffer: String = ""

    private let pollInterval: TimeInterval = 0.5
    private let maxReadBytes = 65536

    init(agentId: Int, jsonlPath: String, bridge: WebViewBridge?) {
        self.agentId = agentId
        self.jsonlPath = jsonlPath
        self.bridge = bridge
    }

    func start() {
        guard FileManager.default.fileExists(atPath: jsonlPath) else {
            print("[TranscriptWatcher] File not found: \(jsonlPath)")
            return
        }

        fileHandle = FileHandle(forReadingAtPath: jsonlPath)
        fileHandle?.seekToEndOfFile()

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.readNewLines()
        }
        print("[TranscriptWatcher] Watching \(jsonlPath) for agent \(agentId)")
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        fileHandle?.closeFile()
        fileHandle = nil
    }

    private func readNewLines() {
        guard let handle = fileHandle else { return }

        let available = handle.availableData
        guard !available.isEmpty else { return }

        guard let newContent = String(data: available, encoding: .utf8) else { return }

        lineBuffer += newContent

        let lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = lines.last ?? ""

        for i in 0..<(lines.count - 1) {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                TranscriptParser.processLine(agentId: agentId, line: line, bridge: bridge)
            }
        }
    }
}
