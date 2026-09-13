import Foundation
import Security

struct KeychainStore: Sendable {
    enum Error: Swift.Error {
        case unexpectedStatus(OSStatus)
    }

    private let service = "app.agenty.connections"

    func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw Error.unexpectedStatus(status) }
    }

    func read(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw Error.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct DashboardTokens: Codable, Sendable, Equatable {
    let origin: String
    let accessToken: String
    let refreshToken: String
    let provider: String
    let expiresAt: Int
}

struct APIServerCredential: Codable, Sendable, Equatable {
    let origin: String
    let apiKey: String
}

struct APIServerCredentialStore: Sendable {
    private let keychain: KeychainStore
    private let accountSuffix = ".api-server-credential"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load(for connectionID: UUID) -> APIServerCredential? {
        guard let encoded = try? keychain.read(account: connectionID.uuidString + accountSuffix),
              let data = encoded.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(APIServerCredential.self, from: data)
    }

    func save(_ credential: APIServerCredential, for connectionID: UUID) throws {
        let data = try JSONEncoder().encode(credential)
        guard let encoded = String(data: data, encoding: .utf8) else { return }
        try keychain.save(encoded, account: connectionID.uuidString + accountSuffix)
    }

    func remove(for connectionID: UUID) {
        keychain.delete(account: connectionID.uuidString + accountSuffix)
    }
}

struct DashboardTokenStore: Sendable {
    private let keychain: KeychainStore
    private let accountSuffix = ".dashboard-tokens"

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func load(for connectionID: UUID) -> DashboardTokens? {
        guard let encoded = try? keychain.read(account: connectionID.uuidString + accountSuffix),
              let data = encoded.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DashboardTokens.self, from: data)
    }

    func save(_ tokens: DashboardTokens, for connectionID: UUID) throws {
        let data = try JSONEncoder().encode(tokens)
        guard let encoded = String(data: data, encoding: .utf8) else { return }
        try keychain.save(encoded, account: connectionID.uuidString + accountSuffix)
    }

    func remove(for connectionID: UUID) {
        keychain.delete(account: connectionID.uuidString + accountSuffix)
    }
}
