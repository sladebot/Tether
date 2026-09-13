import XCTest
@testable import Agenty

final class AgentyTests: XCTestCase {
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
                body = #"{"platform":"hermes-agent","auth":{"type":"bearer","required":true}}"#
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

    func testToolCompletionEventAcceptsBooleanErrorField() throws {
        let data = #"{"event":"tool.completed","timestamp":1,"tool":"terminal","duration":0.12,"error":false}"#.data(using: .utf8)!
        let event = try JSONDecoder().decode(HermesRunEvent.self, from: data)
        XCTAssertEqual(event.tool, "terminal")
        XCTAssertEqual(event.durationSeconds, 0.12)
        XCTAssertNil(event.error)
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
