import Foundation

struct Bot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let connectionID: UUID
    var name: String
    var instructions: String
    var symbol: String
    var model: ModelChoice?
    let createdAt: Date

    init(id: UUID = UUID(), connectionID: UUID, name: String, instructions: String,
         symbol: String = "sparkles", model: ModelChoice? = nil, createdAt: Date = .now) {
        self.id = id
        self.connectionID = connectionID
        self.name = name
        self.instructions = instructions
        self.symbol = symbol
        self.model = model
        self.createdAt = createdAt
    }

    var modelLabel: String { model.map { "\($0.providerName) · \($0.model)" } ?? "Hermes default" }
}

struct BotTask: Identifiable, Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case queued, submitting, running, awaitingApproval, reconnecting, stopping, needsAttention
        case completed, cancelled, failed

        var isTerminal: Bool { [.completed, .cancelled, .failed].contains(self) }
        var title: String {
            switch self {
            case .queued: "Queued"
            case .submitting: "Sending to Studio"
            case .running: "Working"
            case .awaitingApproval: "Needs your approval"
            case .reconnecting: "Waiting to reconnect"
            case .stopping: "Stopping"
            case .needsAttention: "Needs attention"
            case .completed: "Done"
            case .cancelled: "Stopped"
            case .failed: "Couldn’t finish"
            }
        }
    }

    let id: UUID
    let botID: UUID
    let connectionID: UUID
    let request: String
    // Exact execution settings are frozen before admission, including the provider.
    let input: String
    let model: ModelChoice?
    let createdAt: Date
    var updatedAt: Date
    var state: State = .queued
    var runID: String?
    var firstSubmissionAt: Date?
    var retentionSeconds: TimeInterval?
    var stopRequested = false
    var approval: RunApproval?
    var output = ""
    var detail: String?
    var activities: [AgentActivity] = []

    init(id: UUID = UUID(), bot: Bot, request: String, now: Date = .now) {
        self.id = id
        botID = bot.id
        connectionID = bot.connectionID
        self.request = request
        input = """
        You are \(bot.name), a personal bot working on the user's Studio through Tether.
        Your role: \(bot.instructions)
        Complete the task and give a clear result. Use the server's existing approval rules.
        Do not claim to have scheduled recurring work or sent a notification unless a tool confirms it.

        User task:
        \(request)
        """
        model = bot.model
        createdAt = now
        updatedAt = now
    }

    var mayRetrySubmission: Bool {
        guard let firstSubmissionAt else { return true }
        guard let retentionSeconds else { return false }
        return Date().timeIntervalSince(firstSubmissionAt) < retentionSeconds
    }
}
