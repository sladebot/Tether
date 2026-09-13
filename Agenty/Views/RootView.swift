import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MainTabView()
        .alert("Agenty", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in model.handleScenePhase(phase) }
    }
}

private struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Chat", systemImage: "bubble.left.and.bubble.right") { ChatView() }
            Tab("Mini Apps", systemImage: "square.grid.2x2") { MiniAppsView() }
        }
    }
}
