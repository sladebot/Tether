import SwiftUI

/// Explicit contrast avoids white labels on white system-prominent buttons.
struct AgentyPrimaryButtonStyle: ButtonStyle {
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

    var body: some View {
        ChatView()
        .tint(.primary)
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
