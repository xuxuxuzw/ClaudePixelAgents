import Foundation

class DayNightCycle {
    private weak var bridge: WebViewBridge?
    private var timer: Timer?

    init(bridge: WebViewBridge) {
        self.bridge = bridge
    }

    func start() {
        updateBrightness()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.updateBrightness()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func updateBrightness() {
        let brightness = calculateBrightness()
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.sendToWebview([
                "type": "dayNightUpdate",
                "brightness": brightness,
            ])
        }
    }

    private func calculateBrightness() -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        let minute = calendar.component(.minute, from: Date())
        let time = Double(hour) + Double(minute) / 60.0

        switch time {
        case 6.0..<8.0:
            // Dawn: 0.7 -> 1.0
            return 0.7 + (time - 6.0) / 2.0 * 0.3
        case 8.0..<18.0:
            // Day: 1.0
            return 1.0
        case 18.0..<20.0:
            // Dusk: 1.0 -> 0.7
            return 1.0 - (time - 18.0) / 2.0 * 0.3
        case 20.0..<24.0:
            // Night: 0.7
            return 0.7
        default:
            // 0.0 - 6.0: Night: 0.7
            return 0.7
        }
    }
}
