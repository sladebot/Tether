import SwiftUI

/// Explicit contrast avoids white labels on white system-prominent buttons.
struct TetherPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var studio = HermesStudioStore()
    @State private var tab = TetherTab.home

    var body: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab).tabItem { Label("Home", systemImage: "house") }.tag(TetherTab.home)
            ChatView().tabItem { Label("Chat", systemImage: "bubble.left.and.bubble.right") }.tag(TetherTab.chat)
            BotsView().tabItem { Label("Bots", systemImage: "person.2") }.tag(TetherTab.bots)
            MiniAppsView(embedded: true).tabItem { Label("Library", systemImage: "square.grid.2x2") }.tag(TetherTab.library)
        }
        .environmentObject(studio)
        .tint(TetherTheme.accent)
        .alert("Tether", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .task(id: model.selectedConnectionID) { await studio.configure(model.selectedConnection) }
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
            if phase == .active { Task { await studio.refresh() } }
        }
    }
}
