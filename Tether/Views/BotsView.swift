import SwiftUI

enum TetherTab: Hashable { case home, chat, bots, library }

struct BotAvatar: View {
    let bot: Bot
    var size: CGFloat = 48
    var body: some View {
        Image(systemName: bot.symbol)
            .font(.system(size: size * 0.38, weight: .medium))
            .frame(width: size, height: size)
            .foregroundStyle(.teal)
            .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.32))
            .accessibilityHidden(true)
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var bots: BotStore
    @Binding var tab: TetherTab
    @State private var connections = false
    @State private var composing = false
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A little more\nheadspace.")
                            .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                        Text("Bring an idea. Hand off a task. Your Studio takes it from here.")
                            .font(.body).foregroundStyle(.secondary)
                    }.padding(.top, 16)

                    Button {
                        if model.connections.isEmpty { connections = true }
                        else if bots.bots.isEmpty { tab = .bots }
                        else { draft = ""; composing = true }
                    } label: {
                        HStack {
                            Text(bots.bots.isEmpty ? "Meet your first bot" : "Give a bot a task")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                        }.padding(4)
                    }.buttonStyle(TetherPrimaryButtonStyle())

                    if !bots.activeTasks.isEmpty {
                        sectionTitle("In motion", detail: "\(bots.activeTasks.count) tasks")
                        VStack(spacing: 12) {
                            ForEach(bots.activeTasks.sorted { $0.updatedAt > $1.updatedAt }) { task in
                                NavigationLink { BotTaskDetailView(taskID: task.id) } label: {
                                    BotTaskRow(task: task, bot: bots.bot(task.botID))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    if bots.tasks.isEmpty {
                        sectionTitle("Make room for what matters", detail: nil)
                        VStack(spacing: 0) {
                            idea("Research something", subtitle: "A clear brief, with sources", symbol: "sparkle.magnifyingglass", prompt: "Research this topic and give me a concise brief with sources: ")
                            Divider().padding(.leading, 56)
                            idea("Turn an idea into a plan", subtitle: "Practical steps you can act on", symbol: "list.bullet.clipboard", prompt: "Help me turn this goal into a practical plan: ")
                            Divider().padding(.leading, 56)
                            idea("Build a little tool", subtitle: "Something useful, just for you", symbol: "square.grid.2x2", prompt: nil)
                        }.background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
                    } else {
                        let finished = bots.tasks.filter { $0.state.isTerminal }.sorted { $0.updatedAt > $1.updatedAt }
                        if !finished.isEmpty {
                            sectionTitle("Ready when you are", detail: nil)
                            ForEach(Array(finished.prefix(5))) { task in
                                NavigationLink { BotTaskDetailView(taskID: task.id) } label: {
                                    BotTaskRow(task: task, bot: bots.bot(task.botID))
                                }.buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Label("Powered by your Studio", systemImage: "desktopcomputer").font(.subheadline.weight(.semibold))
                        Text("Once Hermes accepts a task, it keeps working when you close Tether. Come back here for results and approvals.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(.bottom, 16)
                }.padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Tether").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { connections = true } label: { Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44) }
                        .accessibilityLabel("Studio connections")
                }
            }
            .sheet(isPresented: $connections) { NavigationStack { ConnectionListView() } }
            .sheet(isPresented: $composing) { NavigationStack { BotTaskComposer(initialRequest: draft) } }
        }
    }

    private func sectionTitle(_ title: String, detail: String?) -> some View {
        HStack {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func idea(_ title: String, subtitle: String, symbol: String, prompt: String?) -> some View {
        Button {
            guard let prompt else { tab = .library; return }
            if bots.bots.isEmpty { tab = .bots }
            else { draft = prompt; composing = true }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title3).frame(width: 24).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct BotsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: BotStore
    @State private var creating = false
    @State private var connections = false
    @State private var search = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.bots.isEmpty {
                    ContentUnavailableView {
                        Label("Your own small team", systemImage: "person.2.wave.2")
                    } description: {
                        Text("Give each bot a role and a model. Delegate work to your Studio, then pick up the results here.")
                    } actions: {
                        Button(model.connections.contains { $0.transport == .apiServer } ? "Create a bot" : "Connect your Studio") {
                            if model.connections.contains(where: { $0.transport == .apiServer }) { creating = true }
                            else { connections = true }
                        }.buttonStyle(TetherPrimaryButtonStyle())
                    }
                } else {
                    List {
                        Section {
                            ForEach(store.bots.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { bot in
                                NavigationLink { BotDetailView(botID: bot.id) } label: {
                                    HStack(spacing: 16) {
                                        BotAvatar(bot: bot)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(bot.name).font(.headline)
                                            Text(bot.modelLabel).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                            if let task = store.history(for: bot.id).first { Text(task.state.title).font(.caption).foregroundStyle(task.state == .awaitingApproval ? .orange : .secondary) }
                                        }.padding(.vertical, 8)
                                    }
                                }
                            }
                        } footer: { Text("Each bot keeps its own context. Model changes apply to future tasks.") }
                    }.searchable(text: $search, prompt: "Find a bot")
                }
            }
            .navigationTitle("Bots")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create bot", systemImage: "plus") { creating = true }
                        .disabled(!model.connections.contains { $0.transport == .apiServer })
                }
            }
            .sheet(isPresented: $creating) { NavigationStack { BotEditorView() } }
            .sheet(isPresented: $connections) { NavigationStack { ConnectionListView() } }
        }
    }
}

struct BotDetailView: View {
    @EnvironmentObject private var store: BotStore
    @Environment(\.dismiss) private var dismiss
    let botID: UUID
    @State private var editing = false
    @State private var composing = false
    @State private var deleting = false

    var body: some View {
        Group {
            if let bot = store.bot(botID) {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 16) {
                            BotAvatar(bot: bot, size: 64)
                            Text(bot.instructions.isEmpty ? "Ready to help with your next task." : bot.instructions).font(.body)
                            Label(bot.modelLabel, systemImage: "cpu").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 12)
                        Button("Give \(bot.name) a task", systemImage: "plus.bubble") { composing = true }.frame(minHeight: 44)
                    }
                    Section("Tasks") {
                        if store.history(for: botID).isEmpty { Text("Start with something you’d like off your plate.").foregroundStyle(.secondary) }
                        ForEach(store.history(for: botID)) { task in
                            NavigationLink { BotTaskDetailView(taskID: task.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(task.request).lineLimit(3)
                                    TaskStatusLabel(task: task)
                                }.padding(.vertical, 8)
                            }
                        }
                    }
                }
                .navigationTitle(bot.name)
                .toolbar {
                    Menu {
                        Button("Edit bot", systemImage: "slider.horizontal.3") { editing = true }
                        Button("Delete bot", systemImage: "trash", role: .destructive) { deleting = true }
                            .disabled(store.activeTasks.contains { $0.botID == botID })
                    } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }
                }
                .sheet(isPresented: $editing) { NavigationStack { BotEditorView(existing: bot) } }
                .sheet(isPresented: $composing) { NavigationStack { BotTaskComposer(botID: botID) } }
                .confirmationDialog("Delete \(bot.name) and its local task history?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete bot", role: .destructive) { store.delete(bot); dismiss() }
                }
            } else { ContentUnavailableView("Bot removed", systemImage: "person.crop.circle.badge.minus") }
        }
    }
}

struct BotEditorView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: BotStore
    @Environment(\.dismiss) private var dismiss
    var existing: Bot?
    @State private var name = ""
    @State private var instructions = ""
    @State private var symbol = "sparkles"
    @State private var connectionID: UUID?
    @State private var choice: ModelChoice?
    @State private var models: [ModelChoice] = []
    @State private var loading = false
    @State private var loadError: String?
    @State private var initialized = false

    var body: some View {
        Form {
            Section("Your bot") {
                TextField("Name", text: $name)
                TextField("What should this bot help you with?", text: $instructions, axis: .vertical).lineLimit(3...8)
                Picker("Icon", selection: $symbol) {
                    Label("General", systemImage: "sparkles").tag("sparkles")
                    Label("Research", systemImage: "magnifyingglass").tag("magnifyingglass")
                    Label("Writing", systemImage: "pencil.line").tag("pencil.line")
                    Label("Building", systemImage: "hammer").tag("hammer")
                    Label("Planning", systemImage: "calendar").tag("calendar")
                }
            }
            Section {
                Picker("Studio", selection: $connectionID) {
                    Text("Choose a connection").tag(nil as UUID?)
                    ForEach(model.connections.filter { $0.transport == .apiServer }) { connection in
                        Text(connection.name).tag(Optional(connection.id))
                    }
                }.disabled(existing != nil)
                NavigationLink {
                    BotModelPicker(choices: models, choice: $choice)
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Provider & model")
                        Text(choice.map { "\($0.providerName) · \($0.model)" } ?? "Hermes default")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(loading || connectionID == nil)
                if loading { ProgressView("Reading models from Studio…") }
                if let loadError {
                    Text(loadError).font(.footnote).foregroundStyle(.secondary)
                    Button("Reload models") { Task { await loadModels() } }
                }
            } header: { Text("Where it works") } footer: {
                Text("Every bot can use a different provider and model. Provider sign-ins stay on Hermes. Changes apply to new tasks; queued and running tasks keep their original settings.")
            }
        }
        .navigationTitle(existing == nil ? "Create a bot" : "Edit bot")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let connectionID else { return }
                    let bot = Bot(id: existing?.id ?? UUID(), connectionID: connectionID,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines), instructions: instructions,
                        symbol: symbol, model: choice, createdAt: existing?.createdAt ?? .now)
                    if store.save(bot) { dismiss() }
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connectionID == nil)
            }
        }
        .onAppear {
            guard !initialized else { return }
            initialized = true
            name = existing?.name ?? ""
            instructions = existing?.instructions ?? ""
            symbol = existing?.symbol ?? "sparkles"
            choice = existing?.model
            connectionID = existing?.connectionID ?? model.selectedConnection.flatMap { $0.transport == .apiServer ? $0.id : nil }
        }
        .task(id: connectionID) { await loadModels() }
        .onChange(of: connectionID) { old, _ in if old != nil && existing == nil { choice = nil } }
    }

    private func loadModels() async {
        guard let connection = model.connections.first(where: { $0.id == connectionID }) else { return }
        loading = true; loadError = nil; models = []
        do {
            let result = try await HermesAPIClient(connection: connection, apiKey: model.apiKey(for: connection), session: HermesAPIClient.diagnosticSession).modelOptions()
            guard !Task.isCancelled, connectionID == connection.id else { return }
            models = result
            if result.isEmpty { loadError = "No signed-in providers were returned. Configure providers on Hermes, then reload." }
        } catch {
            guard !Task.isCancelled, connectionID == connection.id else { return }
            loadError = error.localizedDescription
        }
        loading = false
    }
}

private struct BotModelPicker: View {
    let choices: [ModelChoice]
    @Binding var choice: ModelChoice?
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [ModelChoice] { choices.filter { search.isEmpty || $0.model.localizedCaseInsensitiveContains(search) || $0.providerName.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            Button { choice = nil; dismiss() } label: { row("Hermes default", selected: choice == nil) }
            ForEach(Dictionary(grouping: filtered, by: \.provider).keys.sorted(), id: \.self) { provider in
                Section(filtered.first { $0.provider == provider }?.providerName ?? provider) {
                    ForEach(filtered.filter { $0.provider == provider }) { item in
                        Button { choice = item; dismiss() } label: { row(item.model, selected: choice == item) }
                    }
                }
            }
        }.navigationTitle("Provider & model").searchable(text: $search, prompt: "Search providers or models")
    }
    private func row(_ title: String, selected: Bool) -> some View {
        HStack { Text(title).foregroundStyle(.primary); Spacer(); if selected { Image(systemName: "checkmark") } }
    }
}

struct BotTaskComposer: View {
    @EnvironmentObject private var store: BotStore
    @Environment(\.dismiss) private var dismiss
    var botID: UUID?
    var initialRequest = ""
    @State private var selected: UUID?
    @State private var request = ""
    var body: some View {
        Form {
            Section {
                Picker("Bot", selection: $selected) {
                    Text("Choose a bot").tag(nil as UUID?)
                    ForEach(store.bots) { Text($0.name).tag(Optional($0.id)) }
                }
                if let bot = selected.flatMap(store.bot) {
                    Text(bot.modelLabel).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("What would you like done?") {
                TextField("Describe the outcome you want…", text: $request, axis: .vertical).lineLimit(6...14)
            }
            Section {
                Button("Delegate task", systemImage: "arrow.up.right") {
                    guard let bot = selected.flatMap(store.bot) else { return }
                    if store.enqueue(request, for: bot) != nil { dismiss() }
                }.disabled(selected == nil || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: { Text("Saved before sending. Once accepted, Hermes keeps working on your Studio even when Tether is closed. Approvals appear when you return.") }
        }
        .navigationTitle("New task").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { selected = botID ?? store.bots.first?.id; request = initialRequest }
    }
}

struct BotTaskRow: View {
    let task: BotTask
    let bot: Bot?
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            if let bot { BotAvatar(bot: bot, size: 40) }
            VStack(alignment: .leading, spacing: 8) {
                Text(bot?.name ?? "Bot").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(task.request).font(.subheadline.weight(.medium)).lineLimit(3)
                TaskStatusLabel(task: task)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }
}

struct TaskStatusLabel: View {
    let task: BotTask
    var body: some View {
        Label(task.state.title, systemImage: task.state == .completed ? "checkmark.circle" : (task.state == .awaitingApproval || task.state == .needsAttention ? "hand.raised" : "circle.dotted"))
            .font(.caption).foregroundStyle(task.state == .awaitingApproval || task.state == .needsAttention ? .orange : .secondary)
    }
}

struct BotTaskDetailView: View {
    @EnvironmentObject private var store: BotStore
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @State private var guidance = ""
    @State private var sending = false
    @State private var forgetting = false

    var body: some View {
        Group {
            if let task = store.task(taskID) {
                List {
                    Section {
                        Text(task.request).font(.title3.weight(.medium)).textSelection(.enabled)
                        TaskStatusLabel(task: task)
                        Text(task.model.map { "\($0.providerName) · \($0.model)" } ?? "Hermes default")
                            .font(.caption).foregroundStyle(.secondary)
                        if let detail = task.detail { Text(detail).font(.footnote).foregroundStyle(.secondary) }
                    }
                    if let approval = task.approval, !task.stopRequested {
                        Section("Your approval") {
                            Text(approval.command).font(.callout.monospaced()).textSelection(.enabled)
                            ForEach(approval.choices, id: \.self) { choice in
                                Button(choice == "once" ? "Allow once" : choice.capitalized) { Task { await store.approve(taskID, choice: choice) } }
                                    .disabled(store.resolvingApprovals.contains(taskID))
                            }
                        }
                    }
                    if !task.output.isEmpty {
                        Section("Result") { Text(.init(task.output)).textSelection(.enabled) }
                    }
                    if !task.activities.isEmpty {
                        Section("Activity") {
                            ForEach(task.activities.reversed()) { activity in
                                VStack(alignment: .leading, spacing: 6) {
                                    Label(activity.title, systemImage: activity.state == .completed ? "checkmark.circle" : "circle.dotted").font(.subheadline)
                                    if let detail = activity.detail { Text(detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                                }.padding(.vertical, 4)
                            }
                        }
                    }
                    if task.state == .needsAttention {
                        Section {
                            Button("Check original task") { store.retry(taskID) }
                            Button("Forget saved task", role: .destructive) { forgetting = true }
                        }
                    } else if !task.state.isTerminal {
                        if task.runID != nil && !task.stopRequested {
                            Section("Guide this task") {
                                TextField("Add instructions…", text: $guidance, axis: .vertical).lineLimit(2...6)
                                Button("Send instructions") {
                                    sending = true
                                    Task { if await store.steer(taskID, input: guidance) { guidance = "" }; sending = false }
                                }.disabled(sending || guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        Section {
                            Button(task.stopRequested ? "Waiting for Hermes to stop…" : "Stop task", role: .destructive) { store.stop(taskID) }
                                .disabled(task.stopRequested)
                        } footer: { Text("Stopping is confirmed by Hermes. A disconnected phone cannot immediately stop remote work.") }
                    }
                }
                .navigationTitle(store.bot(task.botID)?.name ?? "Task").navigationBarTitleDisplayMode(.inline)
                .confirmationDialog("Forget this saved task?", isPresented: $forgetting, titleVisibility: .visible) {
                    Button("Forget task", role: .destructive) { store.forget(taskID); dismiss() }
                } message: { Text("This only removes the local checkpoint. It does not stop remote work. Check Hermes before submitting the same task again.") }
            } else { ContentUnavailableView("Task removed", systemImage: "tray") }
        }
    }
}
