import SwiftUI

struct ChatView: View {
    let onSpaces: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(TetherAppearance.preferenceKey) private var appearance = TetherAppearance.system
    @FocusState private var composerFocused: Bool
    @State private var input = ""
    @State private var showingConnections = false
    @State private var addingServer = false
    @State private var showingModels = false
    @State private var showingSteer = false
    @State private var instructions = ""
    @State private var sendingInstructions = false
    @State private var referencedApp: MiniApp?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if model.selectedConnection != nil { connectionStatus }
                        if model.messages.isEmpty { welcome }
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
                .background(Studio.canvas)
                .onChange(of: model.messages) { _, messages in
                    if let last = messages.last { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    if let approval = model.pendingApproval {
                        ScrollView { ApprovalCard(approval: approval) }
                            .frame(maxHeight: 180).background(Studio.paper)
                    }
                    composer
                }.fixedSize(horizontal: false, vertical: true)
            }
            .safeAreaInset(edge: .top, spacing: 0) { chatHeader }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingConnections) { NavigationStack { ConnectionListView() } }
            .sheet(isPresented: $addingServer) { NavigationStack { ConnectionEditorView() } }
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
        }
        .onChange(of: model.selectedConversationID) { old, _ in
            if old != nil { input = ""; referencedApp = nil }
        }
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            Button { showingConnections = true } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted").frame(width: 44, height: 44)
                    .background(Studio.paper, in: Circle())
            }.accessibilityLabel("Connections")
            VStack(alignment: .leading, spacing: 1) {
                Text("Tether").font(.headline)
                Text(model.selectedConnection?.name ?? "Personal agent").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Picker("Appearance", selection: $appearance) {
                    ForEach(TetherAppearance.allCases, id: \.self) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
            } label: {
                Image(systemName: "circle.lefthalf.filled").frame(width: 44, height: 44)
            }.accessibilityLabel("Appearance").accessibilityValue(appearance.rawValue)
            if model.selectedConnection != nil {
                Button { model.newConversation(); composerFocused = false } label: {
                    Image(systemName: "square.and.pencil").frame(width: 44, height: 44)
                }.accessibilityLabel("New conversation")
            }
        }.foregroundStyle(Studio.ink).padding(.horizontal, 18).padding(.vertical, 4).background(Studio.canvas)
    }

    private func isPending(_ message: ChatMessage) -> Bool {
        model.selectedConversation?.pendingRun?.assistantMessageID == message.id
    }

    @ViewBuilder private var connectionStatus: some View {
        if model.selectedConversation?.pendingRun?.state == .waitingForNetwork || !model.isNetworkAvailable {
            Label("Offline — this run will resume automatically", systemImage: "arrow.clockwise.icloud")
                .statusPill(color: Studio.ink)
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
                    }.statusPill(color: Studio.ink)
                }.accessibilityHint(message)
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            AgentLoop().frame(height: 150).frame(maxWidth: .infinity)
            Text(model.selectedConnection == nil ? "Meet your agent." : "What’s on your mind?")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).foregroundStyle(Studio.ink)
            if model.selectedConnection == nil {
                Text("Bring your own model. Connect Tether to Hermes on your computer to start a conversation or build a personal tool.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Connect to Hermes") { addingServer = true }.buttonStyle(TetherPrimaryButtonStyle())
            } else {
                suggestion("Plan my day", icon: "sun.horizon") {
                    input = "Help me plan my day. Ask me about my priorities first."; composerFocused = true
                }
                suggestion("Think through an idea", icon: "lightbulb") {
                    input = "Help me think through an idea. Here’s what I have so far: "; composerFocused = true
                }
                suggestion("Build a personal tool", icon: "square.grid.2x2", action: onSpaces)
            }
        }.padding(10).frame(maxWidth: 560, alignment: .leading)
    }

    private func suggestion(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 28).foregroundStyle(Studio.accent)
                Text(title).font(.body.weight(.medium))
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }.foregroundStyle(Studio.ink).padding(.horizontal, 16).frame(minHeight: 48)
                .background(Studio.paper, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var composer: some View {
        if model.selectedConnection != nil {
            VStack(alignment: .leading, spacing: 4) {
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
                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Ask Tether…", text: $input, axis: .vertical)
                        .focused($composerFocused).accessibilityIdentifier("chat.input")
                        .lineLimit(1...6).textFieldStyle(.plain).padding(.horizontal, 8)
                        .frame(minHeight: 44).onSubmit(submit)
                    if model.isResponding {
                        Button(action: model.stop) {
                            Image(systemName: "stop.fill").frame(width: 44, height: 44)
                                .background(Studio.accent, in: Circle()).foregroundStyle(Studio.paper)
                        }.accessibilityLabel(model.selectedConversation?.pendingRun?.stopRequested != true ? "Stop response" : "Stopping response")
                            .disabled(model.selectedConversation?.pendingRun?.stopRequested == true)
                    } else {
                        Button(action: submit) {
                            Image(systemName: "arrow.up").font(.headline).frame(width: 44, height: 44)
                                .background(canSend ? Studio.accent : Studio.wash, in: Circle())
                                .foregroundStyle(canSend ? Studio.paper : Studio.accent)
                        }.accessibilityLabel("Send message").accessibilityIdentifier("chat.send").disabled(!canSend)
                    }
                }.buttonStyle(.plain)
                HStack(spacing: 12) {
                    if model.selectedConnection?.transport == .apiServer {
                        Button { showingModels = true } label: {
                            Label(model.selectedModelChoice?.model ?? model.defaultModelName ?? "Hermes default", systemImage: "cpu")
                                .lineLimit(1).frame(minHeight: 44)
                        }.accessibilityLabel("Choose model")
                    }
                    Spacer()
                    if model.selectedConversation?.pendingRun?.runID != nil {
                        Button("Guide task", systemImage: "text.bubble") { showingSteer = true }
                    }
                    if !model.miniApps.isEmpty {
                        Menu {
                            ForEach(model.miniApps) { app in
                                Button(app.title) { referencedApp = app; composerFocused = true }
                            }
                        } label: { Image(systemName: "paperclip").frame(width: 44, height: 44) }
                        .accessibilityLabel("Reference a space")
                    }
                }.font(.caption.weight(.medium)).padding(.leading, 8)
            }.padding(10).background(Studio.paper, in: RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(Studio.accent.opacity(0.16)) }
                .padding(.horizontal, 14).padding(.vertical, 6).background(Studio.canvas)
        }
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
                    HStack(spacing: 6) {
                        AgentLoop().frame(width: 26, height: 26)
                        Text("Tether").font(.subheadline.bold()).foregroundStyle(Studio.ink)
                    }
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
                    .background(Studio.wash, in: RoundedRectangle(cornerRadius: 18))
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
                        Image(systemName: symbol(for: activity.state)).foregroundStyle(Studio.ink).frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(activity.title).font(.subheadline.weight(.medium))
                            if let detail = activity.detail, !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(4) }
                        }
                    }
                }
            }.padding(.top, 12)
        } label: {
            HStack {
                Image(systemName: "list.bullet.indent")
                Text(activities.contains(where: { $0.state == .failed }) ? "Review task activity" : "Task activity")
                Spacer(); Text("\(activities.count)").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline.weight(.medium))
        }.foregroundStyle(.secondary).padding(.vertical, 6)
    }
    private func symbol(for state: AgentActivity.State) -> String {
        switch state { case .running: "circle.dotted"; case .completed: "checkmark.circle.fill"; case .failed: "xmark.circle.fill" }
    }

}

private struct ApprovalCard: View {
    @EnvironmentObject private var model: AppModel
    let approval: RunApproval

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Permission required", systemImage: "hand.raised.fill").font(.headline).foregroundStyle(Studio.ink)
            Text(approval.command).font(.subheadline).textSelection(.enabled)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125))]) {
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
        .background(Studio.wash, in: RoundedRectangle(cornerRadius: 16))
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

struct TaskHistory: View {
    @EnvironmentObject private var model: AppModel
    let open: () -> Void
    @State private var search = ""

    private var tasks: [Conversation] {
        model.conversations.filter { !$0.messages.isEmpty && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(tasks) { task in
                    Button {
                        model.selectConversation(task)
                        open()
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: task.pendingRun == nil ? "bubble.left.and.text.bubble.right" : "hourglass")
                                .foregroundStyle(Studio.accent).frame(width: 40, height: 46)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title).font(.headline).foregroundStyle(Studio.ink).lineLimit(2)
                                if task.pendingRun != nil { Text("In progress").font(.caption) }
                                else { Text(task.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }.listRowBackground(Studio.paper)
                }.onDelete { offsets in
                    let removed = offsets.map { tasks[$0] }
                    for task in removed { model.deleteConversation(task) }
                }
            }
            .scrollContentBackground(.hidden).background(Studio.canvas)
            .overlay {
                if tasks.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView {
                            Label("Your activity", systemImage: "clock.arrow.circlepath")
                        } description: { Text("Return to conversations and follow work in progress here.") }
                          actions: { Button("Open agent", action: open).buttonStyle(TetherPrimaryButtonStyle()) }
                    } else { ContentUnavailableView.search(text: search) }
                }
            }
            .searchable(text: $search, prompt: "Find a conversation")
            .navigationTitle("Activity")
        }
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
                    modelRow(title: "Hermes default", subtitle: model.defaultModelName ?? "Use the server’s configured model", selected: model.selectedModelChoice == nil)
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
            .scrollContentBackground(.hidden).background(Studio.canvas)
            .navigationTitle("Model for this chat")
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
