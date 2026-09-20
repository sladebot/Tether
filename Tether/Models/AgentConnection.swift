import Foundation

struct AgentConnection: Identifiable, Codable, Hashable, Sendable {
    enum Transport: CaseIterable, Identifiable, Sendable, Codable {
        case apiServer
        case dashboard

        var id: Self { self }

        var title: String {
            switch self {
            case .apiServer: "Hermes API Server"
            case .dashboard: "Dashboard control plane"
            }
        }

        var detail: String {
            switch self {
            case .apiServer: "Recommended for chat and mini apps"
            case .dashboard: "Advanced dashboard and PTY compatibility"
            }
        }

        var defaultPort: Int { self == .apiServer ? 8642 : 9119 }

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            switch value {
            case "apiServer", "Hermes API Server", "OpenAI-compatible API": self = .apiServer
            case "dashboard", "Hermes Dashboard", "Dashboard control plane": self = .dashboard
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown Hermes transport: \(value)"
                ))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self == .apiServer ? "apiServer" : "dashboard")
        }
    }

    enum Route: String, Codable, CaseIterable, Identifiable, Sendable {
        case local = "Local network"
        case tailscale = "Tailscale"

        var id: Self { self }
        var symbol: String { self == .local ? "wifi" : "network.badge.shield.half.filled" }
    }

    var id: UUID
    var name: String
    var baseURL: String
    var route: Route
    var transport: Transport
    var username: String?
    var modelName: String?

    init(id: UUID = UUID(), name: String, baseURL: String, route: Route, transport: Transport = .apiServer, username: String? = nil, modelName: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.route = route
        self.transport = transport
        self.username = username
        self.modelName = modelName
    }

    private enum CodingKeys: String, CodingKey { case id, name, baseURL, route, transport, username, modelName }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        baseURL = try values.decode(String.self, forKey: .baseURL)
        route = try values.decode(Route.self, forKey: .route)
        username = try values.decodeIfPresent(String.self, forKey: .username)
        modelName = try values.decodeIfPresent(String.self, forKey: .modelName)
        if let saved = try values.decodeIfPresent(Transport.self, forKey: .transport) {
            transport = saved
        } else {
            transport = URL(string: baseURL)?.port == 9119 ? .dashboard : .apiServer
        }
    }

    var normalizedBaseURL: URL? {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.contains("://"), route == .tailscale { value = "https://" + value }
        while value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix("/v1") { value.removeLast(3) }
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            return nil
        }
        return url
    }

    func endpoint(_ path: String) -> URL? {
        guard let base = normalizedBaseURL else { return nil }
        return base.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }

    // Conversations and durable jobs belong to a server identity, not an editable label.
    func preservingServerIdentity(previous: AgentConnection?) -> AgentConnection {
        guard let previous, previous.id == id,
              previous.transport != transport || previous.normalizedBaseURL != normalizedBaseURL else { return self }
        var separate = self
        separate.id = UUID()
        return separate
    }

    var usesTailscaleHTTPS: Bool {
        route != .tailscale || normalizedBaseURL?.scheme?.lowercased() == "https"
    }
}
