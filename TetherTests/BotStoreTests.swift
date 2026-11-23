import XCTest
import WebKit
@testable import Tether

@MainActor
final class BotStoreTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func connection() -> AgentConnection {
        AgentConnection(name: "Studio", baseURL: "https://studio.example.ts.net", route: .tailscale)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 8, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out: \(description)")
    }

    func testBotsRouteDifferentProvidersAndFreezeQueuedModelSettings() async throws {
        let client = RecordingBotClient()
        let store = BotStore(root: try temporaryRoot(), clientFactory: { _ in client })
        let connection = connection()
        store.configure(connections: [connection], active: false)
        let anthropic = ModelChoice(provider: "anthropic", providerName: "Anthropic", model: "model-a")
        let openai = ModelChoice(provider: "openai", providerName: "OpenAI", model: "model-b")
        var research = Bot(connectionID: connection.id, name: "Research", instructions: "Cite sources", model: anthropic)
        let writer = Bot(connectionID: connection.id, name: "Writer", instructions: "Write clearly", model: openai)
        XCTAssertTrue(store.save(research)); XCTAssertTrue(store.save(writer))
        let first = try XCTUnwrap(store.enqueue("Research", for: research))
        let second = try XCTUnwrap(store.enqueue("Write", for: writer))
        research.model = openai
        XCTAssertTrue(store.save(research))
        store.configure(connections: [connection])
        try await waitUntil("both tasks finish") { store.task(first)?.state == .completed && store.task(second)?.state == .completed }
        let submissions = await client.submissions
        XCTAssertEqual(submissions.count, 2)
        XCTAssertEqual(submissions.first { $0.key == first.uuidString.lowercased() }?.model, anthropic)
        XCTAssertEqual(submissions.first { $0.key == second.uuidString.lowercased() }?.model, openai)
        XCTAssertEqual(Set(submissions.map(\.sessionID)).count, 2)
        XCTAssertTrue(submissions.allSatisfy { $0.history.isEmpty })
        store.configure(connections: [connection], active: false)
    }

    func testRestoringAcceptedTaskPollsOriginalRunWithoutResubmitting() async throws {
        let root = try temporaryRoot()
        let client = RecordingBotClient(status: "running")
        let connection = connection()
        let store = BotStore(root: root, clientFactory: { _ in client })
        store.configure(connections: [connection])
        let bot = Bot(connectionID: connection.id, name: "Builder", instructions: "Build")
        XCTAssertTrue(store.save(bot))
        let id = try XCTUnwrap(store.enqueue("Do work", for: bot))
        try await waitUntil("admitted") { store.task(id)?.runID != nil }
        let originalRun = store.task(id)?.runID
        store.configure(connections: [connection], active: false)
        await client.setStatus("completed")
        let restored = BotStore(root: root, clientFactory: { _ in client })
        XCTAssertEqual(restored.task(id)?.runID, originalRun)
        restored.configure(connections: [connection])
        try await waitUntil("recovered") { restored.task(id)?.state == .completed }
        let submissions = await client.submissions
        XCTAssertEqual(submissions.count, 1)
        restored.configure(connections: [connection], active: false)
    }

    func testStopFailureRetainsCheckpointAndRetriesAfterRestore() async throws {
        let root = try temporaryRoot()
        let client = RecordingBotClient(status: "running")
        await client.setStopFails(true)
        let connection = connection()
        let store = BotStore(root: root, clientFactory: { _ in client })
        store.configure(connections: [connection])
        let bot = Bot(connectionID: connection.id, name: "Worker", instructions: "Work")
        XCTAssertTrue(store.save(bot))
        let id = try XCTUnwrap(store.enqueue("Task", for: bot))
        try await waitUntil("admitted") { store.task(id)?.runID != nil }
        store.stop(id)
        try await waitUntil("failed stop attempted") { await client.stopCalls > 0 }
        XCTAssertEqual(store.task(id)?.state, .stopping)
        XCTAssertNotNil(store.task(id)?.runID)
        store.configure(connections: [connection], active: false)
        let restored = BotStore(root: root, clientFactory: { _ in client })
        XCTAssertEqual(restored.task(id)?.stopRequested, true)
        await client.setStopFails(false)
        restored.configure(connections: [connection])
        try await waitUntil("server confirmed cancellation") { restored.task(id)?.state == .cancelled }
        let submissions = await client.submissions
        XCTAssertEqual(submissions.count, 1)
        restored.configure(connections: [connection], active: false)
    }

    func testApprovalTargetsOnlyItsBotAndExactRequest() async throws {
        let client = RecordingBotClient(status: "waiting_for_approval")
        let store = BotStore(root: try temporaryRoot(), clientFactory: { _ in client })
        let connection = connection()
        store.configure(connections: [connection])
        let a = Bot(connectionID: connection.id, name: "A", instructions: "A")
        let b = Bot(connectionID: connection.id, name: "B", instructions: "B")
        XCTAssertTrue(store.save(a)); XCTAssertTrue(store.save(b))
        let first = try XCTUnwrap(store.enqueue("Task A", for: a))
        let second = try XCTUnwrap(store.enqueue("Task B", for: b))
        try await waitUntil("both approvals") { store.task(first)?.approval != nil && store.task(second)?.approval != nil }
        let approvalA = try XCTUnwrap(store.task(first)?.approval)
        let approvalB = try XCTUnwrap(store.task(second)?.approval)
        await store.approve(first, choice: "always") // Not offered by the server.
        let rejected = await client.approvals
        XCTAssertTrue(rejected.isEmpty)
        await store.approve(first, choice: "once")
        let approvals = await client.approvals
        XCTAssertEqual(approvals.count, 1)
        XCTAssertEqual(approvals.first?.runID, approvalA.runID)
        XCTAssertEqual(approvals.first?.requestID, approvalA.requestID)
        XCTAssertEqual(store.task(second)?.approval, approvalB)
        store.configure(connections: [connection], active: false)
    }

    func testTasksForSameBotAreSerialized() async throws {
        let client = RecordingBotClient(status: "running")
        let connection = connection()
        let store = BotStore(root: try temporaryRoot(), clientFactory: { _ in client })
        store.configure(connections: [connection])
        let bot = Bot(connectionID: connection.id, name: "Worker", instructions: "Work")
        XCTAssertTrue(store.save(bot))
        let first = try XCTUnwrap(store.enqueue("First", for: bot))
        let second = try XCTUnwrap(store.enqueue("Second", for: bot))
        try await waitUntil("first admission") { store.task(first)?.runID != nil }
        var submissions = await client.submissions
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(store.task(second)?.state, .queued)
        await client.setStatus("completed")
        try await waitUntil("queue drained") { store.task(second)?.state == .completed }
        submissions = await client.submissions
        XCTAssertEqual(submissions.map(\.key), [first, second].map { $0.uuidString.lowercased() })
        XCTAssertEqual(submissions[0].sessionID, submissions[1].sessionID)
        store.configure(connections: [connection], active: false)
    }

    func testRemovedConnectionExposesRecoveryAndDoesNotMoveTask() throws {
        let connection = connection()
        let store = BotStore(root: try temporaryRoot())
        store.configure(connections: [connection], active: false)
        let bot = Bot(connectionID: connection.id, name: "Worker", instructions: "Work")
        XCTAssertTrue(store.save(bot))
        let id = try XCTUnwrap(store.enqueue("Task", for: bot))
        store.configure(connections: [])
        XCTAssertEqual(store.task(id)?.state, .needsAttention)
        XCTAssertEqual(store.task(id)?.connectionID, connection.id)
        store.forget(id)
        XCTAssertNil(store.task(id))
    }

    func testStopUnsubmittedTaskDoesNotStartRemoteWork() throws {
        let connection = connection()
        let store = BotStore(root: try temporaryRoot())
        store.configure(connections: [connection], active: false)
        let bot = Bot(connectionID: connection.id, name: "Worker", instructions: "Work")
        XCTAssertTrue(store.save(bot))
        let id = try XCTUnwrap(store.enqueue("Task", for: bot))
        store.stop(id)
        XCTAssertEqual(store.task(id)?.state, .cancelled)
        XCTAssertNil(store.task(id)?.firstSubmissionAt)
    }

    func testExpiredAdmissionIsNotReplayed() throws {
        let bot = Bot(connectionID: UUID(), name: "Worker", instructions: "Work")
        var task = BotTask(bot: bot, request: "Task")
        task.firstSubmissionAt = Date().addingTimeInterval(-90_000)
        task.retentionSeconds = 86_400
        XCTAssertFalse(task.mayRetrySubmission)
        task.firstSubmissionAt = .now
        XCTAssertTrue(task.mayRetrySubmission)
    }

    func testFailedProviderResponseKeepsServerExplanation() async throws {
        let client = RecordingBotClient(status: "failed")
        let connection = connection()
        let store = BotStore(root: try temporaryRoot(), clientFactory: { _ in client })
        store.configure(connections: [connection])
        let bot = Bot(connectionID: connection.id, name: "Writer", instructions: "Write")
        XCTAssertTrue(store.save(bot))
        let id = try XCTUnwrap(store.enqueue("Write a note", for: bot))
        try await waitUntil("failure surfaced") { store.task(id)?.state == .failed }
        XCTAssertEqual(store.task(id)?.output, "Sign in to the model service on Studio.")
        store.configure(connections: [connection], active: false)
    }

    func testChatSwitchClearsOldApproval() throws {
        let suite = "review-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let connection = connection()
        let storage = ConnectionStore(defaults: defaults)
        storage.save([connection], selectedID: connection.id)
        let model = AppModel(store: storage)
        model.pendingApproval = RunApproval(runID: "old", command: "old", choices: ["once"])
        model.newConversation()
        XCTAssertNil(model.pendingApproval)
    }

    func testPolicyPrecedesCommentedHeadAndBlocksWebKitSubresources() async throws {
        let escaped = expectation(description: "Network resource must be blocked")
        escaped.isInverted = true
        let loaded = expectation(description: "Document loaded")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let handler = BlockedResourceProbe(escaped)
        configuration.setURLSchemeHandler(handler, forURLScheme: "review")
        let web = WKWebView(frame: .zero, configuration: configuration)
        let delegate = DocumentLoadProbe(loaded)
        web.navigationDelegate = delegate
        let html = try MiniAppDocument.prepare("<!DOCTYPE html><!-- <head> --><html><head></head><body><h1>Usable</h1><script>window.tetherTest=42</script><img src='review://outside/leak'></body></html>")
        XCTAssertLessThan(try XCTUnwrap(html.range(of: "Content-Security-Policy")?.lowerBound), try XCTUnwrap(html.range(of: "<!--")?.lowerBound))
        web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let result = try await web.evaluateJavaScript("window.tetherTest")
        XCTAssertEqual(result as? Int, 42, "Inline mini-app functionality is preserved")
        await fulfillment(of: [escaped], timeout: 0.3)
        withExtendedLifetime(delegate) {}
        withExtendedLifetime(web) {}
    }
}

private actor RecordingBotClient: BotRunClient {
    struct Submission: Sendable {
        let input: String
        let sessionID: String
        let history: [ChatMessage]
        let model: ModelChoice?
        let key: String
    }
    struct Approval: Sendable { let runID: String; let requestID: String? }
    var submissions: [Submission] = []
    var approvals: [Approval] = []
    var stopCalls = 0
    private var status: String
    private var stopFails = false
    init(status: String = "completed") { self.status = status }
    func setStatus(_ value: String) { status = value }
    func setStopFails(_ value: Bool) { stopFails = value }
    func requireDurableRuns() async throws -> TimeInterval { 86_400 }
    func createRun(input: String, sessionID: String, history: [ChatMessage], modelChoice: ModelChoice?, idempotencyKey: String) async throws -> RunSubmission {
        submissions.append(Submission(input: input, sessionID: sessionID, history: history, model: modelChoice, key: idempotencyKey))
        return RunSubmission(runID: "run-" + idempotencyKey, status: "running", replayed: false)
    }
    func runStatus(_ runID: String) async throws -> RunStatus {
        let approval: HermesRunEvent? = status == "waiting_for_approval" ? try JSONDecoder().decode(HermesRunEvent.self, from: JSONSerialization.data(withJSONObject: ["event":"approval.required", "command":"Action", "choices":["once","deny"], "request_id":"request-"+runID])) : nil
        return RunStatus(runID: runID, status: status, output: status == "completed" ? "Finished" : (status == "failed" ? "Sign in to the model service on Studio." : nil), error: nil, approval: approval)
    }
    nonisolated func runEvents(_ runID: String) -> AsyncThrowingStream<HermesRunEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func stopRun(_ runID: String) async throws {
        stopCalls += 1
        if stopFails { throw URLError(.networkConnectionLost) }
        status = "cancelled"
    }
    func resolveApproval(_ runID: String, choice: String, requestID: String?) async throws {
        approvals.append(Approval(runID: runID, requestID: requestID))
    }
    func steerRun(_ runID: String, input: String) async throws {}
}

@MainActor
private final class BlockedResourceProbe: NSObject, WKURLSchemeHandler {
    let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        expectation.fulfill()
        urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
private final class DocumentLoadProbe: NSObject, WKNavigationDelegate {
    let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { expectation.fulfill() }
}
