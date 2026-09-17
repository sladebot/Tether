import SwiftUI

struct ConnectionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var inputFocused: Bool
    private let existing: AgentConnection?
    private let draftID: UUID

    @State private var name: String
    @State private var address: String
    @State private var route: AgentConnection.Route
    @State private var transport: AgentConnection.Transport
    @State private var username: String
    @State private var apiKey: String
    @State private var credentialOrigin: URL?
    @State private var originChanged = false
    @State private var detectedModel: String?
    @State private var testing = false
    @State private var testResult: String?
    @State private var testSucceeded = false
    @State private var testedAt: Date?
    @State private var testTask: Task<Void, Never>?

    init(connection: AgentConnection? = nil, apiKey: String = "") {
        existing = connection
        draftID = connection?.id ?? UUID()
        _name = State(initialValue: connection?.name ?? "")
        _address = State(initialValue: connection?.baseURL ?? "")
        _route = State(initialValue: connection?.route ?? .local)
        _transport = State(initialValue: connection?.transport ?? .apiServer)
        _username = State(initialValue: connection?.username ?? "admin")
        _apiKey = State(initialValue: apiKey)
        _credentialOrigin = State(initialValue: connection?.normalizedBaseURL)
        _detectedModel = State(initialValue: connection?.modelName)
    }

    private var draft: AgentConnection {
        let candidate = AgentConnection(id: draftID, name: name, baseURL: address, route: route, transport: transport, username: transport == .dashboard ? username : nil, modelName: detectedModel)
        var result = candidate
        result.baseURL = candidate.normalizedBaseURL?.absoluteString ?? address
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.name = candidate.normalizedBaseURL?.host ?? "Hermes" }
        return result
    }

    var body: some View {
        Form {
            Section("Connection") {
                Picker("Connect over", selection: $route) {
                    ForEach(AgentConnection.Route.allCases) { route in
                        Label(route.rawValue, systemImage: route.symbol).tag(route)
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Server URL").font(.subheadline.weight(.medium))
                    TextField(addressPlaceholder, text: $address, axis: .vertical)
                        .textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                        .focused($inputFocused)
                        .accessibilityIdentifier("connection.url")
                    Text(route == .tailscale ? "Paste your Tailscale URL or hostname. HTTPS is added automatically. Include a port only if your server uses one." : "Enter the full local URL, including http:// and the server port.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if transport == .dashboard {
                    TextField("Dashboard username", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password (initial sign-in)", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                } else {
                    SecureField("Hermes API key", text: $apiKey)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($inputFocused)
                }
                TextField("Connection name (optional)", text: $name)
            }
            if let validationMessage {
                Section { Text(validationMessage).font(.footnote).foregroundStyle(.secondary) }
            }
            if originChanged {
                Section {
                    Text(existing == nil
                         ? "Enter the credential issued for this server before testing or connecting."
                         : "The server address or protocol changed. Enter this server’s credential. Applying creates a separate connection; your original connection, conversations, and queued builds are preserved.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    runTest()
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(draft.normalizedBaseURL == nil || (transport == .apiServer && apiKey.isEmpty) || testing)
                if testing {
                    Text("Checking address, authentication and model access…").font(.footnote).foregroundStyle(.secondary)
                    Button("Cancel test") { resetTest() }
                }
                if let testResult {
                    Label(testSucceeded ? "Ready to connect" : "Connection needs attention", systemImage: testSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(testSucceeded ? .green : .orange)
                    Text(testResult).font(.footnote).textSelection(.enabled)
                }
                if let testedAt {
                    LabeledContent("Last tested") { Text(testedAt, style: .time) }
                }
                if let detectedModel {
                    LabeledContent("Model", value: detectedModel)
                }
                if route == .tailscale, !draft.usesTailscaleHTTPS, draft.normalizedBaseURL != nil {
                    Label("Use a Tailscale Serve HTTPS URL to protect Hermes credentials in transit.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                DisclosureGroup("Advanced & connection details") {
                    Picker("Protocol", selection: $transport) {
                        ForEach(AgentConnection.Transport.allCases) { Text($0.title).tag($0) }
                    }
                    if let url = draft.normalizedBaseURL {
                        Text("Read-only details from your URL").font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Host", value: url.host ?? "—")
                        LabeledContent("Port", value: String(url.port ?? (url.scheme == "https" ? 443 : 80)))
                        LabeledContent("Security", value: url.scheme == "https" ? "HTTPS" : "HTTP · no TLS")
                    } else {
                        Text("Enter a valid URL to see its connection details.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text(connectionHelp).font(.footnote).foregroundStyle(.secondary)
                    Text("Testing checks API access, not a generated reply. Credentials are never included in results.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(existing == nil ? "Add connection" : "Edit connection")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                guard credentialOrigin == draft.normalizedBaseURL else { updateCredentialOrigin(); return }
                inputFocused = false
                model.upsert(draft, apiKey: apiKey)
                dismiss()
            } label: {
                Text("Apply & connect").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .background(colorScheme == .dark ? Color.white : Color.black, in: RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .disabled(validationMessage != nil || testing)
            .opacity(validationMessage == nil && !testing ? 1 : 0.4)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(.bar)
        }
        .onDisappear { testTask?.cancel() }
        .onChange(of: address) { _, _ in updateCredentialOrigin(); resetTest() }
        .onChange(of: apiKey) { _, _ in resetTest() }
        .onChange(of: route) { _, _ in updateCredentialOrigin(); resetTest() }
        .onChange(of: transport) { _, _ in
            apiKey = ""
            originChanged = true
            credentialOrigin = draft.normalizedBaseURL
            resetTest()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }

    private var validationMessage: String? {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add your server URL to get started." }
        if draft.normalizedBaseURL == nil { return "Enter a valid server address. Don’t include a password or token in the URL." }
        if transport == .apiServer && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add your Hermes API token to test or connect." }
        return nil
    }

    private func resetTest() {
        testTask?.cancel()
        testing = false
        testResult = nil
        testedAt = nil
        detectedModel = nil
    }

    private func updateCredentialOrigin() {
        let next = draft.normalizedBaseURL
        guard credentialOrigin != next else { return }
        apiKey = ""
        credentialOrigin = next
        originChanged = true
    }

    private func runTest() {
        guard credentialOrigin == draft.normalizedBaseURL else { updateCredentialOrigin(); return }
        inputFocused = false
        resetTest()
        testing = true
        let connection = draft
        let key = apiKey
        testTask = Task { @MainActor in
            let start = Date()
            do {
                let result = try await HermesAPIClient(connection: connection, apiKey: key, session: HermesAPIClient.diagnosticSession).testConnection()
                guard !Task.isCancelled else { return }
                detectedModel = result
                testSucceeded = true
                testResult = "Server reachable · Authentication accepted · Model access verified\nCompleted in \(String(format: "%.1f", Date().timeIntervalSince(start))) seconds."
            } catch {
                guard !Task.isCancelled else { return }
                testSucceeded = false
                if let error = error as? URLError {
                    switch error.code {
                    case .cannotFindHost, .dnsLookupFailed:
                        testResult = "DNS lookup failed. Verify the hostname, including any new -1 suffix, and connect Tailscale on both devices."
                    case .timedOut, .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost:
                        testResult = "Server unreachable (network code \(error.code.rawValue)). Check the Mac is awake, Tailscale is connected, and Serve forwards this port to 127.0.0.1:8642. For LAN, check Wi-Fi and Local Network permission in iOS Settings."
                    default:
                        testResult = "Secure connection failed (network code \(error.code.rawValue)). Check the address and certificate. HTTPS certificates require the hostname, not a numeric Tailscale IP."
                    }
                } else if case let HermesAPIClient.ClientError.server(status, _) = error {
                    testResult = "Server reachable · HTTP \(status)\n" + ([401, 403].contains(status) ? "Authentication rejected. Check the Hermes API token for this endpoint." : "Check that this route serves Hermes API, not another service.")
                } else {
                    testResult = "Hermes API verification failed. Check that this endpoint forwards to port 8642 and uses the selected protocol."
                }
            }
            testedAt = Date()
            testing = false
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
