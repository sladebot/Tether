import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composerFocused: Bool
    @State private var input = ""
    @State private var showingConnections = false
    @State private var showingHistory = false
    @State private var showingModels = false
    @State private var showingMiniApps = false
    @State private var showingSteer = false
    @State private var instructions = ""
    @State private var sendingInstructions = false
    @State private var referencedApp: MiniApp?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        connectionStatus
                        if let approval = model.pendingApproval { ApprovalCard(approval: approval) }
                        ForEach(model.messages) { message in
                            if message.role == .assistant {
                                let activities = model.activities(for: message.turnID)
                                if !activities.isEmpty { AgentProgressCard(activities: activities) }
                            }
                            MessageRow(message: message, pending: isPending(message)).id(message.id)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .defaultScrollAnchor(.top)
                .scrollDismissesKeyboard(.interactively)
                .overlay { if model.messages.isEmpty { emptyState } }
                .onChange(of: model.messages) { _, messages in
                    if let last = messages.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .safeAreaInset(edge: .top, spacing: 0) { chatHeader }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingConnections) { NavigationStack { ConnectionListView() } }
            .sheet(isPresented: $showingMiniApps) {
                MiniAppsView()
            }
            .sheet(isPresented: $showingModels) { ModelPickerView() }
            .sheet(isPresented: $showingSteer) {
                NavigationStack {
                    Form {
                        TextField("Additional instructions", text: $instructions, axis: .vertical).lineLimit(4...8)
                        Button("Send instructions") {
                            sendingInstructions = true
                            Task {
                                if await model.steer(instructions) { instructions = ""; showingSteer = false }
                                sendingInstructions = false
                            }
                        }.disabled(sendingInstructions || instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }.navigationTitle("Guide this task")
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingSteer = false } } }
                }.presentationDetents([.medium, .large])
            }
            .task(id: model.selectedConnectionID) { await model.checkSelectedConnection() }
        }
        .accessibilityHidden(showingHistory)
        .overlay(alignment: .leading) {
            if showingHistory {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Color.black.opacity(0.3).ignoresSafeArea()
                            .onTapGesture { closeHistory() }
                            .accessibilityHidden(true)
                        ConversationDrawer(onClose: closeHistory, onConnections: {
                            closeHistory(); showingConnections = true
                        }, onMiniApps: {
                            closeHistory(); showingMiniApps = true
                        })
                        .frame(width: min(geometry.size.width * 0.86, 360))
                        .background(Color(.systemBackground))
                        .transition(.move(edge: .leading))
                        .accessibilityAddTraits(.isModal)
                    }
                }
            }
        }
    }

    private var chatHeader: some View {
        HStack {
            Button {
                composerFocused = false
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { showingHistory = true }
            } label: {
                Image(systemName: "line.3.horizontal").font(.system(size: 21, weight: .medium))
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }.accessibilityLabel("Conversations").accessibilityIdentifier("chat.conversations")
            Spacer(minLength: 8)
            Button { composerFocused = false; showingModels = true } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text(model.selectedConnection?.providerKind.title ?? "Tether").font(.headline)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    if let choice = model.selectedModelChoice {
                        Text(choice.model).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }.accessibilityLabel("Choose model").accessibilityIdentifier("chat.models")
            Spacer(minLength: 8)
            Button {
                composerFocused = false
                if model.selectedConnection == nil { showingConnections = true }
                else { model.newConversation(); input = "" }
            } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 21, weight: .medium))
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }.accessibilityLabel("New chat").accessibilityIdentifier("chat.new")
        }.buttonStyle(.plain).foregroundStyle(.primary)
            .padding(.horizontal, 8).background(Color(.systemBackground))
    }

    private func closeHistory() { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { showingHistory = false } }

    private func isPending(_ message: ChatMessage) -> Bool {
        model.selectedConversation?.pendingRun?.assistantMessageID == message.id
    }

    @ViewBuilder private var connectionStatus: some View {
        if model.selectedConversation?.pendingRun?.state == .waitingForNetwork || !model.isNetworkAvailable {
            Label("Offline — this run will resume automatically", systemImage: "arrow.clockwise.icloud")
                .statusPill(color: .orange)
        } else {
            switch model.connectionState {
            case .idle, .testing:
                Label("Connecting…", systemImage: "circle.dotted").statusPill(color: .secondary)
            case .connected:
                EmptyView()
            case let .failed(message):
                Button { Task { await model.checkSelectedConnection() } } label: {
                    VStack(spacing: 6) {
                        Label("Connection unavailable · Retry", systemImage: "exclamationmark.triangle.fill")
                        Text(message).font(.caption).multilineTextAlignment(.center)
                    }.statusPill(color: .orange)
                }.accessibilityHint(message)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if model.selectedConnection == nil {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 36)).foregroundStyle(.tint)
                Text("Connect to Hermes").font(.title2.bold())
                Text("Add Hermes with its Tailscale URL and API token to start chatting.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Add provider") { showingConnections = true }.buttonStyle(TetherPrimaryButtonStyle())
            } else {
                Text("What can I help with?").font(.system(size: 28, weight: .semibold))
            }
        }.frame(maxWidth: .infinity).padding(.horizontal, 28)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if let app = referencedApp {
                    HStack {
                        Label(app.title, systemImage: "app.dashed").font(.subheadline)
                        Button("Remove", systemImage: "xmark.circle") { referencedApp = nil }.labelStyle(.iconOnly)
                    }.padding(.horizontal, 8)
                }
                if input.split(separator: " ", omittingEmptySubsequences: false).last?.hasPrefix("@") == true {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(model.miniApps.filter { app in
                                let query = String(input.split(separator: " ", omittingEmptySubsequences: false).last?.dropFirst() ?? "".dropFirst())
                                return query.isEmpty || app.title.localizedCaseInsensitiveContains(query)
                            }) { app in
                                Button("@\(app.title)") {
                                    referencedApp = app
                                    if let range = input.range(of: "@", options: .backwards) { input.replaceSubrange(range.lowerBound..., with: "@\(app.title) ") }
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                }
                TextField("Message Tether", text: $input, axis: .vertical)
                    .focused($composerFocused).accessibilityIdentifier("chat.input")
                    .lineLimit(1...7).textFieldStyle(.plain).padding(.horizontal, 8).padding(.top, 8).onSubmit(submit)
                HStack {
                    Menu {
                        if model.isResponding {
                            Button("Add instructions", systemImage: "text.bubble") { showingSteer = true }
                        }
                        Button("Mini apps", systemImage: "square.grid.2x2") { showingMiniApps = true }
                        Button("Choose model", systemImage: "slider.horizontal.3") { showingModels = true }
                        Button("Providers", systemImage: "network") { showingConnections = true }
                    } label: {
                        Image(systemName: "plus").font(.system(size: 22)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.accessibilityLabel("Chat options")
                    Spacer()
                if model.isResponding {
                    Button(action: model.stop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                            .frame(width: 44, height: 44)
                            .background(colorScheme == .dark ? Color.white : Color.black, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Stop response")
                } else {
                    Button(action: submit) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 21, weight: .bold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(canSend ? (colorScheme == .dark ? Color.black : Color.white) : Color.secondary)
                            .frame(width: 44, height: 44)
                            .background(canSend ? (colorScheme == .dark ? Color.white : Color.black) : Color(.tertiarySystemFill), in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Send message")
                        .accessibilityIdentifier("chat.send")
                        .disabled(!canSend)
                }
                }
            }.padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 28))
            Text("Tether may make mistakes. Check important results.").font(.caption2).foregroundStyle(.tertiary).padding(.top, 5)
        }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6).background(Color(.systemBackground))
    }

    private var canSend: Bool {
        model.selectedConnection != nil && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !value.isEmpty, !model.isResponding else { return }
        input = ""
        model.send(value, referencing: referencedApp)
        referencedApp = nil
    }
}

private struct MessageRow: View {
    @State private var copied = false
    let message: ChatMessage
    let pending: Bool
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 46) }
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 8) {
                    if message.content.isEmpty && pending {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Working…") }.foregroundStyle(.secondary)
                    } else {
                        Text(.init(message.content)).textSelection(.enabled).lineSpacing(5)
                        if !pending {
                            Button { UIPasteboard.general.string = message.content; copied = true } label: {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(copied ? "Copied" : "Copy response")
                        }
                    }
                }
                Spacer(minLength: 24)
            } else {
                Text(message.content).textSelection(.enabled).padding(.horizontal, 15).padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            }
        }.frame(maxWidth: .infinity)
    }
}

private struct AgentProgressCard: View {
    let activities: [AgentActivity]
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(activities) { activity in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: symbol(for: activity.state)).foregroundStyle(color(for: activity.state)).frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.title).font(.subheadline.weight(.medium))
                            if let detail = activity.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                        }
                    }
                }
            }.padding(.top, 12)
        } label: {
            HStack {
                Image(systemName: activities.contains(where: { $0.state == .running }) ? "gearshape.2" : "checkmark.circle")
                Text(activities.contains(where: { $0.state == .running }) ? "Agent progress" : "Work completed")
                Spacer(); Text("\(activities.count)").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline.weight(.medium))
        }.foregroundStyle(.secondary).padding(.vertical, 6)
    }
    private func symbol(for state: AgentActivity.State) -> String {
        switch state { case .running: "circle.dotted"; case .completed: "checkmark.circle.fill"; case .failed: "xmark.circle.fill" }
    }
    private func color(for state: AgentActivity.State) -> Color {
        switch state { case .running: .accentColor; case .completed: .green; case .failed: .red }
    }
}

private struct ApprovalCard: View {
    @EnvironmentObject private var model: AppModel
    let approval: RunApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Permission required", systemImage: "hand.raised.fill").font(.headline).foregroundStyle(.orange)
            Text(approval.command).font(.subheadline).textSelection(.enabled)
            HStack {
                ForEach(approval.choices, id: \.self) { choice in
                    if choice == "deny" {
                        Button(label(for: choice)) { model.resolveApproval(choice) }.buttonStyle(.bordered)
                    } else {
                        Button(label(for: choice)) { model.resolveApproval(choice) }.buttonStyle(TetherPrimaryButtonStyle())
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private func label(for choice: String) -> String {
        switch choice {
        case "once": "Allow once"
        case "session": "This chat"
        case "always": "Always"
        case "deny": "Deny"
        default: choice.capitalized
        }
    }
}

private struct ConversationDrawer: View {
    @EnvironmentObject private var model: AppModel
    let onClose: () -> Void
    let onConnections: () -> Void
    let onMiniApps: () -> Void
    @State private var search = ""
    private var conversations: [Conversation] {
        model.conversations.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Tether").font(.title2.weight(.semibold))
                Spacer()
                Button("Close", systemImage: "xmark", action: onClose).labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }.padding(.horizontal, 20)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search chats", text: $search)
            }.padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12)).padding(.horizontal, 16)
            List {
                Button { model.newConversation(); onClose() } label: { Label("New chat", systemImage: "square.and.pencil") }
                Button(action: onMiniApps) { Label("Mini apps", systemImage: "square.grid.2x2") }
                Section("Recent") {
                    if conversations.isEmpty {
                        Text(search.isEmpty ? "Your conversations will appear here." : "No chats match your search.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(conversations) { conversation in
                        Button { model.selectConversation(conversation); onClose() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title).lineLimit(1).foregroundStyle(.primary)
                                }
                                Spacer()
                                if conversation.pendingRun != nil { ProgressView().controlSize(.small) }
                                if conversation.id == model.selectedConversationID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }.onDelete { offsets in
                        let selected = offsets.map { conversations[$0] }
                        for conversation in selected { model.deleteConversation(conversation) }
                    }
                }
            }.listStyle(.plain).scrollContentBackground(.hidden)
            Button(action: onConnections) {
                Label("Providers & settings", systemImage: "gearshape")
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
        }.padding(.top, 8)
    }
}

private struct ModelPickerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [ModelChoice] {
        guard !search.isEmpty else { return model.modelChoices }
        return model.modelChoices.filter { $0.model.localizedCaseInsensitiveContains(search) || $0.providerName.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            List {
                Button { model.selectModel(nil); dismiss() } label: {
                    modelRow(title: "Hermes default", subtitle: "Use the server’s configured model", selected: model.selectedModelChoice == nil)
                }
                ForEach(Dictionary(grouping: filtered, by: \.provider).keys.sorted(), id: \.self) { provider in
                    let choices = filtered.filter { $0.provider == provider }
                    Section(choices.first?.providerName ?? provider) {
                        ForEach(choices) { choice in
                            Button { model.selectModel(choice); dismiss() } label: {
                                modelRow(title: choice.model, subtitle: choice.provider, selected: model.selectedModelChoice == choice)
                            }
                        }
                    }
                }
            }
            .overlay { if model.isLoadingModels { ProgressView("Loading models…") } }
            .searchable(text: $search, prompt: "Search models")
            .task { await model.refreshModelChoices() }
            .navigationTitle("Model")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Refresh") { Task { await model.refreshModelChoices() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
    private func modelRow(title: String, subtitle: String, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) { Text(title).foregroundStyle(.primary); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(.tint) }
        }
    }
}

private extension View {
    func statusPill(color: Color) -> some View {
        self.font(.caption).foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 5).background(color.opacity(0.1), in: Capsule())
    }
}
