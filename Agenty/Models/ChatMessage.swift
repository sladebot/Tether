import Foundation

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String
    var turnID: UUID?

    init(id: UUID = UUID(), role: Role, content: String, turnID: UUID? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.turnID = turnID
    }
}

struct ModelChoice: Codable, Equatable, Hashable, Identifiable, Sendable {
    let provider: String
    let providerName: String
    let model: String
    var id: String { "\(provider)/\(model)" }
}

struct AgentActivity: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case running, completed, failed }

    let id: String
    let turnID: UUID
    var title: String
    var detail: String?
    var state: State
    var timestamp: Date
}

struct RunApproval: Equatable, Sendable {
    let runID: String
    let command: String
    let choices: [String]
}

struct PendingRun: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case submitting, running, waitingForNetwork }

    let idempotencyKey: String
    var runID: String?
    let turnID: UUID
    let assistantMessageID: UUID
    let input: String
    let conversationHistory: [ChatMessage]
    let createdAt: Date
    var state: State
}

struct Conversation: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let connectionID: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ChatMessage]
    var activities: [AgentActivity]
    var pendingRun: PendingRun?
    var modelChoice: ModelChoice?

    init(
        id: UUID = UUID(), connectionID: UUID, title: String = "New chat",
        createdAt: Date = Date(), updatedAt: Date = Date(), messages: [ChatMessage] = [],
        activities: [AgentActivity] = [], pendingRun: PendingRun? = nil, modelChoice: ModelChoice? = nil
    ) {
        self.id = id
        self.connectionID = connectionID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.activities = activities
        self.pendingRun = pendingRun
        self.modelChoice = modelChoice
    }
}
