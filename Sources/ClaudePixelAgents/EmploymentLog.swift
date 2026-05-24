import Foundation

struct EmploymentRecord: Codable {
    let time: Date
    let name: String
    let role: String
    let event: EventType

    enum EventType: String, Codable {
        case hire
        case fire
    }
}

class EmploymentLog {
    private var records: [EmploymentRecord] = []
    private let filePath: String

    init() {
        let dir = NSHomeDirectory() + "/.pixel-agents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        filePath = dir + "/employment-log.json"
        load()
    }

    func recordHire(name: String, role: String, timeMs: Int64? = nil) {
        let time: Date
        if let ms = timeMs {
            time = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        } else {
            time = Date()
        }
        let record = EmploymentRecord(time: time, name: name, role: role, event: .hire)
        records.append(record)
        save()
        print("[EmploymentLog] HIRE: \(name) (\(role)) at \(time)")
    }

    func recordFire(name: String, role: String) {
        let record = EmploymentRecord(time: Date(), name: name, role: role, event: .fire)
        records.append(record)
        save()
        print("[EmploymentLog] FIRE: \(name) (\(role))")
    }

    func getAllRecords() -> [EmploymentRecord] {
        return records.sorted { $0.time > $1.time }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = FileManager.default.contents(atPath: filePath),
              let decoded = try? JSONDecoder().decode([EmploymentRecord].self, from: data) else {
            return
        }
        records = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: URL(fileURLWithPath: filePath))
    }
}
