import Foundation

struct HermesAPIClient: Sendable {
    enum ClientError: LocalizedError {
        case invalidURL
        case invalidResponse
        case notHermesAPIServer
        case server(status: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter a valid HTTP or HTTPS address."
            case .invalidResponse: "Hermes returned an unreadable response."
            case .notHermesAPIServer: "This endpoint does not identify itself as a Hermes API Server. Check that Tailscale Serve forwards to port 8642."
            case let .server(status, message): message.isEmpty ? "Hermes returned HTTP \(status)." : message
            }
        }
    }

    private let connection: AgentConnection
    private let apiKey: String
    private let session: URLSession

    init(connection: AgentConnection, apiKey: String, session: URLSession = .shared) {
        self.connection = connection
        self.apiKey = apiKey
        self.session = session
    }

    func testConnection() async throws -> String {
        if connection.transport == .dashboard {
            return try await HermesDashboardClient(connection: connection, accessToken: apiKey, session: session).testConnection()
        }
        do {
            let capabilities = try await capabilities()
            guard capabilities.platform == "hermes-agent",
                  capabilities.auth.type == "bearer",
                  capabilities.auth.required else {
                throw ClientError.notHermesAPIServer
            }
        } catch let ClientError.server(status, _) where status == 404 {
            // Older Hermes API Server builds predate capability discovery.
        }
        let availableModels = try await models()
        guard let model = availableModels.first else { throw ClientError.invalidResponse }
        return model
    }

    func models() async throws -> [String] {
        guard let url = connection.endpoint("v1/models") else { throw ClientError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 12
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let envelope = try? JSONDecoder().decode(ModelsEnvelope.self, from: data) else {
            throw ClientError.invalidResponse
        }
        return envelope.data.map(\.id)
    }

    private func capabilities() async throws -> APIServerCapabilities {
        guard let url = connection.endpoint("v1/capabilities") else { throw ClientError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 12
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        authorize(&request)
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        guard let value = try? JSONDecoder().decode(APIServerCapabilities.self, from: data) else {
            throw ClientError.invalidResponse
        }
        return value
    }

    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        if connection.transport == .dashboard {
            return HermesDashboardClient(connection: connection, accessToken: apiKey, session: session).stream(messages: messages)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = connection.endpoint("v1/chat/completions") else {
                        throw ClientError.invalidURL
                    }
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 600
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    authorize(&request)
                    let model: String
                    if let configuredModel = connection.modelName {
                        model = configuredModel
                    } else {
                        model = try await models().first ?? "hermes-agent"
                    }
                    request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: messages.map {
                        .init(role: $0.role.rawValue, content: $0.content)
                    }))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines { body += line }
                        throw ClientError.server(status: http.statusCode, message: Self.errorMessage(from: Data(body.utf8)))
                    }
                    for try await line in bytes.lines {
                        guard let piece = SSEDecoder.content(from: line) else { continue }
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.server(status: http.statusCode, message: Self.errorMessage(from: data))
        }
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let detail = object["detail"] as? String { return detail }
        if let error = object["error"] as? String { return error }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return ""
    }
}

private struct HermesDashboardClient: Sendable {
    enum DashboardError: LocalizedError {
        case invalidURL
        case invalidBootstrap
        case invalidResponse
        case loginRequired
        case passwordAuthUnavailable
        case server(Int, String)
        case timedOut

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Enter a valid Hermes dashboard HTTP or HTTPS address."
            case .invalidBootstrap: "Hermes did not provide a dashboard session token."
            case .invalidResponse: "Hermes returned an unreadable dashboard response."
            case .loginRequired: "Hermes requires sign-in. Enter the dashboard username and password."
            case .passwordAuthUnavailable: "This Hermes dashboard does not advertise username/password authentication."
            case let .server(status, message): message.isEmpty ? "Hermes dashboard returned HTTP \(status)." : message
            case .timedOut: "Hermes did not finish the response in time."
            }
        }
    }

    private let connection: AgentConnection
    private let accessToken: String
    private let session: URLSession
    private let tokenStore: DashboardTokenStore
    private let profile = "default"

    init(connection: AgentConnection, accessToken: String, session: URLSession, tokenStore: DashboardTokenStore = DashboardTokenStore()) {
        self.connection = connection
        self.accessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
        self.tokenStore = tokenStore
    }

    func testConnection() async throws -> String {
        let auth = try await authenticate()
        let data = try await get("api/model/info", auth: auth, query: [.init(name: "profile", value: profile)])
        let info = try JSONDecoder().decode(ModelInfo.self, from: data)
        return info.model ?? "Hermes Dashboard"
    }

    func stream(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var rpcSocket: URLSessionWebSocketTask?
                var terminalSocket: URLSessionWebSocketTask?
                var rpcDrain: Task<Void, Never>?
                var terminalDrain: Task<Void, Never>?
                defer {
                    rpcDrain?.cancel()
                    terminalDrain?.cancel()
                    rpcSocket?.cancel(with: .normalClosure, reason: nil)
                    terminalSocket?.cancel(with: .normalClosure, reason: nil)
                }

                do {
                    let auth = try await authenticate()
                    let baseline = try await sessionIDs(auth: auth)
                    let submittedPrompt = Self.prompt(from: messages)

                    let rpc = try await webSocket(path: "api/ws", auth: auth)
                    rpcSocket = rpc
                    rpc.resume()
                    try await rpc.send(.string(Self.createSessionRequest(profile: profile)))
                    rpcDrain = drain(rpc)

                    let terminal = try await webSocket(path: "api/pty", auth: auth, query: [
                        .init(name: "channel", value: "chat-fresh-\(UUID().uuidString.lowercased())"),
                        .init(name: "fresh", value: "1"),
                        .init(name: "attach", value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
                        .init(name: "profile", value: profile)
                    ])
                    terminalSocket = terminal
                    terminal.resume()
                    terminalDrain = drain(terminal)
                    try await terminal.send(.string("\u{1b}[RESIZE:100;40]"))
                    try await Task.sleep(for: .seconds(7))
                    try Task.checkCancellation()
                    try await terminal.send(.string(submittedPrompt))
                    try await Task.sleep(for: .milliseconds(150))
                    try await terminal.send(.string("\r"))

                    for _ in 0..<360 {
                        try Task.checkCancellation()
                        let sessions = try await recentSessions(auth: auth)
                        let candidates = sessions.filter { !baseline.contains($0.id) }
                        for candidate in candidates {
                            let transcript = try await dashboardMessages(sessionID: candidate.id, auth: auth)
                            guard transcript.contains(where: { $0.role == "user" && $0.content == submittedPrompt }) else { continue }
                            if let reply = transcript.last(where: { $0.role == "assistant" && !$0.content.isEmpty && $0.finishReason != nil }) {
                                continuation.yield(reply.content)
                                continuation.finish()
                                return
                            }
                        }
                        try await Task.sleep(for: .milliseconds(500))
                    }
                    throw DashboardError.timedOut
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private enum Authentication: Sendable {
        case loopbackToken(String)
        case bearer(String)
        case sessionCookie
    }

    private func authenticate() async throws -> Authentication {
        let statusData = try await publicGet("api/status")
        let status = try JSONDecoder().decode(DashboardStatus.self, from: statusData)
        if status.authRequired {
            guard status.authProviders.contains(where: { $0 == "basic" }) else {
                throw DashboardError.passwordAuthUnavailable
            }
            let origin = connection.normalizedBaseURL?.absoluteString ?? ""
            if let stored = tokenStore.load(for: connection.id), stored.origin == origin {
                if stored.expiresAt > Int(Date().timeIntervalSince1970) + 30 {
                    do {
                        _ = try await get("api/auth/me", auth: .bearer(stored.accessToken))
                        return .bearer(stored.accessToken)
                    } catch let DashboardError.server(status, _) where status == 401 {
                        // Continue to the refresh-token path.
                    }
                }
                if !stored.refreshToken.isEmpty {
                    do {
                        let refreshed = try await refresh(stored)
                        try tokenStore.save(refreshed, for: connection.id)
                        return .bearer(refreshed.accessToken)
                    } catch let DashboardError.server(status, _) where status == 400 || status == 401 {
                        tokenStore.remove(for: connection.id)
                    }
                }
            } else {
                tokenStore.remove(for: connection.id)
            }
            let username = connection.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !username.isEmpty, !accessToken.isEmpty else { throw DashboardError.loginRequired }
            if let issued = try await passwordLogin(username: username, password: accessToken) {
                _ = try await get("api/auth/me", auth: .bearer(issued.accessToken))
                try tokenStore.save(issued, for: connection.id)
                return .bearer(issued.accessToken)
            }
            _ = try await get("api/auth/me", auth: .sessionCookie)
            return .sessionCookie
        }
        return .loopbackToken(try await dashboardToken())
    }

    private func dashboardToken() async throws -> String {
        guard let url = connection.normalizedBaseURL else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 12
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        if response.url?.path == "/login" { throw DashboardError.loginRequired }
        let html = String(decoding: data, as: UTF8.self)
        let pattern = #"__HERMES_SESSION_TOKEN__\s*=\s*['\"]([^'\"]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else {
            throw DashboardError.invalidBootstrap
        }
        return String(html[range])
    }

    private func passwordLogin(username: String, password: String) async throws -> DashboardTokens? {
        guard let url = connection.endpoint("auth/password-login") else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PasswordLoginRequest(
            provider: "basic", username: username, password: password, next: "/"
        ))
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let cookieStorage = session.configuration.httpCookieStorage ?? HTTPCookieStorage.shared
        let cookies = cookieStorage.cookies(for: url) ?? []
        guard let access = cookies.first(where: { $0.name.hasSuffix("hermes_session_at") }) else {
            return nil
        }
        let refresh = cookies.first(where: { $0.name.hasSuffix("hermes_session_rt") })?.value ?? ""
        let provider = cookies.first(where: { $0.name.hasSuffix("hermes_session_provider") })?.value ?? "basic"
        let expiry = Int(access.expiresDate?.timeIntervalSince1970 ?? Date().addingTimeInterval(12 * 60 * 60).timeIntervalSince1970)
        return DashboardTokens(
            origin: connection.normalizedBaseURL?.absoluteString ?? "",
            accessToken: access.value,
            refreshToken: refresh,
            provider: provider,
            expiresAt: expiry
        )
    }

    private func refresh(_ tokens: DashboardTokens) async throws -> DashboardTokens {
        guard let url = connection.endpoint("auth/native/refresh") else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RefreshRequest(
            refreshToken: tokens.refreshToken,
            provider: tokens.provider
        ))
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        let envelope = try JSONDecoder().decode(NativeTokenEnvelope.self, from: data)
        return DashboardTokens(
            origin: connection.normalizedBaseURL?.absoluteString ?? "",
            accessToken: envelope.accessToken,
            refreshToken: envelope.refreshToken,
            provider: envelope.provider,
            expiresAt: envelope.expiresAt
        )
    }

    private func publicGet(_ path: String) async throws -> Data {
        guard let url = connection.endpoint(path) else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        request.timeoutInterval = 12
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return data
    }

    private func recentSessions(auth: Authentication) async throws -> [DashboardSession] {
        let data = try await get("api/sessions", auth: auth, query: [
            .init(name: "limit", value: "20"),
            .init(name: "offset", value: "0"),
            .init(name: "order", value: "recent"),
            .init(name: "source", value: "tui"),
            .init(name: "profile", value: profile)
        ])
        return try JSONDecoder().decode(SessionsEnvelope.self, from: data).sessions
    }

    private func sessionIDs(auth: Authentication) async throws -> Set<String> {
        Set(try await recentSessions(auth: auth).map(\.id))
    }

    private func dashboardMessages(sessionID: String, auth: Authentication) async throws -> [DashboardMessage] {
        let data = try await get("api/sessions/\(sessionID)/messages", auth: auth, query: [
            .init(name: "limit", value: "500"),
            .init(name: "order", value: "latest"),
            .init(name: "profile", value: profile)
        ])
        return try JSONDecoder().decode(MessagesEnvelope.self, from: data).messages
    }

    private func get(_ path: String, auth: Authentication, query: [URLQueryItem] = []) async throws -> Data {
        guard var components = endpoint(path: path) else { throw DashboardError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        switch auth {
        case let .loopbackToken(token):
            request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        case let .bearer(token):
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .sessionCookie:
            break
        }
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return data
    }

    private func webSocket(path: String, auth: Authentication, query: [URLQueryItem] = []) async throws -> URLSessionWebSocketTask {
        guard var components = endpoint(path: path) else { throw DashboardError.invalidURL }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        let credential: URLQueryItem
        switch auth {
        case let .loopbackToken(token):
            credential = .init(name: "token", value: token)
        case .sessionCookie, .bearer:
            credential = .init(name: "ticket", value: try await webSocketTicket(auth: auth))
        }
        components.queryItems = query + [credential]
        guard let url = components.url else { throw DashboardError.invalidURL }
        return session.webSocketTask(with: url)
    }

    private func webSocketTicket(auth: Authentication) async throws -> String {
        guard let url = connection.endpoint("api/auth/ws-ticket") else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        if case let .bearer(token) = auth {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(WebSocketTicket.self, from: data).ticket
    }

    private func endpoint(path: String) -> URLComponents? {
        guard let base = connection.normalizedBaseURL else { return nil }
        return URLComponents(url: base.appending(path: path), resolvingAgainstBaseURL: false)
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw DashboardError.invalidResponse }
        if http.url?.path == "/login" { throw DashboardError.loginRequired }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(DashboardAPIError.self, from: data).detail) ?? ""
            throw DashboardError.server(http.statusCode, message)
        }
    }

    private func drain(_ socket: URLSessionWebSocketTask) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                do { _ = try await socket.receive() }
                catch { return }
            }
        }
    }

    private static func createSessionRequest(profile: String) -> String {
        #"{"jsonrpc":"2.0","id":"ios-1","method":"session.create","params":{"close_on_disconnect":true,"source":"tool","profile":"\#(profile)"}}"#
    }

    private static func prompt(from messages: [ChatMessage]) -> String {
        guard messages.count > 1 else { return messages.last?.content ?? "" }
        let transcript = messages.suffix(20).map { message in
            "\(message.role == .user ? "User" : "Hermes"): \(message.content)"
        }.joined(separator: "\n\n")
        return "Continue this conversation and respond to the latest user message.\n\n\(transcript)"
    }
}

private struct DashboardStatus: Decodable {
    let authRequired: Bool
    let authProviders: [String]

    enum CodingKeys: String, CodingKey {
        case authRequired = "auth_required"
        case authProviders = "auth_providers"
    }
}
private struct PasswordLoginRequest: Encodable {
    let provider: String
    let username: String
    let password: String
    let next: String
}
private struct RefreshRequest: Encodable {
    let refreshToken: String
    let provider: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case provider
    }
}
private struct NativeTokenEnvelope: Decodable {
    let accessToken: String
    let refreshToken: String
    let provider: String
    let expiresAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case provider
        case expiresAt = "expires_at"
    }
}
private struct WebSocketTicket: Decodable { let ticket: String }
private struct ModelInfo: Decodable { let model: String? }
private struct SessionsEnvelope: Decodable { let sessions: [DashboardSession] }
private struct DashboardSession: Decodable { let id: String }
private struct MessagesEnvelope: Decodable { let messages: [DashboardMessage] }
private struct DashboardMessage: Decodable {
    let role: String
    let content: String
    let finishReason: String?

    enum CodingKeys: String, CodingKey { case role, content; case finishReason = "finish_reason" }
}
private struct DashboardAPIError: Decodable { let detail: String }

private struct ModelsEnvelope: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct APIServerCapabilities: Decodable {
    struct Authentication: Decodable {
        let type: String
        let required: Bool
    }

    let platform: String
    let auth: Authentication
}

private struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    let model: String
    let messages: [Message]
    let stream = true
}

enum SSEDecoder {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }

    static func content(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]", let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Chunk.self, from: data).choices.first?.delta.content
    }
}
