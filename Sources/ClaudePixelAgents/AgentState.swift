import Foundation

class AgentState {
    let id: Int
    let sessionId: String
    let name: String
    let role: String
    var isActive: Bool = false
    var activeToolName: String?
    var createdAt: Date

    init(id: Int, sessionId: String, name: String, role: String) {
        self.id = id
        self.sessionId = sessionId
        self.name = name
        self.role = role
        self.createdAt = Date()
    }
}
