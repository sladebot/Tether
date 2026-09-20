import XCTest
@testable import Tether

final class TetherTests: XCTestCase {
    func testFeatureReportDistinguishesFlagsFromMetadataAndClientCoverage() throws {
        let json = #"{"platform":"hermes-agent","features":{"audio_api":false,"run_stop":true,"runs_idempotency":{"supported":true,"durable":true,"retention_seconds":86400},"browser_extension_control":{"enabled":false,"capabilities":[]},"future_flag":"unknown","numeric":1}}"#
        let report = try JSONDecoder().decode(HermesFeatureReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.features["audio_api"]?.availability, .unavailable)
        XCTAssertEqual(report.features["run_stop"]?.availability, .available)
        XCTAssertEqual(report.features["runs_idempotency"]?.availability, .available)
        XCTAssertEqual(report.features["browser_extension_control"]?.availability, .unavailable)
        XCTAssertEqual(report.features["future_flag"]?.availability, .unknown)
        XCTAssertEqual(report.features["numeric"]?.availability, .unknown)
        XCTAssertTrue(HermesFeatureReport.appSupport(for: "session_fork").hasPrefix("Gap:"))
        XCTAssertEqual(HermesFeatureReport.appSupport(for: "future_flag"), "No native Tether interface verified")
    }

    func testDebugBootstrapReusesMatchingAPIServerAndPreservesConnections() throws {
        let studio = AgentConnection(
            name: "Studio", baseURL: "https://studio.example.ts.net:8445",
            route: .tailscale, transport: .apiServer
        )
        let sandbox = AgentConnection(
            name: "Existing VM", baseURL: "https://sandbox.example.ts.net",
            route: .tailscale, transport: .apiServer
        )
        let saved = [studio, sandbox]

        let result = try XCTUnwrap(DebugConnectionBootstrap.apply(
            to: saved,
            url: "  https://sandbox.example.ts.net/v1/ ",
            token: "development-token"
        ))

        XCTAssertEqual(result.connections, saved)
        XCTAssertEqual(result.selectedConnectionID, sandbox.id)
        XCTAssertEqual(result.credentialConnection, sandbox)
    }

    func testDebugBootstrapAppendsSeparateSandboxWithoutChangingSavedProfiles() throws {
        let studio = AgentConnection(
            name: "Studio", baseURL: "https://studio.example.ts.net:8445",
            route: .tailscale, transport: .apiServer
        )

        let result = try XCTUnwrap(DebugConnectionBootstrap.apply(
            to: [studio],
            url: "sandbox.example.ts.net",
            token: "development-token"
        ))

        XCTAssertEqual(result.connections.count, 2)
        XCTAssertEqual(result.connections.first, studio)
        let sandbox = try XCTUnwrap(result.connections.last)
        XCTAssertEqual(sandbox.name, "Hermes Sandbox")
        XCTAssertEqual(sandbox.route, .tailscale)
        XCTAssertEqual(sandbox.transport, .apiServer)
        XCTAssertEqual(sandbox.normalizedBaseURL?.absoluteString, "https://sandbox.example.ts.net")
        XCTAssertEqual(result.selectedConnectionID, sandbox.id)
        XCTAssertEqual(result.credentialConnection, sandbox)

        let repeated = try XCTUnwrap(DebugConnectionBootstrap.apply(
            to: result.connections,
            url: "https://sandbox.example.ts.net/",
            token: "replacement-token"
        ))
        XCTAssertEqual(repeated.connections, result.connections)
        XCTAssertEqual(repeated.selectedConnectionID, sandbox.id)
    }

    func testDebugBootstrapDoesNotReuseDashboardCredentialOrAcceptInvalidInput() throws {
        let dashboard = AgentConnection(
            name: "Dashboard", baseURL: "https://sandbox.example.ts.net",
            route: .tailscale, transport: .dashboard
        )

        let result = try XCTUnwrap(DebugConnectionBootstrap.apply(
            to: [dashboard],
            url: "https://sandbox.example.ts.net",
            token: "development-token"
        ))
        XCTAssertEqual(result.connections.count, 2)
        XCTAssertEqual(result.connections.first, dashboard)
        XCTAssertEqual(result.credentialConnection.transport, .apiServer)
        XCTAssertNotEqual(result.credentialConnection.id, dashboard.id)

        XCTAssertNil(DebugConnectionBootstrap.apply(to: [dashboard], url: "not a URL", token: "token"))
        XCTAssertNil(DebugConnectionBootstrap.apply(to: [dashboard], url: "https://sandbox.example.ts.net", token: "  "))
    }

    func testSavedRunFailureDistinguishesTerminalServerResponseFromRetryableNetworkError() {
        for status in [404, 409, 410] {
            let message = AppModel.savedRunFailureMessage(HermesAPIClient.ClientError.server(status: status, message: "server detail"))
            XCTAssertNotNil(message)
            XCTAssertTrue(message?.contains("No replacement run was started") == true)
        }
        for status in [401, 403, 408, 429, 500, 502, 503] {
            XCTAssertNil(AppModel.savedRunFailureMessage(HermesAPIClient.ClientError.server(status: status, message: "temporary or auth")))
        }
        XCTAssertNil(AppModel.savedRunFailureMessage(URLError(.networkConnectionLost)))
        XCTAssertNil(AppModel.savedRunFailureMessage(CancellationError()))
        XCTAssertNotNil(AppModel.savedRunFailureMessage(HermesAPIClient.ClientError.durableRunsUnavailable("not durable")))
        XCTAssertNotNil(AppModel.savedRunFailureMessage(HermesAPIClient.ClientError.notHermesAPIServer))
        XCTAssertNotNil(AppModel.savedRunFailureMessage(HermesAPIClient.ClientError.invalidURL))
    }

    func testPausedMiniAppJobKeepsOriginalRunIdentityAcrossRelaunch() throws {
        let choice = ModelChoice(provider: "custom", providerName: "VM", model: "saved-model")
        var job = MiniAppBuildJob(connectionID: UUID(), title: "Saved app", prompt: "Keep this request", model: choice)
        job.runID = "original-run"
        job.targetAppID = UUID()
        job.failureMessage = "Hermes cannot find this saved run."
        let encoded = try JSONEncoder().encode(job)
        let restored = try JSONDecoder().decode(MiniAppBuildJob.self, from: encoded)
        XCTAssertEqual(restored.id, job.id)
        XCTAssertEqual(restored.connectionID, job.connectionID)
        XCTAssertEqual(restored.runID, job.runID)
        XCTAssertEqual(restored.targetAppID, job.targetAppID)
        XCTAssertEqual(restored.failureMessage, job.failureMessage)
        XCTAssertEqual(restored.model, choice)
        XCTAssertEqual(restored.prompt, job.prompt)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "failureMessage")
        let legacyJob = try JSONDecoder().decode(MiniAppBuildJob.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(legacyJob.failureMessage)
        XCTAssertEqual(legacyJob.runID, job.runID)
    }

    func testEquivalentServerEditPreservesConnectionIdentity() {
        let original = AgentConnection(name: "Studio", baseURL: "https://studio.example.ts.net", route: .tailscale)
        var edited = original
        edited.name = "Renamed"
        edited.baseURL = " studio.example.ts.net/v1/ "
        let saved = edited.preservingServerIdentity(previous: original)
        XCTAssertEqual(saved.id, original.id)
        XCTAssertEqual(saved.name, "Renamed")
        XCTAssertEqual(original.name, "Studio")
        XCTAssertEqual(original.baseURL, "https://studio.example.ts.net")
    }

    func testDifferentServerOrProtocolGetsSeparateIdentity() {
        let original = AgentConnection(name: "Studio", baseURL: "https://studio.example.ts.net", route: .tailscale)
        for changedURL in ["https://hermes-vm.example.ts.net", "https://studio.example.ts.net:8445", "http://studio.example.ts.net"] {
            var edited = original
            edited.baseURL = changedURL
            let saved = edited.preservingServerIdentity(previous: original)
            XCTAssertNotEqual(saved.id, original.id)
            XCTAssertEqual(saved.baseURL, changedURL)
        }
        var dashboard = original
        dashboard.transport = .dashboard
        XCTAssertNotEqual(dashboard.preservingServerIdentity(previous: original).id, original.id)
        XCTAssertEqual(original.transport, .apiServer)
        XCTAssertEqual(original.baseURL, "https://studio.example.ts.net")
        XCTAssertEqual(original.preservingServerIdentity(previous: nil).id, original.id)
    }

    func testPendingRunModelSnapshotSurvivesRoundTripAndLegacyDecode() throws {
        let choice = ModelChoice(provider: "custom", providerName: "VM provider", model: "queued-model")
        let pending = PendingRun(idempotencyKey: "queued-turn", runID: nil, turnID: UUID(),
            assistantMessageID: UUID(), input: "Continue later", conversationHistory: [],
            createdAt: .now, state: .submitting, modelChoice: choice)
        let encoded = try JSONEncoder().encode(pending)
        let restored = try JSONDecoder().decode(PendingRun.self, from: encoded)
        XCTAssertEqual(restored, pending)
        XCTAssertEqual(restored.modelChoice, choice)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "modelChoice")
        let legacyRun = try JSONDecoder().decode(PendingRun.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(legacyRun.modelChoice)
        XCTAssertEqual(legacyRun.idempotencyKey, pending.idempotencyKey)
        XCTAssertEqual(legacyRun.input, pending.input)
    }

    @MainActor
    func testMiniAppUpdatePreservesIdentityChatAndRollback() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let store = MiniAppStore(root: root)
        let app = try store.save(title: "Counter", html: "<html>original</html>")
        let message = ChatMessage(role: .user, content: "Add reset")
        try store.appendChat(message, for: app)
        try store.appendChat(message, for: app)
        let updated = try store.save(title: app.title, html: "<html>updated</html>", id: app.id)
        XCTAssertEqual(updated.createdAt, app.createdAt)
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.chat(for: app).count, 1)
        // Replaying a completed job must not overwrite the rollback snapshot.
        _ = try store.save(title: app.title, html: "<html>updated</html>", id: app.id)
        try store.rollback(app)
        XCTAssertEqual(try String(contentsOf: store.htmlURL(for: app), encoding: .utf8), "<html>original</html>")
    }

    func testUpdateJobPersistsTarget() throws {
        var job = MiniAppBuildJob(connectionID: UUID(), title: "Counter", prompt: "Edit", model: nil)
        job.targetAppID = UUID()
        let restored = try JSONDecoder().decode(MiniAppBuildJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.targetAppID, job.targetAppID)
        XCTAssertNotEqual(restored.id, restored.targetAppID)
    }

    func testTailscaleHostnameGetsHTTPS() {
        let connection = AgentConnection(name: "Studio", baseURL: "studio.example.ts.net:8445", route: .tailscale)
        XCTAssertEqual(connection.normalizedBaseURL?.absoluteString, "https://studio.example.ts.net:8445")
    }

    func testConnectionRejectsCredentialsAndMissingHostInURL() {
        for address in ["http:///", "https://user:secret@example.com", "https://example.com?token=secret", "https://example.com#fragment"] {
            XCTAssertNil(AgentConnection(name: "Test", baseURL: address, route: .tailscale).normalizedBaseURL)
        }
    }

    func testDiagnosticSessionDoesNotWaitIndefinitelyForConnectivity() {
        let configuration = HermesAPIClient.diagnosticSession.configuration
        XCTAssertFalse(configuration.waitsForConnectivity)
        XCTAssertEqual(configuration.timeoutIntervalForResource, 12)
    }

    func testMiniAppJobPreservesResumeIdentity() throws {
        var job = MiniAppBuildJob(connectionID: UUID(), title: "Counter", prompt: "Build a counter", model: nil)
        job.runID = "run-resume-test"
        let restored = try JSONDecoder().decode(MiniAppBuildJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.id, job.id)
        XCTAssertEqual(restored.runID, job.runID)
        XCTAssertEqual(restored.connectionID, job.connectionID)
        XCTAssertEqual(restored.prompt, job.prompt)
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testNormalizesBaseURLAndV1Suffix() {
        let connection = AgentConnection(name: "Test", baseURL: " http://192.168.1.5:8642/v1/ ", route: .local)
        XCTAssertEqual(connection.endpoint("v1/models")?.absoluteString, "http://192.168.1.5:8642/v1/models")
    }

    func testRejectsUnsupportedSchemes() {
        let connection = AgentConnection(name: "Test", baseURL: "ftp://example.com", route: .tailscale)
        XCTAssertNil(connection.normalizedBaseURL)
    }

    func testDecodesStreamingContent() {
        let line = #"data: {"choices":[{"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(SSEDecoder.content(from: line), "Hello")
        XCTAssertNil(SSEDecoder.content(from: "data: [DONE]"))
    }

    func testKeepsDiscoveredModelOnConnection() throws {
        let original = AgentConnection(name: "Studio", baseURL: "https://studio.example.ts.net", route: .tailscale, modelName: "work-profile")
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(AgentConnection.self, from: data).modelName, "work-profile")
    }

    func testDashboardTransportRoundTrips() throws {
        let original = AgentConnection(name: "Hermes", baseURL: "https://hermes.example.ts.net", route: .tailscale, transport: .dashboard)
        let decoded = try JSONDecoder().decode(AgentConnection.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.transport, .dashboard)
    }

    func testAPIServerTransportRoundTrips() throws {
        let original = AgentConnection(name: "Hermes", baseURL: "https://hermes.example.ts.net", route: .tailscale, transport: .apiServer)
        let decoded = try JSONDecoder().decode(AgentConnection.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.transport, .apiServer)
    }

    func testLegacyOpenAITransportMigratesToAPIServer() throws {
        let id = UUID()
        let legacy = #"{"id":"\#(id.uuidString)","name":"Hermes","baseURL":"http://127.0.0.1:8642","route":"Local network","transport":"OpenAI-compatible API"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AgentConnection.self, from: legacy).transport, .apiServer)
    }

    func testAPIServerCredentialCarriesExactOrigin() throws {
        let original = APIServerCredential(origin: "https://studio.example.ts.net", apiKey: "secret")
        let decoded = try JSONDecoder().decode(APIServerCredential.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testAPIServerHandshakeAuthenticatesAndDiscoversModel() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body: String
            switch request.url?.path {
            case "/v1/capabilities":
                body = #"{"platform":"hermes-agent","auth":{"type":"bearer","required":true},"features":{"run_submission":true,"run_status":true,"run_events_sse":true,"run_stop":true,"runs_idempotency":{"supported":true,"durable":true,"retention_seconds":86400}}}"#
            case "/v1/models":
                body = #"{"data":[{"id":"hermes-agent"}]}"#
            default:
                XCTFail("Unexpected path: \(request.url?.path ?? "nil")")
                body = #"{"detail":"not found"}"#
            }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let connection = AgentConnection(
            name: "Hermes", baseURL: "https://studio.example.ts.net",
            route: .tailscale, transport: .apiServer
        )

        let model = try await HermesAPIClient(
            connection: connection, apiKey: "test-key", session: session
        ).testConnection()

        XCTAssertEqual(model, "hermes-agent")
    }

    func testHandshakeRejectsIncompleteDurableRunCapabilitiesBeforeModelDiscovery() async throws {
        let valid: [String: Any] = [
            "run_submission": true, "run_status": true, "run_events_sse": true, "run_stop": true,
            "runs_idempotency": ["supported": true, "durable": true, "retention_seconds": 86400]
        ]
        var invalid: [[String: Any]] = [[:]]
        for flag in ["run_submission", "run_status", "run_events_sse", "run_stop"] {
            var missing = valid
            missing.removeValue(forKey: flag)
            invalid.append(missing)
            var disabled = valid
            disabled[flag] = false
            invalid.append(disabled)
        }
        for idempotency: [String: Any] in [[:], ["supported": false, "durable": true, "retention_seconds": 86400],
            ["supported": true, "durable": false, "retention_seconds": 86400],
            ["supported": true, "durable": true, "retention_seconds": 0],
            ["supported": true, "durable": true, "retention_seconds": -1]] {
            var features = valid
            features["runs_idempotency"] = idempotency
            invalid.append(features)
        }
        var missingIdempotency = valid
        missingIdempotency.removeValue(forKey: "runs_idempotency")
        invalid.append(missingIdempotency)
        for features in invalid {
            let body = try JSONSerialization.data(withJSONObject: ["platform": "hermes-agent",
                "auth": ["type": "bearer", "required": true], "features": features])
            MockURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/v1/capabilities", "Must reject before models or run submission")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let client = HermesAPIClient(connection: AgentConnection(name: "VM", baseURL: "https://vm.example.ts.net", route: .tailscale),
                apiKey: "test-only", session: URLSession(configuration: configuration))
            do {
                _ = try await client.testConnection()
                XCTFail("Unsupported durability must not report readiness")
            } catch HermesAPIClient.ClientError.durableRunsUnavailable(_) {
                // Expected: positive durable-run guarantees are required.
            } catch { XCTFail("Unexpected failure: \(error)") }
        }
    }

    func testHandshakeMissingCapabilitiesDoesNotFallBackButAuthFailureStaysDistinct() async throws {
        for status in [404, 401, 403] {
            MockURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/v1/capabilities")
                return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let client = HermesAPIClient(connection: AgentConnection(name: "VM", baseURL: "https://vm.example.ts.net", route: .tailscale),
                apiKey: "test-only", session: URLSession(configuration: configuration))
            do {
                _ = try await client.testConnection()
                XCTFail("HTTP \(status) must fail readiness")
            } catch HermesAPIClient.ClientError.durableRunsUnavailable(_) {
                XCTAssertEqual(status, 404)
            } catch let HermesAPIClient.ClientError.server(code, _) {
                XCTAssertEqual(code, status)
                XCTAssertTrue([401, 403].contains(code))
            } catch { XCTFail("Unexpected failure: \(error)") }
        }
    }

    func testMalformedCapabilitiesPauseReadinessInsteadOfReportingNetworkRetry() async throws {
        for body in ["not json", #"{"platform":"hermes-agent","auth":{"type":"bearer","required":true},"features":{"run_submission":"yes"}}"#] {
            MockURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.path, "/v1/capabilities")
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            let client = HermesAPIClient(connection: AgentConnection(name: "VM", baseURL: "https://vm.example.ts.net", route: .tailscale),
                apiKey: "test-only", session: URLSession(configuration: configuration))
            do {
                try await client.requireDurableRuns()
                XCTFail("Malformed capabilities must not report readiness")
            } catch HermesAPIClient.ClientError.durableRunsUnavailable(_) {
                // Stable unsupported contract, not a reconnect loop.
            } catch { XCTFail("Unexpected failure: \(error)") }
        }
    }

    func testDiscoversOnlyAuthenticatedHermesModelOptions() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/model/options")
            let body = #"{"providers":[{"slug":"custom:omlx","name":"omlx","authenticated":true,"models":["Qwen"]},{"slug":"offline","name":"Offline","authenticated":false,"models":["Nope"]}]}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let choices = try await HermesAPIClient(
            connection: AgentConnection(name: "Hermes", baseURL: "https://host.ts.net", route: .tailscale),
            apiKey: "key", session: URLSession(configuration: configuration)
        ).modelOptions()
        XCTAssertEqual(choices, [ModelChoice(provider: "custom:omlx", providerName: "omlx", model: "Qwen")])
    }

    func testRunSubmissionUsesIdempotencySessionAndModelRouting() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/runs")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "turn-1")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Hermes-Session-Id"), "chat-1")
            let body = #"{"run_id":"run_1","status":"started","replayed":false}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let submission = try await HermesAPIClient(
            connection: AgentConnection(name: "Hermes", baseURL: "https://host.ts.net", route: .tailscale),
            apiKey: "key", session: URLSession(configuration: configuration)
        ).createRun(
            input: "Hello", sessionID: "chat-1", history: [],
            modelChoice: ModelChoice(provider: "custom:omlx", providerName: "omlx", model: "Qwen"),
            idempotencyKey: "turn-1"
        )
        XCTAssertEqual(submission.runID, "run_1")
    }

    func testSteeringAuthenticatesAndUsesActiveRunEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/runs/run_1/steer")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
            let body = #"{"run_id":"run_1","accepted":true}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        try await HermesAPIClient(
            connection: AgentConnection(name: "Hermes", baseURL: "https://host.ts.net", route: .tailscale),
            apiKey: "key", session: URLSession(configuration: configuration)
        ).steerRun("run_1", input: "Keep the answer concise")
    }

    func testSteeringCompletedRunSurfacesConflict() async throws {
        MockURLProtocol.handler = { request in
            let body = #"{"error":{"message":"Run is not currently accepting steer input","code":"run_not_accepting_steer"}}"#
            return (HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        do {
            try await HermesAPIClient(
                connection: AgentConnection(name: "Hermes", baseURL: "https://host.ts.net", route: .tailscale),
                apiKey: "key", session: URLSession(configuration: configuration)
            ).steerRun("run_1", input: "Keep the answer concise")
            XCTFail("Completed runs must not acknowledge steering")
        } catch HermesAPIClient.ClientError.server(let status, _) {
            XCTAssertEqual(status, 409)
        }
    }

    func testToolCompletionEventAcceptsBooleanErrorField() throws {
        let data = #"{"event":"tool.completed","timestamp":1,"tool":"terminal","duration":0.12,"error":false}"#.data(using: .utf8)!
        let event = try JSONDecoder().decode(HermesRunEvent.self, from: data)
        XCTAssertEqual(event.tool, "terminal")
        XCTAssertEqual(event.durationSeconds, 0.12)
        XCTAssertNil(event.error)
    }

    func testPollingRecoversApprovalAfterStreamDisconnect() throws {
        let data = #"{"run_id":"run_1","status":"waiting_for_approval","approval":{"event":"approval.request","request_id":"approval_1","command":"Confirm command","choices":["once","deny"]}}"#.data(using: .utf8)!
        let status = try JSONDecoder().decode(RunStatus.self, from: data)
        XCTAssertEqual(status.status, "waiting_for_approval")
        XCTAssertEqual(status.approval?.requestID, "approval_1")
        XCTAssertEqual(status.approval?.choices, ["once", "deny"])
        XCTAssertEqual(status.approval?.command, "Confirm command")
    }

    func testApprovalEventCarriesServerChoices() throws {
        let data = #"{"event":"approval.request","timestamp":1,"command":"redacted command","choices":["once","deny"]}"#.data(using: .utf8)!
        let event = try JSONDecoder().decode(HermesRunEvent.self, from: data)
        XCTAssertEqual(event.command, "redacted command")
        XCTAssertEqual(event.choices, ["once", "deny"])
    }

    func testDashboardTokensRoundTrip() throws {
        let original = DashboardTokens(
            origin: "http://10.0.0.151:9119",
            accessToken: "access",
            refreshToken: "refresh",
            provider: "basic",
            expiresAt: 123456
        )
        let decoded = try JSONDecoder().decode(DashboardTokens.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testLegacyPort9119ConnectionMigratesToDashboardTransport() throws {
        let id = UUID()
        let legacy = #"{"id":"\#(id.uuidString)","name":"Hermes","baseURL":"http://127.0.0.1:9119","route":"Local network"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AgentConnection.self, from: legacy).transport, .dashboard)
    }

    func testPreparesFencedMiniAppAndInjectsIsolationPolicy() throws {
        let response = """
        ```html
        <!DOCTYPE html><html><head><title>Counter</title></head><body><button>0</button></body></html>
        ```
        """
        let html = try MiniAppDocument.prepare(response)
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }

    func testRejectsIncompleteMiniApp() {
        XCTAssertThrowsError(try MiniAppDocument.prepare("<div>Not a document</div>"))
    }

    func testHarnessPolicyIsAddedEvenWhenDocumentProvidesCSP() throws {
        let source = #"<html><head><meta http-equiv="Content-Security-Policy" content="default-src *"></head><body></body></html>"#
        let html = try MiniAppDocument.prepare(source)
        XCTAssertEqual(html.components(separatedBy: "Content-Security-Policy").count - 1, 2)
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.badServerResponse)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
