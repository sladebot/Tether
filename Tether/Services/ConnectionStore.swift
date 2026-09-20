import Foundation

@MainActor
final class ConnectionStore {
    private let defaults: UserDefaults
    private let keychain: KeychainStore
    private let connectionsKey = "connections"
    private let selectedKey = "selectedConnectionID"
    private let chatKeyPrefix = "chat."
    private let conversationsKeyPrefix = "conversations."
    private let selectedConversationKeyPrefix = "selectedConversation."

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = KeychainStore()) {
        self.defaults = defaults
        self.keychain = keychain
    }

    func load() -> ([AgentConnection], UUID?) {
        let connections = defaults.data(forKey: connectionsKey)
            .flatMap { try? JSONDecoder().decode([AgentConnection].self, from: $0) } ?? []
        let selected = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
        return (connections, selected)
    }

    func save(_ connections: [AgentConnection], selectedID: UUID?) {
        if let data = try? JSONEncoder().encode(connections) {
            defaults.set(data, forKey: connectionsKey)
        }
        defaults.set(selectedID?.uuidString, forKey: selectedKey)
    }

    func credential(for connection: AgentConnection) -> String {
        switch connection.transport {
        case .apiServer:
            let origin = connection.normalizedBaseURL?.absoluteString ?? ""
            if let saved = APIServerCredentialStore(keychain: keychain).load(for: connection.id) {
                guard saved.origin == origin else {
                    APIServerCredentialStore(keychain: keychain).remove(for: connection.id)
                    return ""
                }
                return saved.apiKey
            }
            // One-time migration from builds that stored the raw API key under the UUID.
            guard let legacy = try? keychain.read(account: connection.id.uuidString),
                  !legacy.isEmpty else { return "" }
            try? saveCredential(legacy, for: connection)
            keychain.delete(account: connection.id.uuidString)
            return legacy
        case .dashboard:
            return (try? keychain.read(account: connection.id.uuidString)) ?? ""
        }
    }

    func saveCredential(_ value: String, for connection: AgentConnection) throws {
        switch connection.transport {
        case .apiServer:
            guard !value.isEmpty else {
                APIServerCredentialStore(keychain: keychain).remove(for: connection.id)
                return
            }
            try APIServerCredentialStore(keychain: keychain).save(
                APIServerCredential(
                    origin: connection.normalizedBaseURL?.absoluteString ?? "",
                    apiKey: value
                ),
                for: connection.id
            )
        case .dashboard:
            if value.isEmpty { keychain.delete(account: connection.id.uuidString) }
            else { try keychain.save(value, account: connection.id.uuidString) }
        }
    }

    func removeCredentials(for id: UUID) {
        keychain.delete(account: id.uuidString)
        APIServerCredentialStore(keychain: keychain).remove(for: id)
    }

    func removeDashboardTokens(for id: UUID) {
        DashboardTokenStore(keychain: keychain).remove(for: id)
    }

    func hasDashboardTokens(for connection: AgentConnection) -> Bool {
        guard let tokens = DashboardTokenStore(keychain: keychain).load(for: connection.id) else {
            return false
        }
        return tokens.origin == connection.normalizedBaseURL?.absoluteString
    }

    func loadChat(for id: UUID) -> [ChatMessage] {
        defaults.data(forKey: chatKeyPrefix + id.uuidString)
            .flatMap { try? JSONDecoder().decode([ChatMessage].self, from: $0) } ?? []
    }

    func saveChat(_ messages: [ChatMessage], for id: UUID) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        defaults.set(data, forKey: chatKeyPrefix + id.uuidString)
    }

    func removeChat(for id: UUID) {
        defaults.removeObject(forKey: chatKeyPrefix + id.uuidString)
        defaults.removeObject(forKey: conversationsKeyPrefix + id.uuidString)
        defaults.removeObject(forKey: selectedConversationKeyPrefix + id.uuidString)
    }

    func loadConversations(for connectionID: UUID) -> ([Conversation], UUID?) {
        let key = conversationsKeyPrefix + connectionID.uuidString
        var conversations = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([Conversation].self, from: $0) } ?? []
        if conversations.isEmpty {
            let legacy = loadChat(for: connectionID)
            if !legacy.isEmpty {
                conversations = [Conversation(
                    connectionID: connectionID,
                    title: Self.title(from: legacy),
                    messages: legacy
                )]
                saveConversations(conversations, selectedID: conversations[0].id, for: connectionID)
                defaults.removeObject(forKey: chatKeyPrefix + connectionID.uuidString)
            }
        }
        let selected = defaults.string(forKey: selectedConversationKeyPrefix + connectionID.uuidString)
            .flatMap(UUID.init(uuidString:))
        return (conversations.sorted { $0.updatedAt > $1.updatedAt }, selected)
    }

    func saveConversations(_ conversations: [Conversation], selectedID: UUID?, for connectionID: UUID) {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        defaults.set(data, forKey: conversationsKeyPrefix + connectionID.uuidString)
        defaults.set(selectedID?.uuidString, forKey: selectedConversationKeyPrefix + connectionID.uuidString)
    }

    private static func title(from messages: [ChatMessage]) -> String {
        guard let text = messages.first(where: { $0.role == .user })?.content else { return "New chat" }
        return String(text.prefix(44))
    }
}
