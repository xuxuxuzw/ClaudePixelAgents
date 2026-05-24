import Foundation

class LocalServer {
    private var process: Process?
    private(set) var actualPort: UInt16 = 0
    private let webviewDir: String

    var serverURL: URL? {
        guard actualPort > 0 else { return nil }
        return URL(string: "http://localhost:\(actualPort)/index.html")
    }

    init?() {
        let bundleName = "ClaudePixelAgents_ClaudePixelAgents"
        var bundle: Bundle?
        for b in Bundle.allBundles {
            if b.bundlePath.contains(bundleName) {
                bundle = b
                break
            }
        }
        guard let resourceBundle = bundle,
              let dir = resourceBundle.url(forResource: "webview", withExtension: nil) else {
            NSLog("[LocalServer] webview directory not found in bundle")
            return nil
        }
        self.webviewDir = dir.path
    }

    func start() {
        // Find a free port by binding to port 0
        let port = findFreePort()
        guard port > 0 else {
            NSLog("[LocalServer] Failed to find free port")
            return
        }
        self.actualPort = UInt16(port)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-m", "http.server", "\(port)", "--bind", "127.0.0.1", "--directory", webviewDir]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            self.process = task
            NSLog("[LocalServer] Python HTTP server started on port \(port), serving \(webviewDir)")
        } catch {
            NSLog("[LocalServer] Failed to start Python server: \(error)")
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    private func findFreePort() -> Int {
        // Use Python to find a free port
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = ["-c", """
            import socket
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.bind(('127.0.0.1', 0))
            print(s.getsockname()[1])
            s.close()
            """]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let portStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "0"
            return Int(portStr) ?? 0
        } catch {
            NSLog("[LocalServer] Failed to find free port: \(error)")
            return 0
        }
    }
}
