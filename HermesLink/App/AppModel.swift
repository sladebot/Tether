import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    enum ConnectionState: Equatable {
        case idle
        case testing
        case connected
        case failed(String)
    }

    @Published var connections: [AgentConnection]
    @Published var selectedConnectionID: UUID?
    @Published var messages: [ChatMessage] = []
    @Published var connectionState: ConnectionState = .idle
    @Published var isResponding = false
    @Published var alertMessage: String?
    @Published var miniApps: [MiniApp]
    @Published var isBuildingMiniApp = false
    @Published var miniAppBuildCharacterCount = 0

    private let store: ConnectionStore
    private let miniAppStore: MiniAppStore
    private var responseTask: Task<Void, Never>?

    init(store: ConnectionStore = ConnectionStore(), miniAppStore: MiniAppStore = MiniAppStore()) {
        self.store = store
        self.miniAppStore = miniAppStore
        let saved = store.load()
        #if targetEnvironment(simulator)
        let initialConnections = saved.0.isEmpty
            ? [AgentConnection(name: "Hermes API on this Mac", baseURL: "http://10.0.0.151:8642", route: .local, transport: .apiServer)]
            : saved.0.map { savedConnection in
                var connection = savedConnection
                if connection.transport == .apiServer,
                   ["localhost", "127.0.0.1"].contains(connection.normalizedBaseURL?.host ?? "") {
                    connection.baseURL = "http://10.0.0.151:8642"
                } else if connection.transport == .dashboard,
                   ["localhost", "127.0.0.1"].contains(connection.normalizedBaseURL?.host ?? "") {
                    connection.baseURL = "http://10.0.0.151:9119"
                    connection.username = connection.username ?? "admin"
                }
                return connection
            }
        #else
        let initialConnections = saved.0
        #endif
        connections = initialConnections
        selectedConnectionID = saved.1 ?? initialConnections.first?.id
        miniApps = miniAppStore.load()
        if let selectedConnectionID {
            messages = store.loadChat(for: selectedConnectionID)
        }
        if initialConnections != saved.0, !initialConnections.isEmpty { persist() }
    }

    var selectedConnection: AgentConnection? {
        connections.first { $0.id == selectedConnectionID }
    }

    func upsert(_ connection: AgentConnection, apiKey: String) {
        saveCurrentChat()
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            let previous = connections[index]
            if previous.transport != connection.transport || previous.normalizedBaseURL != connection.normalizedBaseURL {
                store.removeCredentials(for: connection.id)
                store.removeDashboardTokens(for: connection.id)
            }
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        selectedConnectionID = connection.id
        let secretToPersist = connection.transport == .dashboard && store.hasDashboardTokens(for: connection)
            ? ""
            : apiKey
        do { try store.saveCredential(secretToPersist, for: connection) }
        catch { alertMessage = "Couldn’t save the API key securely: \(error.localizedDescription)" }
        persist()
        messages = store.loadChat(for: connection.id)
        connectionState = .idle
    }

    func apiKey(for connection: AgentConnection) -> String { store.credential(for: connection) }

    func remove(_ connection: AgentConnection) {
        connections.removeAll { $0.id == connection.id }
        store.removeCredentials(for: connection.id)
        store.removeDashboardTokens(for: connection.id)
        store.removeChat(for: connection.id)
        if selectedConnectionID == connection.id { selectedConnectionID = connections.first?.id }
        messages = selectedConnectionID.map(store.loadChat(for:)) ?? []
        persist()
    }

    func select(_ connection: AgentConnection) {
        guard selectedConnectionID != connection.id else { return }
        saveCurrentChat()
        stop()
        selectedConnectionID = connection.id
        messages = store.loadChat(for: connection.id)
        connectionState = .idle
        persist()
    }

    @discardableResult
    func test(_ connection: AgentConnection, apiKey: String) async -> String? {
        connectionState = .testing
        do {
            let model = try await HermesAPIClient(connection: connection, apiKey: apiKey).testConnection()
            if connection.transport == .dashboard, store.hasDashboardTokens(for: connection) {
                try? store.saveCredential("", for: connection)
            }
            connectionState = .connected
            return model
        } catch {
            connectionState = .failed(error.localizedDescription)
            return nil
        }
    }

    func checkSelectedConnection() async {
        guard let connection = selectedConnection else { return }
        _ = await test(connection, apiKey: apiKey(for: connection))
    }

    func send(_ text: String) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, let connection = selectedConnection, !isResponding else { return }
        messages.append(ChatMessage(role: .user, content: input))
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        saveCurrentChat()
        isResponding = true
        let history = messages.filter { $0.id != assistantID }
        let client = HermesAPIClient(connection: connection, apiKey: apiKey(for: connection))

        responseTask = Task {
            do {
                for try await piece in client.stream(messages: history) {
                    guard let index = messages.firstIndex(where: { $0.id == assistantID }) else { continue }
                    messages[index].content += piece
                }
            } catch {
                messages.removeAll { $0.id == assistantID && $0.content.isEmpty }
                alertMessage = error.localizedDescription
            }
            isResponding = false
            saveCurrentChat()
        }
    }

    func stop() {
        responseTask?.cancel()
        responseTask = nil
        isResponding = false
        saveCurrentChat()
    }

    func clearChat() {
        stop()
        messages.removeAll()
        saveCurrentChat()
    }

    func buildMiniApp(title: String, request: String) async -> Bool {
        guard let connection = selectedConnection else {
            alertMessage = "Add and select a Hermes connection before building a mini app."
            return false
        }
        guard !isBuildingMiniApp else { return false }
        isBuildingMiniApp = true
        miniAppBuildCharacterCount = 0
        defer { isBuildingMiniApp = false }

        let builderPrompt = """
        You are the Mini App Builder inside the HermesLink iOS harness.

        Build this mini app: \(request)

        Return exactly one complete, self-contained HTML document beginning with <!DOCTYPE html>. Do not use Markdown fences or add commentary. Put all CSS and JavaScript inline. Do not use external packages, URLs, fonts, images, network requests, iframes, or APIs. The app must work offline, fit a mobile viewport, support touch, use accessible labels and contrast, respect light/dark color schemes, and persist state only in memory for the current run.
        """
        let client = HermesAPIClient(connection: connection, apiKey: apiKey(for: connection))
        var response = ""
        do {
            for try await piece in client.stream(messages: [ChatMessage(role: .user, content: builderPrompt)]) {
                response += piece
                miniAppBuildCharacterCount = response.count
            }
            let html = try MiniAppDocument.prepare(response)
            let app = try miniAppStore.save(title: title, html: html)
            miniApps.insert(app, at: 0)
            return true
        } catch is CancellationError {
            return false
        } catch {
            alertMessage = "Mini app build failed: \(error.localizedDescription)"
            return false
        }
    }

    func deleteMiniApp(_ app: MiniApp) {
        do {
            try miniAppStore.delete(app, from: miniApps)
            miniApps.removeAll { $0.id == app.id }
        } catch {
            alertMessage = "Couldn’t delete the mini app: \(error.localizedDescription)"
        }
    }

    func miniAppURL(for app: MiniApp) -> URL { miniAppStore.htmlURL(for: app) }

    private func persist() { store.save(connections, selectedID: selectedConnectionID) }

    private func saveCurrentChat() {
        guard let selectedConnectionID else { return }
        store.saveChat(messages, for: selectedConnectionID)
    }
}
