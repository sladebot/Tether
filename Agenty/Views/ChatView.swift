import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var input = ""
    @State private var showingConnections = false
    @State private var showingHistory = false
    @State private var showingModels = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        connectionStatus
                        if let approval = model.pendingApproval { ApprovalCard(approval: approval) }
                        if model.messages.isEmpty { emptyState }
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
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.messages) { _, messages in
                    if let last = messages.last { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Conversations", systemImage: "line.3.horizontal") { showingHistory = true }
                }
                ToolbarItem(placement: .principal) {
                    Button { showingModels = true } label: {
                        HStack(spacing: 5) {
                            Text(model.selectedModelChoice?.model.split(separator: "/").last.map(String.init) ?? "Agenty")
                                .font(.headline).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(model.selectedConnection?.transport != .apiServer)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") { model.newConversation() }
                        .disabled(model.selectedConnection == nil)
                }
            }
            .sheet(isPresented: $showingConnections) { NavigationStack { ConnectionListView() } }
            .sheet(isPresented: $showingHistory) { ConversationDrawer(showingConnections: $showingConnections) }
            .sheet(isPresented: $showingModels) { ModelPickerView() }
            .task(id: model.selectedConnectionID) { await model.checkSelectedConnection() }
        }
    }

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
                    Label("Offline — tap to retry", systemImage: "exclamationmark.triangle.fill").statusPill(color: .orange)
                }.accessibilityHint(message)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if model.selectedConnection == nil {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 36)).foregroundStyle(.tint)
                Text("Connect to Hermes").font(.title2.bold())
                Text("Add your local or Tailscale gateway to start chatting.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Set Up Connection") { showingConnections = true }.buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(.tint)
                Text("What can I help with?").font(.title2.bold())
                Text("Agenty can use Hermes tools and delegate work while keeping progress neatly tucked away.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }.frame(maxWidth: .infinity).padding(.top, 100)
    }

    private var composer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message Agenty", text: $input, axis: .vertical)
                    .lineLimit(1...7).textFieldStyle(.plain).padding(.leading, 16).padding(.vertical, 12).onSubmit(submit)
                if model.isResponding {
                    Button(action: model.stop) { Image(systemName: "stop.fill").font(.caption).frame(width: 34, height: 34) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.circle).padding(.trailing, 6).padding(.bottom, 5)
                } else {
                    Button(action: submit) { Image(systemName: "arrow.up").font(.headline).frame(width: 34, height: 34) }
                        .buttonStyle(.borderedProminent).buttonBorderShape(.circle).padding(.trailing, 6).padding(.bottom, 5)
                        .disabled(model.selectedConnection == nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
            Text("Agenty may make mistakes. Check important results.").font(.caption2).foregroundStyle(.tertiary).padding(.top, 5)
        }.padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4).background(.bar)
    }

    private func submit() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !model.isResponding else { return }
        input = ""
        model.send(value)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let pending: Bool
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user { Spacer(minLength: 46) }
            if message.role == .assistant {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { Image(systemName: "sparkles").foregroundStyle(.tint); Text("Agenty").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                    if message.content.isEmpty && pending {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Working…") }.foregroundStyle(.secondary)
                    } else { Text(message.content).textSelection(.enabled) }
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
        }.padding(12).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
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
                        Button(label(for: choice)) { model.resolveApproval(choice) }.buttonStyle(.borderedProminent)
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
    @Environment(\.dismiss) private var dismiss
    @Binding var showingConnections: Bool
    var body: some View {
        NavigationStack {
            List {
                Button { model.newConversation(); dismiss() } label: { Label("New chat", systemImage: "square.and.pencil") }
                Section("Recent") {
                    ForEach(model.conversations) { conversation in
                        Button { model.selectConversation(conversation); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.title).lineLimit(1).foregroundStyle(.primary)
                                    Text(conversation.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if conversation.pendingRun != nil { ProgressView().controlSize(.small) }
                                if conversation.id == model.selectedConversationID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                        }
                    }.onDelete { offsets in for index in offsets { model.deleteConversation(model.conversations[index]) } }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Connections") { dismiss(); showingConnections = true } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }.presentationDetents([.medium, .large])
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
