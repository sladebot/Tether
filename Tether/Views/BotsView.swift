import SwiftUI

enum TetherTab: Hashable { case home, chat, bots, library }

enum TetherTheme {
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.48, green: 0.82, blue: 0.75, alpha: 1) : UIColor(red: 0.10, green: 0.35, blue: 0.31, alpha: 1)
    })
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var studio: HermesStudioStore
    @Binding var tab: TetherTab
    @State private var connections = false
    private var connected: Bool { model.connectionState == .connected }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your Studio.\nWithin reach.").font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        Text("Conversations, specialist bots, and small tools — powered by your Hermes.")
                            .font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.top, 12)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(TetherTheme.accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.selectedConnection?.name ?? "Connect your Studio").font(.headline)
                                Text(model.selectedConnection?.normalizedBaseURL?.host ?? "Hermes over Tailscale")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Circle().fill(connected ? Color.green : Color.secondary).frame(width: 8, height: 8)
                                .accessibilityLabel(connected ? "Connected" : "Connection not verified")
                        }
                        Divider()
                        Button { connections = true } label: {
                            HStack { Text(model.selectedConnection == nil ? "Set up connection" : "Manage connection"); Spacer(); Image(systemName: "arrow.up.right") }
                                .font(.subheadline).frame(minHeight: 32)
                        }
                    }.padding(20).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    VStack(spacing: 12) {
                        destination("Chat with Hermes", subtitle: "Ask, plan, and get things done", icon: "bubble.left.and.bubble.right", target: .chat)
                        destination("Hermes bots", subtitle: studio.profiles.isEmpty ? "Open the bots configured on your Studio" : "\(studio.profiles.count) profiles reported by your Studio", icon: "person.2", target: .bots)
                        destination("Mini apps", subtitle: model.miniApps.isEmpty ? "Build a useful tool from an idea" : "\(model.miniApps.count) saved \(model.miniApps.count == 1 ? "tool" : "tools") in your library", icon: "square.grid.2x2", target: .library)
                    }
                    Label("Agent and model work stays on your Studio", systemImage: "network.badge.shield.half.filled")
                        .font(.footnote).foregroundStyle(.secondary).padding(.bottom, 12)
                }.padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tether").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Connections", systemImage: "slider.horizontal.3") { connections = true }.labelStyle(.iconOnly) } }
            .sheet(isPresented: $connections) { NavigationStack { ConnectionListView() } }
        }
    }
    private func destination(_ title: String, subtitle: String, icon: String, target: TetherTab) -> some View {
        Button { tab = target } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title3).frame(width: 44, height: 44)
                    .background(TetherTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(TetherTheme.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }
}

struct BotsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var studio: HermesStudioStore
    @State private var setup = false
    @State private var creating = false
    @State private var search = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "desktopcomputer").foregroundStyle(TetherTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hermes on Mac Studio").font(.headline)
                            Text("Live profiles · via Tailscale").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if studio.loading { ProgressView() }
                    }.padding(.vertical, 6)
                    if !studio.authenticated {
                        Button("Sign in to Hermes", systemImage: "lock.open") { setup = true }
                            .disabled(studio.configuration == nil)
                        Text("Your Mac Studio reports these Hermes profiles. Sign in with your Hermes dashboard account to open their conversations and model settings.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = studio.error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").font(.footnote); Button("Retry") { Task { await studio.refresh() } } }
                }
                Section("On your Mac Studio") {
                    ForEach(studio.profiles.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search) }) { profile in
                        NavigationLink { StudioBotView(profile: profile) } label: {
                            HStack(spacing: 14) {
                                Text(String(profile.title.prefix(1)).uppercased()).font(.title3.weight(.medium))
                                    .frame(width: 46, height: 46).background(TetherTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 15)).foregroundStyle(TetherTheme.accent)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(profile.title).font(.headline)
                                    Text(studio.authenticated ? profile.modelLabel : "Sign in to view this profile")
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.padding(.vertical, 8)
                            }
                        }.disabled(!studio.authenticated)
                    }
                    if studio.profiles.isEmpty && !studio.loading {
                        Text("No profiles loaded. Check your Studio connection and gateway sign-in.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("This roster comes from Hermes on your Studio. Bots created here become real Hermes profiles, with their own model, tools, and conversation history.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Hermes bots")
            .searchable(text: $search, prompt: "Find a Studio bot")
            .refreshable { await studio.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Gateway settings", systemImage: "slider.horizontal.3") { setup = true }.labelStyle(.iconOnly) }
                ToolbarItem(placement: .topBarTrailing) { Button("Create on Studio", systemImage: "plus") { creating = true }.disabled(!studio.authenticated) }
            }
            .sheet(isPresented: $setup) { NavigationStack { StudioGatewaySetupView() } }
            .sheet(isPresented: $creating) { NavigationStack { StudioBotCreateView() } }
            .task { await studio.refresh() }
        }
    }
}

struct StudioGatewaySetupView: View {
    @EnvironmentObject private var studio: HermesStudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var username = "admin"
    @State private var password = ""
    @State private var signingIn = false
    var body: some View {
        Form {
            Section {
                Label("Hermes on your Mac Studio", systemImage: "desktopcomputer").font(.headline)
                Text("Use your Mac Studio’s Hermes dashboard account to access its bots. Chat and mini apps already use your Hermes API connection over Tailscale.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section("Hermes gateway · Tailscale") {
                TextField("Tailscale HTTPS URL", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Username", text: $username).textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Dashboard password", text: $password).textContentType(.password)
            }
            if let error = studio.error { Section { Text(error).font(.footnote).foregroundStyle(.red) } }
            Section {
                Button {
                    signingIn = true
                    Task {
                        if await studio.signIn(url: url, username: username, password: password) { password = ""; dismiss() }
                        signingIn = false
                    }
                } label: {
                    HStack { Text("Sign in to Hermes"); Spacer(); if signingIn { ProgressView() } }
                }.disabled(signingIn || password.isEmpty || url.isEmpty || username.isEmpty)
            } footer: { Text("Your Hermes sign-in is saved securely in iPhone Keychain.") }
        }
        .navigationTitle("Hermes sign-in").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { url = studio.configuration?.url ?? ""; username = studio.configuration?.username ?? "admin" }
    }
}

struct StudioBotView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var studio: HermesStudioStore
    let profile: StudioProfile
    @State private var input = ""
    @State private var sending = false
    @State private var choosingModel = false
    @State private var confirmingClear = false
    private var current: StudioProfile { studio.profiles.first { $0.name == profile.name } ?? profile }
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Button { choosingModel = true } label: {
                        HStack { Label(current.modelLabel, systemImage: "cpu").font(.caption); Spacer(); Image(systemName: "chevron.down").font(.caption2) }
                    }.padding(14).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                    if let description = current.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                    if let error = studio.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
                        Button("Refresh conversation") { Task { await studio.poll(current) } }
                    }
                    if let saved = studio.pendingInput {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Message awaiting confirmation", systemImage: "clock").font(.headline)
                            Text(saved.text).font(.callout).textSelection(.enabled)
                            Button("Retry saved message") {
                                sending = true
                                Task { if await studio.retrySavedInput(current) { input = "" }; sending = false }
                            }.disabled(sending)
                            Button("I checked Hermes · clear saved message", role: .destructive) { confirmingClear = true }
                        }.padding(18).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    ForEach(Array(studio.pendingApprovals.enumerated()), id: \.offset) { _, approval in
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Your approval", systemImage: "hand.raised").font(.headline)
                            Text(approval["command"].string ?? "Hermes needs permission to continue.").font(.callout).textSelection(.enabled)
                            ForEach(approval["choices"].array.compactMap(\.string), id: \.self) { choice in
                                Button(choice == "once" ? "Allow once" : choice.capitalized) { Task { await studio.approve(approval, choice: choice, profile: current) } }.buttonStyle(.bordered)
                            }
                        }.padding(18).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    }
                    if studio.messages.isEmpty && !studio.running {
                        ContentUnavailableView("A conversation with \(current.title)", systemImage: "bubble.left.and.bubble.right", description: Text("Messages are read from this bot’s Bot Chat on your Studio."))
                    }
                    ForEach(studio.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.role == "user" ? "You" : current.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(.init(message.text)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    if studio.running { Label("Working on Studio…", systemImage: "circle.dotted").font(.subheadline).foregroundStyle(.secondary) }
                }.padding(20)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Message \(current.title)", text: $input, axis: .vertical).lineLimit(1...6)
                if studio.running {
                    Button("Stop", systemImage: "stop.fill") { Task { await studio.stop(current) } }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                } else {
                    Button {
                        sending = true
                        Task { if await studio.send(input, profile: current) { input = "" }; sending = false }
                    } label: { Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                        .disabled(sending || studio.pendingInput != nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || studio.sessionID == nil)
                }
            }.padding(16).background(.bar)
        }
        .navigationTitle(current.title).navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear the saved message?", isPresented: $confirmingClear) {
            Button("Clear saved message", role: .destructive) { studio.clearSavedInput(current); input = "" }
        } message: { Text("Clearing this record does not cancel any work Hermes accepted. Check the conversation on your Mac Studio first.") }
        .sheet(isPresented: $choosingModel) {
            NavigationStack {
                StudioModelPicker(choices: model.modelChoices, selected: nil, allowsDefault: false) { choice in
                    if let choice { Task { if await studio.setModel(choice, profile: current) { choosingModel = false } } }
                }
            }
        }
        .task(id: profile.name) {
            await model.refreshModelChoices()
            await studio.open(profile)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await studio.poll(profile)
            }
        }
    }
}

struct StudioBotCreateView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var studio: HermesStudioStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var choice: ModelChoice?
    @State private var saving = false
    var body: some View {
        Form {
            Section("New Hermes profile") {
                TextField("Profile name, e.g. researcher", text: $name).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Role and description", text: $description, axis: .vertical).lineLimit(3...7)
                NavigationLink {
                    StudioModelPicker(choices: model.modelChoices, selected: choice) { choice = $0 }
                } label: { LabeledContent("Model", value: choice?.model ?? "Studio default") }
            }
            Section {
                Button("Create on Studio") {
                    saving = true
                    Task { if await studio.create(name: name, description: description, model: choice) { dismiss() }; saving = false }
                }.disabled(saving || name.isEmpty || !name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            } footer: { Text("Creates a real Hermes profile on your Studio. Existing messaging channels are not cloned.") }
            if let error = studio.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
        .navigationTitle("Create Studio bot").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .task { await model.refreshModelChoices() }
    }
}

struct StudioModelPicker: View {
    let choices: [ModelChoice]
    let selected: ModelChoice?
    var allowsDefault = true
    let select: (ModelChoice?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [ModelChoice] { choices.filter { search.isEmpty || $0.model.localizedCaseInsensitiveContains(search) || $0.providerName.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if allowsDefault { Button("Studio default") { select(nil); dismiss() } }
            ForEach(Dictionary(grouping: filtered, by: \.provider).keys.sorted(), id: \.self) { provider in
                Section(filtered.first { $0.provider == provider }?.providerName ?? provider) {
                    ForEach(filtered.filter { $0.provider == provider }) { choice in
                        Button { select(choice); dismiss() } label: {
                            HStack { Text(choice.model).foregroundStyle(.primary); Spacer(); if selected == choice { Image(systemName: "checkmark") } }
                        }
                    }
                }
            }
        }.navigationTitle("Studio models").searchable(text: $search, prompt: "Search models and providers")
            .overlay { if choices.isEmpty { ContentUnavailableView("No models loaded", systemImage: "cpu", description: Text("Check your Studio connection and reload its model catalog.")) } }
    }
}
