import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var model: AppModel
    @State private var input = ""
    @State private var showingConnections = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        connectionStatus
                        if model.messages.isEmpty { emptyState }
                        ForEach(model.messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: model.messages) { _, messages in
                    if let last = messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle(model.selectedConnection?.name ?? "Hermes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Connections", systemImage: "network") { showingConnections = true }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") { model.clearChat() }
                        .disabled(model.messages.isEmpty)
                }
            }
            .sheet(isPresented: $showingConnections) { NavigationStack { ConnectionListView() } }
            .task(id: model.selectedConnectionID) { await model.checkSelectedConnection() }
        }
    }

    @ViewBuilder private var connectionStatus: some View {
        switch model.connectionState {
        case .idle, .testing:
            Label("Connecting…", systemImage: "circle.dotted")
                .font(.caption).foregroundStyle(.secondary)
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundStyle(.green)
        case let .failed(message):
            Button { Task { await model.checkSelectedConnection() } } label: {
                Label("Offline — tap to retry", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            .accessibilityHint(message)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.selectedConnection == nil {
                Image(systemName: "point.3.connected.trianglepath.dotted").font(.system(size: 36)).foregroundStyle(.tint)
                Text("Connect to Hermes").font(.title2.bold())
                Text("Add your local or Tailscale gateway to start chatting.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Set Up Connection") { showingConnections = true }.buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(.tint)
                Text("What should we work on?").font(.title2.bold())
                Text("Messages run through your selected Hermes agent and its tools.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 90)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message Hermes", text: $input, axis: .vertical)
                .lineLimit(1...6).textFieldStyle(.plain).padding(.horizontal, 14).padding(.vertical, 11)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            if model.isResponding {
                Button(action: model.stop) { Image(systemName: "stop.fill").frame(width: 36, height: 36) }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
            } else {
                Button {
                    let value = input
                    input = ""
                    model.send(value)
                } label: { Image(systemName: "arrow.up").frame(width: 36, height: 36) }
                .buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                .disabled(model.selectedConnection == nil || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal).padding(.vertical, 10).background(.bar)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 52) }
            Text(message.content.isEmpty ? "Thinking…" : message.content)
                .foregroundStyle(message.content.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(message.role == .user ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 18))
            if message.role == .assistant { Spacer(minLength: 52) }
        }
        .frame(maxWidth: .infinity)
    }
}
