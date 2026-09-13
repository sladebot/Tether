import SwiftUI

struct ConnectionListView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editing: AgentConnection?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(model.connections) { connection in
                Button {
                    model.select(connection)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: connection.route.symbol).frame(width: 28).foregroundStyle(.tint)
                        VStack(alignment: .leading) {
                            Text(connection.name).foregroundStyle(.primary)
                            Text(connection.baseURL).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Text(connection.transport.title).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            if let modelName = connection.modelName {
                                Text(modelName).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if connection.id == model.selectedConnectionID {
                            Image(systemName: "checkmark").fontWeight(.semibold)
                        }
                    }
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { model.remove(connection) }
                    Button("Edit") { editing = connection }.tint(.blue)
                }
            }
        }
        .navigationTitle("Connections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { Button("Add", systemImage: "plus") { adding = true } }
            ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $adding) { NavigationStack { ConnectionEditorView() } }
        .sheet(item: $editing) { connection in
            NavigationStack { ConnectionEditorView(connection: connection, apiKey: model.apiKey(for: connection)) }
        }
    }
}
