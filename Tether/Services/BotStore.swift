import Foundation
import Combine

protocol BotRunClient: Sendable {
    func requireDurableRuns() async throws -> TimeInterval
    func createRun(input: String, sessionID: String, history: [ChatMessage], modelChoice: ModelChoice?, idempotencyKey: String) async throws -> RunSubmission
    func runStatus(_ runID: String) async throws -> RunStatus
    func runEvents(_ runID: String) -> AsyncThrowingStream<HermesRunEvent, Error>
    func stopRun(_ runID: String) async throws
    func resolveApproval(_ runID: String, choice: String, requestID: String?) async throws
    func steerRun(_ runID: String, input: String) async throws
}

extension HermesAPIClient: BotRunClient {}

/// Each bot owns an independent server session. Viewing another screen never
/// changes a worker's connection, task, model, or approval identity.
@MainActor
final class BotStore: ObservableObject {
    @Published private(set) var bots: [Bot] = []
    @Published private(set) var tasks: [BotTask] = []
    @Published private(set) var resolvingApprovals: Set<UUID> = []
    @Published var error: String?

    private struct Snapshot: Codable { var bots: [Bot]; var tasks: [BotTask] }
    private let file: URL
    private let clientFactory: (AgentConnection) -> any BotRunClient
    private var connections: [AgentConnection] = []
    private var workers: [UUID: Task<Void, Never>] = [:]
    private var isActive = true
    private var storageAvailable = true

    init(root: URL? = nil, clientFactory: ((AgentConnection) -> any BotRunClient)? = nil) {
        let root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = root.appending(path: "Bots/state.json")
        self.clientFactory = clientFactory ?? { connection in
            HermesAPIClient(connection: connection, apiKey: ConnectionStore().credential(for: connection))
        }
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let saved = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
                bots = saved.bots
                tasks = saved.tasks
            } catch {
                storageAvailable = false
                self.error = "Couldn’t read saved bots. Your saved file has been preserved. \(error.localizedDescription)"
            }
        }
    }

    var activeTasks: [BotTask] { tasks.filter { !$0.state.isTerminal } }
    var attentionCount: Int { tasks.filter { $0.state == .awaitingApproval || $0.state == .needsAttention }.count }
    func bot(_ id: UUID) -> Bot? { bots.first { $0.id == id } }
    func task(_ id: UUID) -> BotTask? { tasks.first { $0.id == id } }
    func history(for botID: UUID) -> [BotTask] { tasks.filter { $0.botID == botID }.sorted { $0.createdAt > $1.createdAt } }

    @discardableResult
    func save(_ bot: Bot) -> Bool {
        guard !bot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        if let previous = self.bot(bot.id), previous.connectionID != bot.connectionID {
            error = "Create a separate bot for another server so its context stays with the original Studio."
            return false
        }
        var updated = bots.filter { $0.id != bot.id }
        updated.append(bot)
        do { try commit(bots: updated, tasks: tasks); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    func delete(_ bot: Bot) {
        guard !activeTasks.contains(where: { $0.botID == bot.id }) else {
            error = "Stop or finish this bot’s tasks before deleting it."
            return
        }
        do { try commit(bots: bots.filter { $0.id != bot.id }, tasks: tasks.filter { $0.botID != bot.id }) }
        catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func enqueue(_ request: String, for bot: Bot) -> UUID? {
        let request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, self.bot(bot.id) != nil else { return nil }
        guard connections.contains(where: { $0.id == bot.connectionID && $0.transport == .apiServer }) else {
            error = "This bot needs its original Hermes API connection. Open Connections to check it."
            return nil
        }
        let task = BotTask(bot: bot, request: request)
        do { try commit(bots: bots, tasks: tasks + [task]); reconcile(); return task.id }
        catch { self.error = error.localizedDescription; return nil }
    }

    func configure(connections: [AgentConnection], active: Bool = true) {
        self.connections = connections
        isActive = active
        if !active {
            workers.values.forEach { $0.cancel() }
            return
        }
        for task in activeTasks where !connections.contains(where: { $0.id == task.connectionID }) {
            workers[task.id]?.cancel()
            try? update(task.id) {
                $0.state = .needsAttention
                $0.approval = nil
                $0.detail = "The original connection was removed. The remote task may still be running."
            }
        }
        reconcile()
    }

    func retry(_ id: UUID) {
        guard let item = task(id), item.state == .needsAttention, workers[id] == nil else { return }
        guard connections.contains(where: { $0.id == item.connectionID }) else {
            error = "The original connection is missing. This task cannot be moved to another server."
            return
        }
        do {
            try update(id) { $0.state = .reconnecting; $0.detail = nil }
            reconcile()
        } catch { self.error = error.localizedDescription }
    }

    /// Only forget a blocked checkpoint on explicit user action. Never imply a remote stop.
    func forget(_ id: UUID) {
        guard let item = task(id), item.state == .needsAttention, workers[id] == nil else { return }
        do { try commit(bots: bots, tasks: tasks.filter { $0.id != id }); reconcile() }
        catch { self.error = error.localizedDescription }
    }

    func stop(_ id: UUID) {
        guard let item = task(id), !item.state.isTerminal else { return }
        do {
            try update(id) {
                $0.stopRequested = true
                $0.approval = nil
                if $0.firstSubmissionAt == nil && $0.runID == nil { $0.state = .cancelled }
                else if $0.state != .needsAttention { $0.state = .stopping }
            }
            reconcile()
        } catch { self.error = error.localizedDescription }
    }

    func approve(_ id: UUID, choice: String) async {
        guard let item = task(id), !item.stopRequested,
              let approval = item.approval, approval.choices.contains(choice),
              !resolvingApprovals.contains(id),
              let connection = connections.first(where: { $0.id == item.connectionID }) else { return }
        resolvingApprovals.insert(id)
        defer { resolvingApprovals.remove(id) }
        do {
            try await clientFactory(connection).resolveApproval(approval.runID, choice: choice, requestID: approval.requestID)
            // An older response must not clear a newer prompt that arrived while awaiting it.
            if task(id)?.approval == approval {
                try update(id) { $0.approval = nil; $0.state = $0.stopRequested ? .stopping : .running }
            }
        } catch { self.error = "Couldn’t send approval: \(error.localizedDescription)" }
    }

    func steer(_ id: UUID, input: String) async -> Bool {
        guard let item = task(id), !item.state.isTerminal, !item.stopRequested,
              let runID = item.runID,
              let connection = connections.first(where: { $0.id == item.connectionID }) else { return false }
        do { try await clientFactory(connection).steerRun(runID, input: input); return true }
        catch { self.error = error.localizedDescription; return false }
    }

    private func reconcile() {
        guard isActive, storageAvailable else { return }
        // A bot's next task waits for the previous task; other bots work independently.
        for bot in bots {
            guard let item = tasks.first(where: { $0.botID == bot.id && !$0.state.isTerminal }),
                  item.state != .needsAttention, workers[item.id] == nil,
                  let connection = connections.first(where: { $0.id == item.connectionID }) else { continue }
            workers[item.id] = Task { [weak self] in
                guard let self else { return }
                await self.observe(item.id, connection: connection)
                self.workers[item.id] = nil
                self.reconcile()
            }
        }
    }

    private func observe(_ id: UUID, connection: AgentConnection) async {
        let client = clientFactory(connection)
        var eventTask: Task<Void, Never>?
        defer { eventTask?.cancel() }
        var delay = 2.0
        while !Task.isCancelled, let item = task(id), !item.state.isTerminal, item.state != .needsAttention {
            do {
                if item.runID == nil {
                    guard item.mayRetrySubmission else {
                        try update(id) {
                            $0.state = .needsAttention
                            $0.detail = "The server’s duplicate-protection window has expired. Check Hermes before starting this task again; it may already have run."
                        }
                        return
                    }
                    let retention = try await client.requireDurableRuns()
                    try Task.checkCancellation()
                    guard task(id)?.state.isTerminal == false else { return }
                    try update(id) {
                        $0.state = $0.stopRequested ? .stopping : .submitting
                        if $0.firstSubmissionAt == nil { $0.firstSubmissionAt = .now; $0.retentionSeconds = retention }
                    }
                    let submission = try await client.createRun(input: item.input, sessionID: item.botID.uuidString.lowercased(),
                        history: [], modelChoice: item.model, idempotencyKey: item.id.uuidString.lowercased())
                    // Save the receipt even if the phone just backgrounded: admission survives cancellation.
                    try update(id) {
                        $0.runID = submission.runID
                        if $0.state != .needsAttention { $0.state = $0.stopRequested ? .stopping : .running }
                    }
                    try Task.checkCancellation()
                }
                guard let runID = task(id)?.runID else { return }
                if eventTask == nil {
                    eventTask = Task { [weak self] in
                        do {
                            for try await event in client.runEvents(runID) {
                                guard !Task.isCancelled else { return }
                                self?.record(event, for: id)
                            }
                        } catch { /* Polling remains authoritative when SSE expires. */ }
                    }
                }
                let status = try await client.runStatus(runID)
                try Task.checkCancellation()
                try update(id) { task in
                    task.detail = nil
                    switch status.status {
                    case "completed": task.state = .completed; task.output = status.output ?? task.output; task.approval = nil
                    case "cancelled": task.state = .cancelled; task.approval = nil
                    case "failed", "interrupted":
                        task.state = .failed
                        task.output = status.output ?? task.output
                        task.detail = status.error ?? "Hermes \(status.status) this task."
                        task.approval = nil
                    case "unknown":
                        task.state = .needsAttention; task.approval = nil
                        task.detail = "Hermes restarted with an unknown outcome. Resolve this task on the Studio before sending more work to this bot."
                    default:
                        if task.stopRequested { task.state = .stopping; task.approval = nil }
                        else if let approval = status.approval {
                            task.state = .awaitingApproval
                            task.approval = RunApproval(runID: runID, command: approval.command ?? "Permission required", choices: approval.choices ?? ["deny"], requestID: approval.requestID)
                        } else { task.state = .running; task.approval = nil }
                    }
                    if task.state.isTerminal {
                        for index in task.activities.indices where task.activities[index].state == .running {
                            task.activities[index].state = task.state == .completed ? .completed : .failed
                        }
                    }
                }
                guard let current = task(id), !current.state.isTerminal, current.state != .needsAttention else { return }
                if current.stopRequested { try await client.stopRun(runID) }
                delay = 2
            } catch {
                if Task.isCancelled { return }
                let terminal = Self.attentionMessage(error)
                do {
                    try update(id) {
                        $0.state = terminal == nil ? ($0.stopRequested ? .stopping : .reconnecting) : .needsAttention
                        $0.detail = terminal ?? "The task is saved. Waiting for a connection to your Studio."
                        $0.approval = nil
                    }
                } catch {
                    storageAvailable = false
                    self.error = "Couldn’t save task progress: \(error.localizedDescription)"
                    return
                }
                if terminal != nil { return }
                delay = min(delay * 1.8, 20)
            }
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }

    private func record(_ event: HermesRunEvent, for id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), !tasks[index].state.isTerminal else { return }
        // Replayed deltas are not appended: polling provides authoritative output.
        guard event.event.contains("tool") || event.event.contains("subagent") else { return }
        let activity = AgentActivity(id: event.identity, turnID: id, title: event.name ?? event.tool ?? "Delegated task",
            detail: event.summary ?? event.preview ?? event.error, state: event.event.contains("fail") ? .failed : (event.event.contains("complete") ? .completed : .running), timestamp: .now)
        if let existing = tasks[index].activities.firstIndex(where: { $0.id == activity.id }) {
            tasks[index].activities[existing] = activity
        } else {
            tasks[index].activities.append(activity)
            tasks[index].activities = Array(tasks[index].activities.suffix(100))
        }
    }

    private static func attentionMessage(_ error: Error) -> String? {
        if let message = AppModel.savedRunFailureMessage(error) { return message }
        if case let HermesAPIClient.ClientError.server(status, _) = error,
           (400..<500).contains(status), ![408, 429].contains(status) {
            return "Hermes rejected this request (HTTP \(status)). Check the connection, model access, and original run before retrying."
        }
        if error is DecodingError { return "Hermes returned an unsupported response. Check the server version before retrying this saved task." }
        return nil
    }

    private func update(_ id: UUID, change: (inout BotTask) -> Void) throws {
        var updated = tasks
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        change(&updated[index])
        updated[index].updatedAt = .now
        try commit(bots: bots, tasks: updated)
    }

    private func commit(bots: [Bot], tasks: [BotTask]) throws {
        guard storageAvailable else { throw CocoaError(.fileReadCorruptFile) }
        let data = try JSONEncoder().encode(Snapshot(bots: bots, tasks: tasks))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        self.bots = bots
        self.tasks = tasks
    }
}
