import Foundation

class CoffeeBreak {
    static let shared = CoffeeBreak()

    private var breakTimers: [Int: Timer] = [:]
    private let breakChance = 0.3
    private let idleThreshold: TimeInterval = 30.0
    private let breakDuration: TimeInterval = 20.0

    private init() {}

    func scheduleBreakCheck(agentId: Int, bridge: WebViewBridge?) {
        cancelBreakCheck(agentId: agentId)

        breakTimers[agentId] = Timer.scheduledTimer(withTimeInterval: idleThreshold, repeats: true) { [weak self, weak bridge] _ in
            guard let self = self else { return }

            if Double.random(in: 0...1) < self.breakChance {
                self.triggerCoffeeBreak(agentId: agentId, bridge: bridge)
            }
        }
    }

    func cancelBreakCheck(agentId: Int) {
        breakTimers[agentId]?.invalidate()
        breakTimers.removeValue(forKey: agentId)
    }

    private func triggerCoffeeBreak(agentId: Int, bridge: WebViewBridge?) {
        cancelBreakCheck(agentId: agentId)

        DispatchQueue.main.async {
            bridge?.sendToWebview([
                "type": "coffeeBreakStart",
                "id": agentId,
            ])
        }

        breakTimers[agentId] = Timer.scheduledTimer(withTimeInterval: breakDuration, repeats: false) { [weak self, weak bridge] _ in
            self?.breakTimers.removeValue(forKey: agentId)

            DispatchQueue.main.async {
                bridge?.sendToWebview([
                    "type": "coffeeBreakEnd",
                    "id": agentId,
                ])
            }
        }
    }
}
