import WebKit

class WebViewBridge: NSObject {
    private static var _shared: WebViewBridge?
    static var shared: WebViewBridge {
        if _shared == nil {
            _shared = WebViewBridge()
        }
        return _shared!
    }

    let webView: WKWebView
    private let userContentController: WKUserContentController

    private var assetLoader: AgentAssetLoader?
    private var agentTracker: AgentTracker?
    private var dayNightCycle: DayNightCycle?
    private var localServer: LocalServer?
    var onAgentCountChanged: ((Int) -> Void)?
    var agentCount: Int = 0 {
        didSet {
            if agentCount != oldValue {
                DispatchQueue.main.async { [weak self] in
                    self?.onAgentCountChanged?(self?.agentCount ?? 0)
                }
            }
        }
    }

    override init() {
        userContentController = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = userContentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        userContentController.add(self, name: "claudePixelAgents")

        webView.navigationDelegate = self

        // Inject acquireVsCodeApi shim via WKUserScript — runs at document start
        let shimSource = """
        window.acquireVsCodeApi = function() {
            return {
                postMessage: function(msg) {
                    window.webkit.messageHandlers.claudePixelAgents.postMessage(JSON.stringify(msg));
                }
            };
        };
        """
        let userScript = WKUserScript(source: shimSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userContentController.addUserScript(userScript)

        assetLoader = AgentAssetLoader(bridge: self)
        agentTracker = AgentTracker(bridge: self)
        dayNightCycle = DayNightCycle(bridge: self)

        startServerAndLoad()
    }

    private func startServerAndLoad() {
        guard let server = LocalServer() else {
            NSLog("[WebViewBridge] Failed to create LocalServer")
            return
        }
        self.localServer = server
        server.start()

        guard server.actualPort > 0 else {
            NSLog("[WebViewBridge] Server failed to start")
            return
        }

        // Give the Python server a moment to bind, then load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.loadFromServer(port: server.actualPort)
        }
    }

    func sendLanguageToWebview() {
        let l10n = Localization.shared
        sendToWebview([
            "type": "languageLoaded",
            "language": l10n.currentLanguage.rawValue,
            "strings": [
                "working": l10n.working,
                "waiting": l10n.waiting,
                "permissionNeeded": l10n.permissionNeeded,
                "reading": l10n.reading,
                "writing": l10n.writing,
                "editing": l10n.editing,
                "hired": l10n.hired,
                "fired": l10n.fired,
                "windowTitle": l10n.windowTitle,
            ],
        ])
    }

    /// Synchronous version: sends directly via evaluateJavaScript (can be called from any thread)
    func sendLanguageToWebviewDirect() {
        let l10n = Localization.shared
        let message: [String: Any] = [
            "type": "languageLoaded",
            "language": l10n.currentLanguage.rawValue,
            "strings": [
                "working": l10n.working,
                "waiting": l10n.waiting,
                "permissionNeeded": l10n.permissionNeeded,
                "reading": l10n.reading,
                "writing": l10n.writing,
                "editing": l10n.editing,
                "hired": l10n.hired,
                "fired": l10n.fired,
                "windowTitle": l10n.windowTitle,
            ],
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.postMessage(JSON.parse('\(escaped)'), '*')")
    }

    private func loadFromServer(port: UInt16) {
        guard let url = URL(string: "http://localhost:\(port)/index.html") else { return }
        NSLog("[WebViewBridge] Loading from server: \(url)")
        webView.load(URLRequest(url: url))
    }

    func sendToWebview(_ message: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.postMessage(JSON.parse('\(escaped)'), '*')")
    }

    func sendToWebviewRaw(_ jsonString: String) {
        let escaped = jsonString.replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.postMessage(JSON.parse('\(escaped)'), '*')")
    }
}

extension WebViewBridge: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        switch type {
        case "webviewReady":
            NSLog("[WebViewBridge] Webview ready")
            sendLanguageToWebview()
            assetLoader?.loadAllAssets()
            agentTracker?.start()
            dayNightCycle?.start()
        case "saveLayout":
            if let layout = json["layout"] {
                saveToFile("~/.pixel-agents/layout.json", object: layout)
            }
        case "saveAgentSeats":
            if let seats = json["seats"] {
                saveToFile("~/.pixel-agents/agent-seats.json", object: seats)
            }
        case "setLanguage":
            if let lang = json["language"] as? String,
               let language = Language(rawValue: lang) {
                Localization.shared.currentLanguage = language
                sendLanguageToWebview()
            }
        default:
            break
        }
    }

    private func saveToFile(_ path: String, object: Any) {
        let expanded = NSString(string: path).expandingTildeInPath
        let dir = (expanded as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: expanded))
        }
    }
}

extension WebViewBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("[WebViewBridge] Page loaded")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[WebViewBridge] Navigation failed: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[WebViewBridge] Provisional navigation failed: \(error.localizedDescription)")
    }
}
