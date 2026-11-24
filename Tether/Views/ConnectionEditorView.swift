import SwiftUI

struct ConnectionEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var inputFocused: Bool
    private let existing: AgentConnection?
    private let draftID: UUID
    private let onSaved: (() -> Void)?

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

    init(connection: AgentConnection? = nil, apiKey: String = "", onSaved: (() -> Void)? = nil) {
        self.onSaved = onSaved
        existing = connection
        draftID = connection?.id ?? UUID()
        _name = State(initialValue: connection?.name ?? "Hermes")
        _address = State(initialValue: connection?.baseURL ?? "")
        _route = State(initialValue: connection?.route ?? .tailscale)
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
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.name = "Hermes" }
        return result
    }

    var body: some View {
        Form {
            providerIntroduction
            connectionFields
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
            verificationSection
            botAccessSection
            advancedSection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(existing == nil ? "Add Hermes" : "Hermes settings")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                guard credentialOrigin == draft.normalizedBaseURL else { updateCredentialOrigin(); return }
                inputFocused = false
                model.upsert(draft, apiKey: apiKey)
                if let onSaved { onSaved() } else { dismiss() }
            } label: {
                Text(existing == nil ? "Add Hermes" : "Save provider").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
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

    private var providerIntroduction: some View {
        Section {
            Label("Hermes", systemImage: "sparkles").font(.headline)
            Text("Connect to your Hermes server. Models and agent work run there.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var connectionFields: some View {
        Section("Connection") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tailscale URL").font(.subheadline.weight(.medium))
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
                SecureField("API token", text: $apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .focused($inputFocused)
            }
            TextField("Name (optional)", text: $name)
        }
    }

    private var verificationSection: some View {
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
            .disabled(validationMessage != nil || testing)
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
    }

    @ViewBuilder private var botAccessSection: some View {
        if existing?.id == model.selectedConnectionID && existing != nil {
            Section {
                NavigationLink { StudioGatewaySetupView() } label: { Label("Bot access", systemImage: "person.2") }
            } footer: { Text("Configured bots use your Hermes dashboard sign-in. Your API token powers chat and mini apps.") }
        }
    }

    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced & connection details") {
                if transport == .apiServer {
                    NavigationLink("Hermes feature availability") {
                        HermesFeatureReportView(connection: draft, apiKey: apiKey)
                    }
                    .disabled(validationMessage != nil || credentialOrigin != draft.normalizedBaseURL)
                }
                LabeledContent("Provider", value: "Hermes")
                LabeledContent("Connect over", value: route.rawValue)
                LabeledContent("Protocol", value: transport.title)
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

    private var validationMessage: String? {
        if address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add your server URL to get started." }
        if draft.normalizedBaseURL == nil { return "Enter a valid server address. Don’t include a password or token in the URL." }
        if route == .tailscale, let url = draft.normalizedBaseURL,
           url.scheme != "https" || url.host?.hasSuffix(".ts.net") != true {
            return "Use your Tailscale HTTPS hostname ending in .ts.net."
        }
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
                testResult = "Server reachable · Authentication accepted · Model catalog available\nCompleted in \(String(format: "%.1f", Date().timeIntervalSince(start))) seconds."
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

private struct HermesFeatureReportView: View {
    let connection: AgentConnection
    let apiKey: String
    @State private var report: HermesFeatureReport?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            Section {
                Text("Server support is not the same as an Tether screen or a passed end-to-end test. Agent tools may work through chat without a dedicated interface.")
                    .font(.footnote)
                Text(connection.normalizedBaseURL?.host ?? "Hermes").font(.caption).foregroundStyle(.secondary)
            }
            if loading { ProgressView("Reading server capabilities…") }
            if let error { Section("Could not verify") { Text(error); Button("Retry") { Task { await reload() } } } }
            if let report {
                ForEach(report.features.keys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(key.replacingOccurrences(of: "_", with: " ").capitalized).font(.headline)
                        Text("Server: \(report.features[key]?.availability.rawValue ?? "Not specified")")
                        Text(HermesFeatureReport.appSupport(for: key)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Hermes features")
        .task { await reload() }
        .refreshable { await reload() }
    }

    @MainActor private func reload() async {
        guard !loading else { return }
        loading = true; error = nil; report = nil
        defer { loading = false }
        do {
            let result = try await HermesAPIClient(connection: connection, apiKey: apiKey, session: HermesAPIClient.diagnosticSession).featureReport()
            try Task.checkCancellation()
            report = result
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
