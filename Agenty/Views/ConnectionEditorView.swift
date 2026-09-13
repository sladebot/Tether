import SwiftUI

struct ConnectionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let existing: AgentConnection?
    private let draftID: UUID

    @State private var name: String
    @State private var address: String
    @State private var route: AgentConnection.Route
    @State private var transport: AgentConnection.Transport
    @State private var username: String
    @State private var apiKey: String
    @State private var detectedModel: String?

    init(connection: AgentConnection? = nil, apiKey: String = "") {
        existing = connection
        draftID = connection?.id ?? UUID()
        _name = State(initialValue: connection?.name ?? "")
        _address = State(initialValue: connection?.baseURL ?? "")
        _route = State(initialValue: connection?.route ?? .local)
        _transport = State(initialValue: connection?.transport ?? .apiServer)
        _username = State(initialValue: connection?.username ?? "admin")
        _apiKey = State(initialValue: apiKey)
        _detectedModel = State(initialValue: connection?.modelName)
    }

    private var draft: AgentConnection {
        AgentConnection(id: draftID, name: name, baseURL: address, route: route, transport: transport, username: transport == .dashboard ? username : nil, modelName: detectedModel)
    }

    var body: some View {
        Form {
            Section("Connection") {
                TextField("Name, e.g. Home Mac", text: $name)
                Picker("Route", selection: $route) {
                    ForEach(AgentConnection.Route.allCases) { route in
                        Label(route.rawValue, systemImage: route.symbol).tag(route)
                    }
                }
                Picker("Protocol", selection: $transport) {
                    ForEach(AgentConnection.Transport.allCases) { transport in
                        VStack(alignment: .leading) {
                            Text(transport.title)
                            Text(transport.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(transport)
                    }
                }
                TextField(addressPlaceholder, text: $address)
                    .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                if transport == .dashboard {
                    TextField("Dashboard username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password (initial sign-in)", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    SecureField("Hermes API key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
            }
            Section {
                Button {
                    Task { detectedModel = await model.test(draft, apiKey: apiKey) }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        stateIndicator
                    }
                }
                .disabled(draft.normalizedBaseURL == nil || (transport == .apiServer && apiKey.isEmpty) || model.connectionState == .testing)
                if let detectedModel {
                    LabeledContent("Model", value: detectedModel)
                }
                if case let .failed(message) = model.connectionState {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
                if route == .tailscale, !draft.usesTailscaleHTTPS, draft.normalizedBaseURL != nil {
                    Label("Use a Tailscale Serve HTTPS URL to protect Hermes credentials in transit.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } footer: {
                Text(connectionHelp)
            }
        }
        .navigationTitle(existing == nil ? "New Connection" : "Edit Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.connectionState = .idle }
        .onChange(of: address) { _, _ in model.connectionState = .idle }
        .onChange(of: transport) { _, _ in
            model.connectionState = .idle
            detectedModel = nil
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { model.upsert(draft, apiKey: apiKey); dismiss() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || draft.normalizedBaseURL == nil || (transport == .apiServer && apiKey.isEmpty))
            }
        }
    }

    private var addressPlaceholder: String {
        if route == .tailscale { return "https://mac-studio.tailnet.ts.net" }
        return "http://192.168.1.20:\(transport.defaultPort)"
    }

    private var connectionHelp: String {
        switch (route, transport) {
        case (.tailscale, .apiServer):
            "Recommended: Tailscale Serve HTTPS forwarding to the loopback Hermes API Server on port 8642. The API key is bound to this exact origin in iOS Keychain."
        case (.tailscale, .dashboard):
            "Use a separate Tailscale Serve HTTPS endpoint forwarding to the loopback dashboard on port 9119. Hermes dashboard authentication remains required."
        case (.local, .apiServer):
            "Connects to the Hermes API Server on port 8642. Its bearer key is stored in iOS Keychain and never placed in app preferences."
        case (.local, .dashboard):
            "The password is used once to obtain signed Hermes tokens, then removed. Origin-bound access and refresh tokens remain in iOS Keychain."
        }
    }

    @ViewBuilder private var stateIndicator: some View {
        switch model.connectionState {
        case .idle: EmptyView()
        case .testing: ProgressView()
        case .connected: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}
