import Foundation
import Combine

/// Gateway identity is separate from the API token. It is never sent to another origin.
struct StudioGatewayConfiguration: Codable, Equatable {
    var id = UUID()
    let apiConnectionID: UUID
    var url: String
    var username: String
    var connection: AgentConnection {
        AgentConnection(id: id, name: "Studio bots", baseURL: url, route: .tailscale, transport: .dashboard, username: username)
    }
    var isValid: Bool {
        guard let base = connection.normalizedBaseURL else { return false }
        return base.scheme == "https" && base.host?.hasSuffix(".ts.net") == true && base.path.isEmpty
    }
}

struct StudioProfile: Identifiable, Decodable, Equatable {
    let name: String
    var displayName: String?
    var description: String?
    var model: String?
    var provider: String?
    var canonicalSession: Session?
    var id: String { name }
    var title: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? name }
    var modelLabel: String {
        guard let model, !model.isEmpty else { return "Uses Studio’s configured model" }
        return [provider, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    struct Session: Decodable, Equatable {
        let id: String
        var resolvedID: String?
        var preview: String?
        enum CodingKeys: String, CodingKey { case id, preview; case resolvedID = "resolved_id" }
    }
    enum CodingKeys: String, CodingKey {
        case name, description, model, provider
        case displayName = "display_name"
        case canonicalSession = "canonical_session"
    }
    init(name: String) { self.name = name }
}

struct StudioMessage: Identifiable, Equatable {
    let id: String
    let role: String
    let text: String
}

enum GatewayValue: Codable, Sendable {
    case object([String: GatewayValue]), array([GatewayValue]), string(String), number(Double), bool(Bool), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Double.self) { self = .number(value) }
        else if let value = try? c.decode([GatewayValue].self) { self = .array(value) }
        else { self = .object(try c.decode([String: GatewayValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case let .object(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .bool(v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> GatewayValue { if case let .object(v) = self { return v[key] ?? .null }; return .null }
    var string: String? { if case let .string(v) = self { return v }; return nil }
    var bool: Bool? { if case let .bool(v) = self { return v }; return nil }
    var array: [GatewayValue] { if case let .array(v) = self { return v }; return [] }
    var number: Double? { if case let .number(v) = self { return v }; return nil }
    func decoded<T: Decodable>(_ type: T.Type) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(self)) }
}

enum StudioGatewayError: LocalizedError {
    case response(String), invalidConnection, notSignedIn
    var errorDescription: String? {
        switch self {
        case let .response(message): message
        case .invalidConnection: "Use your Studio’s Tailscale HTTPS gateway URL."
        case .notSignedIn: "Sign in to the Studio gateway to open its bot conversations and model settings."
        }
    }
}

actor HermesStudioClient {
    let configuration: StudioGatewayConfiguration
    private let session: URLSession
    init(configuration: StudioGatewayConfiguration) {
        self.configuration = configuration
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.timeoutIntervalForResource = 35
        session = URLSession(configuration: c)
    }
    private func dashboard(password: String = "") -> HermesDashboardClient {
        HermesDashboardClient(connection: configuration.connection, accessToken: password, session: session)
    }
    func signIn(password: String) async throws {
        guard configuration.isValid else { throw StudioGatewayError.invalidConnection }
        _ = try await dashboard(password: password).gatewayRequest("api/auth/me")
    }
    func publicProfiles() async throws -> [StudioProfile] {
        guard configuration.isValid, let url = configuration.connection.endpoint("api/status") else { throw StudioGatewayError.invalidConnection }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw StudioGatewayError.response("The Studio gateway is unreachable.") }
        struct Status: Decodable { let profiles: [String] }
        return try JSONDecoder().decode(Status.self, from: data).profiles.map(StudioProfile.init)
    }
    func request(_ method: String, params: [String: GatewayValue] = [:]) async throws -> GatewayValue {
        guard configuration.isValid else { throw StudioGatewayError.invalidConnection }
        let socket = try await dashboard().gatewaySocket()
        socket.maximumMessageSize = 8 * 1024 * 1024
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        return try await withThrowingTaskGroup(of: GatewayValue.self) { group in
            group.addTask {
                // Canonical Hermes requires subscription on THIS socket before a
                // session can accept a prompt or control. A separate read is insufficient.
                if ["prompt.submit", "session.interrupt", "approval.respond"].contains(method), let sid = params["session_id"] {
                    var attach: [String: GatewayValue] = ["session_id": sid]
                    attach["profile"] = params["profile"]
                    _ = try await Self.exchange("session.resume", params: attach, socket: socket)
                }
                return try await Self.exchange(method, params: params, socket: socket)
            }
            group.addTask { try await Task.sleep(for: .seconds(30)); throw URLError(.timedOut) }
            defer { socket.cancel(with: .normalClosure, reason: nil); group.cancelAll() }
            return try await group.next()!
        }
    }
    private static func exchange(_ method: String, params: [String: GatewayValue], socket: URLSessionWebSocketTask) async throws -> GatewayValue {
        let id = UUID().uuidString
        let payload = GatewayValue.object(["jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": .object(params)])
        try await socket.send(.string(String(decoding: JSONEncoder().encode(payload), as: UTF8.self)))
        while !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data
            switch message { case let .data(d): data = d; case let .string(s): data = Data(s.utf8); @unknown default: continue }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                let frame = try JSONDecoder().decode(GatewayValue.self, from: Data(line.utf8))
                guard frame["id"].string == id else { continue }
                if let error = frame["error"]["message"].string { throw StudioGatewayError.response(error) }
                return frame["result"]
            }
        }
        throw CancellationError()
    }
    func profiles() async throws -> [StudioProfile] {
        let response = try await request("profiles.list")
        return try response["profiles"].decoded([StudioProfile].self)
    }
    func setModel(profile: String, choice: ModelChoice) async throws {
        let body = try JSONEncoder().encode(["provider": choice.provider, "model": choice.model])
        _ = try await dashboard().gatewayRequest("api/profiles/\(profile)/model", method: "PUT", body: body)
    }
    func createProfile(name: String, description: String, model: ModelChoice?) async throws -> [String] {
        var params: [String: GatewayValue] = ["name": .string(name), "description": .string(description), "no_alias": .bool(true)]
        if let model { params["model"] = .string(model.model); params["provider"] = .string(model.provider) }
        let result = try await request("profiles.create", params: params)
        var warnings = result["warnings"].array.compactMap(\.string)
        if model != nil && result["model_set"].bool != true { warnings.append("The profile was created, but Hermes did not confirm the requested model. Check its model settings before sending work.") }
        return warnings
    }
}

/// Persisted before admission so a lost reply never turns a retry into a new task.
struct StudioPendingInput: Codable, Equatable {
    let profile: String
    let sessionID: String
    let submissionID: String
    let text: String
    let createdAt: Date
    init(profile: String, sessionID: String, text: String) {
        self.profile = profile; self.sessionID = sessionID; self.text = text
        submissionID = UUID().uuidString; createdAt = .now
    }
    var parameters: [String: GatewayValue] {
        ["profile": .string(profile), "session_id": .string(sessionID), "text": .string(text), "submission_id": .string(submissionID), "queued": .bool(true)]
    }
    func isConfirmed(by receipt: GatewayValue) -> Bool {
        ["queued", "started", "terminal"].contains(receipt["status"].string ?? "") && receipt["ref"]["session_id"].string == sessionID && receipt["admission_id"].string != nil
    }
}

/// All bot identities and transcripts come from the Studio gateway. No local bot
/// catalog is used as a replacement when the server is unreachable.
@MainActor
final class HermesStudioStore: ObservableObject {
    @Published private(set) var profiles: [StudioProfile] = []
    @Published private(set) var configuration: StudioGatewayConfiguration?
    @Published private(set) var authenticated = false
    @Published private(set) var loading = false
    @Published var error: String?
    @Published private(set) var messages: [StudioMessage] = []
    @Published private(set) var running = false
    @Published private(set) var sessionID: String?
    @Published private(set) var selectedProfile: String?
    @Published private(set) var pendingApprovals: [GatewayValue] = []
    @Published private(set) var pendingInput: StudioPendingInput?
    private var client: HermesStudioClient?
    private var generation: Double?
    private let defaults: UserDefaults
    private var ownerID: UUID?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func configure(_ connection: AgentConnection?) async {
        guard connection?.id != ownerID else { return }
        ownerID = connection?.id
        loading = false
        profiles = []; authenticated = false; messages = []; selectedProfile = nil; sessionID = nil; pendingInput = nil; pendingApprovals = []; running = false; generation = nil; error = nil
        guard let connection, let url = connection.normalizedBaseURL,
              url.scheme == "https", url.host?.hasSuffix(".ts.net") == true else { configuration = nil; client = nil; return }
        let key = "studio.gateway.\(connection.id)"
        if let saved = defaults.data(forKey: key).flatMap({ try? JSONDecoder().decode(StudioGatewayConfiguration.self, from: $0) }) { configuration = saved }
        else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.port = 9119; components.path = ""
            configuration = StudioGatewayConfiguration(apiConnectionID: connection.id, url: components.url!.absoluteString, username: "admin")
            if let configuration { defaults.set(try? JSONEncoder().encode(configuration), forKey: key) }
        }
        client = configuration.map(HermesStudioClient.init)
        await refresh()
    }
    func signIn(url: String, username: String, password: String) async -> Bool {
        guard var config = configuration else { return false }
        if config.url != url || config.username != username { config.id = UUID() }
        config.url = url; config.username = username
        let connection = HermesStudioClient(configuration: config)
        do {
            try await connection.signIn(password: password)
            configuration = config; client = connection
            defaults.set(try JSONEncoder().encode(config), forKey: "studio.gateway.\(config.apiConnectionID)")
            await refresh()
            return authenticated
        } catch { self.error = error.localizedDescription; return false }
    }
    func refresh() async {
        guard let client, !loading else { return }
        let identity = configuration?.id
        loading = true
        defer { if identity == configuration?.id { loading = false } }
        do {
            let profiles = try await client.profiles()
            guard identity == configuration?.id else { return }
            self.profiles = profiles
            authenticated = true; error = nil
        } catch {
            guard identity == configuration?.id else { return }
            authenticated = false
            do { let live = try await client.publicProfiles(); guard identity == configuration?.id else { return }; profiles = live }
            catch { profiles = []; self.error = error.localizedDescription }
        }
    }
    func open(_ profile: StudioProfile) async {
        guard authenticated, let client, let configuration else { error = StudioGatewayError.notSignedIn.localizedDescription; return }
        if selectedProfile != profile.name { messages = []; sessionID = nil; pendingInput = nil; pendingApprovals = []; running = false; generation = nil; error = nil }
        selectedProfile = profile.name
        do {
            var stored = profile.canonicalSession?.resolvedID ?? profile.canonicalSession?.id
            if stored == nil {
                let rows = try await client.request("session.list", params: ["profile": .string(profile.name), "title": .string("Bot Chat"), "include_hidden": .bool(true)])
                stored = rows["sessions"].array.first?["resolved_id"].string ?? rows["sessions"].array.first?["id"].string
            }
            guard self.configuration?.id == configuration.id, selectedProfile == profile.name else { return }
            if stored == nil {
                // The server owns canonical chat identity; never synthesize a local bot.
                let intentKey = "studio.create.\(configuration.id).\(profile.name)"
                let intent = defaults.string(forKey: intentKey) ?? UUID().uuidString
                defaults.set(intent, forKey: intentKey)
                let created = try await client.request("session.create", params: ["profile": .string(profile.name), "title": .string("Bot Chat"), "source": .string("gui"), "follow_profile_config": .bool(true), "request_id": .string(intent)])
                stored = created["stored_session_id"].string ?? created["session_id"].string
                if stored != nil { defaults.removeObject(forKey: intentKey) }
            }
            guard let stored else { throw StudioGatewayError.response("Hermes did not identify this bot’s conversation.") }
            let snapshot = try await client.request("session.resume", params: ["profile": .string(profile.name), "session_id": .string(stored)])
            guard self.configuration?.id == configuration.id, selectedProfile == profile.name else { return }
            sessionID = snapshot["session_id"].string ?? stored
            if let key = inputKey(profile.name) { pendingInput = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(StudioPendingInput.self, from: $0) } }
            apply(snapshot)
        } catch { self.error = error.localizedDescription }
    }
    func poll(_ profile: StudioProfile) async {
        guard authenticated, selectedProfile == profile.name, let sessionID, let client else { return }
        let identity = configuration?.id
        do {
            let snapshot = try await client.request("session.resume", params: ["profile": .string(profile.name), "session_id": .string(sessionID)])
            guard identity == configuration?.id, self.sessionID == sessionID, selectedProfile == profile.name else { return }
            apply(snapshot)
        } catch { self.error = "Couldn’t refresh the Studio conversation: \(error.localizedDescription)" }
    }
    private func inputKey(_ profile: String) -> String? {
        configuration.map { "studio.input.\($0.id).\(profile)" }
    }
    func send(_ text: String, profile: StudioProfile) async -> Bool {
        guard authenticated, selectedProfile == profile.name, let sessionID, !running,
              pendingInput == nil, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let key = inputKey(profile.name) else { return false }
        let saved = StudioPendingInput(profile: profile.name, sessionID: sessionID, text: text)
        do { defaults.set(try JSONEncoder().encode(saved), forKey: key) }
        catch { self.error = "Couldn’t save the message for safe recovery. \(error.localizedDescription)"; return false }
        pendingInput = saved
        return await retrySavedInput(profile)
    }
    func retrySavedInput(_ profile: StudioProfile) async -> Bool {
        guard let client, authenticated, selectedProfile == profile.name,
              let saved = pendingInput, saved.profile == profile.name,
              saved.sessionID == sessionID, let key = inputKey(profile.name) else { return false }
        // A very old unacknowledged message needs a human check rather than
        // assuming the server retains duplicate protection indefinitely.
        guard Date().timeIntervalSince(saved.createdAt) < 86_400 else {
            error = "This message is over a day old. Check its conversation in Hermes before clearing the saved message."
            return false
        }
        let identity = configuration?.id
        do {
            let result = try await client.request("prompt.submit", params: saved.parameters)
            guard saved.isConfirmed(by: result) else { throw StudioGatewayError.response("Hermes did not confirm that it accepted the message.") }
            defaults.removeObject(forKey: key)
            guard identity == configuration?.id else { return true }
            if pendingInput == saved { pendingInput = nil }
            error = nil
            if selectedProfile == profile.name { running = true; await poll(profile) }
            return true
        } catch {
            guard identity == configuration?.id, selectedProfile == profile.name else { return false }
            self.error = "Message delivery is unconfirmed. Refresh the conversation or retry the saved message; the retry keeps its original identity. \(error.localizedDescription)"
            return false
        }
    }
    func clearSavedInput(_ profile: StudioProfile) {
        guard selectedProfile == profile.name, let key = inputKey(profile.name) else { return }
        defaults.removeObject(forKey: key); pendingInput = nil; error = nil
    }
    func stop(_ profile: StudioProfile) async {
        guard let client, let sessionID, selectedProfile == profile.name else { return }
        var params: [String: GatewayValue] = ["profile": .string(profile.name), "session_id": .string(sessionID)]
        if let generation { params["execution_generation"] = .number(generation) }
        do { _ = try await client.request("session.interrupt", params: params); await poll(profile) }
        catch { self.error = "Couldn’t confirm stopping the Studio task. \(error.localizedDescription)" }
    }
    func approve(_ approval: GatewayValue, choice: String, profile: StudioProfile) async {
        guard let client, let sessionID, selectedProfile == profile.name,
              approval["choices"].array.contains(where: { $0.string == choice }),
              let id = approval["prompt_id"].string ?? approval["request_id"].string ?? approval["id"].string else { return }
        do {
            _ = try await client.request("approval.respond", params: ["profile": .string(profile.name), "session_id": .string(sessionID), "prompt_id": .string(id), "execution_generation": .number(approval["execution_generation"].number ?? generation ?? -1), "choice": .string(choice)])
            await poll(profile)
        } catch { self.error = error.localizedDescription }
    }
    func setModel(_ choice: ModelChoice, profile: StudioProfile) async -> Bool {
        guard let client, authenticated else { return false }
        do { try await client.setModel(profile: profile.name, choice: choice); await refresh(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func create(name: String, description: String, model: ModelChoice?) async -> Bool {
        guard let client, authenticated else { return false }
        do { let warnings = try await client.createProfile(name: name, description: description, model: model); await refresh(); if !warnings.isEmpty { error = warnings.joined(separator: "\n") }; return true }
        catch { self.error = error.localizedDescription; return false }
    }
    private func apply(_ snapshot: GatewayValue) {
        running = snapshot["running"].bool == true || snapshot["pending"].array.contains { ["queued", "started", "unknown"].contains($0["status"].string ?? "") }
        generation = snapshot["execution_generation"].number
        let rows = snapshot["messages"].array
        messages = rows.enumerated().compactMap { index, row in
            guard let role = row["role"].string, ["user", "assistant"].contains(role) else { return nil }
            let text = row["content"].string ?? row["content"].array.compactMap { $0["text"].string }.joined(separator: "\n")
            guard !text.isEmpty else { return nil }
            return StudioMessage(id: row["message_uid"].string ?? row["id"].string ?? row["message_id"].string ?? "\(index)-\(role)", role: role, text: text)
        }
        if let text = snapshot["inflight"]["assistant"].string, !text.isEmpty {
            messages.append(StudioMessage(id: "inflight", role: "assistant", text: text))
        }
        pendingApprovals = snapshot["prompts"].array.filter { $0["kind"].string == "approval" }
        if case .object = snapshot["pending_approval"] { pendingApprovals = [snapshot["pending_approval"]] }
        if let failure = snapshot["inflight"]["error"].string { error = failure }
    }
}
