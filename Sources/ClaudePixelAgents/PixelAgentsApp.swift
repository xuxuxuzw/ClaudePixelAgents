import SwiftUI

@main
struct PixelAgentsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var currentLanguage: Language = Localization.shared.currentLanguage
    @State private var agentCount: Int = 0
    @State private var windowTitle: String = Localization.shared.windowTitle

    init() {
        // Initialize the bridge singleton before any views are created
        _ = WebViewBridge.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            toggleLanguage()
                        } label: {
                            Text(currentLanguage == .chinese ? "中 / EN" : "EN / 中")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .help(currentLanguage == .chinese ? "Switch to English" : "切换到中文")
                    }
                }
                .onAppear {
                    WebViewBridge.shared.onAgentCountChanged = { count in
                        agentCount = count
                        updateWindowTitle()
                    }
                    updateWindowTitle()
                }
                .onChange(of: currentLanguage) { _, _ in
                    updateWindowTitle()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1200, height: 800)
    }

    private func toggleLanguage() {
        let newLang: Language = currentLanguage == .chinese ? .english : .chinese
        currentLanguage = newLang
        Localization.shared.currentLanguage = newLang
        WebViewBridge.shared.sendLanguageToWebview()
        updateWindowTitle()
    }

    private func updateWindowTitle() {
        let l10n = Localization.shared
        if agentCount > 0 {
            let countStr = currentLanguage == .chinese ? "\(agentCount) 个代理" : "\(agentCount) agents"
            windowTitle = "\(l10n.windowTitle) — \(countStr)"
        } else {
            windowTitle = l10n.windowTitle
        }
        NSApp.mainWindow?.title = windowTitle
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
