import SwiftUI

struct ConnectionListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: AgentConnection?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(model.connections) { connection in
                    VStack(alignment: .leading, spacing: 12) {
                        Button {
                            model.select(connection)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: connection.providerKind.symbol)
                                    .font(.title3).foregroundStyle(TetherTheme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(TetherTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(connection.providerKind.title).font(.headline).foregroundStyle(.primary)
                                    Text(connection.name == connection.providerKind.title ? (connection.normalizedBaseURL?.host ?? connection.baseURL) : connection.name)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if connection.id == model.selectedConnectionID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(TetherTheme.accent)
                                        .accessibilityLabel("Selected provider")
                                }
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button("Provider settings", systemImage: "slider.horizontal.3") { editing = connection }
                            .font(.subheadline).buttonStyle(.borderless).frame(minHeight: 32)
                    }.padding(.vertical, 8)
                    .swipeActions {
                        Button("Remove", role: .destructive) { model.remove(connection) }
                        Button("Edit") { editing = connection }.tint(TetherTheme.accent)
                    }
                }
            } footer: {
                if !model.connections.isEmpty { Text("Select the provider for your chats and mini apps. Each provider keeps its own conversations.") }
            }
        }
        .overlay {
            if model.connections.isEmpty {
                ContentUnavailableView {
                    Label("Add a provider", systemImage: "point.3.connected.trianglepath.dotted")
                } description: {
                    Text("Connect Hermes with your Tailscale URL and API token.")
                } actions: {
                    Button("Add provider") { adding = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Providers")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add provider", systemImage: "plus") { adding = true } }
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $adding) {
            NavigationStack { AddProviderView { adding = false } }
        }
        .sheet(item: $editing) { connection in
            NavigationStack { ConnectionEditorView(connection: connection, apiKey: model.apiKey(for: connection)) }
        }
    }
}

private struct AddProviderView: View {
    @Environment(\.dismiss) private var dismiss
    let onAdded: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(AgentConnection.ProviderKind.allCases) { kind in
                    NavigationLink {
                        switch kind {
                        case .hermes: ConnectionEditorView(onSaved: onAdded)
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: kind.symbol).font(.title2).foregroundStyle(TetherTheme.accent)
                                .frame(width: 46, height: 46)
                                .background(TetherTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(kind.title).font(.headline)
                                Text("Your agent, connected over Tailscale").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 8)
                    }
                }
            } header: { Text("Choose a provider") }
            footer: { Text("Hermes gives you access to the models and tools configured on your server.") }
        }
        .navigationTitle("Add provider").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}
