import AppKit

class AmbientSound {
    static let shared = AmbientSound()

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "claudePixelAgents_soundEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "claudePixelAgents_soundEnabled") }
    }

    private init() {}

    func playTypingSound() {
        guard isEnabled else { return }
        playSystemSound("key_press_click")
    }

    func playDoneSound() {
        guard isEnabled else { return }
        playSystemSound("Glass")
    }

    func playPermissionSound() {
        guard isEnabled else { return }
        playSystemSound("Ping")
    }

    private func playSystemSound(_ name: String) {
        NSSound(named: name)?.play()
    }
}
