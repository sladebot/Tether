import SwiftUI

enum Studio {
    static let canvas = gray(light: 0.97, dark: 0)
    static let paper = gray(light: 1, dark: 0.095)
    static let ink = gray(light: 0.055, dark: 0.97)
    static let accent = gray(light: 0, dark: 1)
    static let wash = gray(light: 0.91, dark: 0.15)

    private static func gray(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }
}

enum TetherAppearance: String, CaseIterable {
    case system = "System"
    case white = "White"
    case black = "Black"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .white: .light
        case .black: .dark
        }
    }

    static let preferenceKey = "tether.appearance"
}

/// A woven loop gives the assistant a recognizable silhouette at either size.
struct AgentLoop: View {
    private static let strands: [Path] = (0..<72).map { index in
        let t = Double(index) * .pi / 36
        var strand = Path()
        for step in 0...160 {
            let u = Double(step) * .pi / 80
            let radius = 63 + 13 * cos(3 * u + t) + 11 * sin(2 * u)
            let point = CGPoint(x: radius * cos(u) + 8 * cos(t),
                                y: radius * sin(u) * 0.91 + 13 * sin(t))
            if step == 0 { strand.move(to: point) } else { strand.addLine(to: point) }
        }
        return strand
    }

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 200
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: scale, y: scale)
            for strand in Self.strands {
                context.stroke(strand, with: .linearGradient(Gradient(colors: [
                    Studio.ink, Color(white: 0.53), Studio.ink.opacity(0.65)
                ]), startPoint: CGPoint(x: -70, y: 45), endPoint: CGPoint(x: 65, y: -35)), lineWidth: 1.15)
            }
        }.aspectRatio(1, contentMode: .fit).accessibilityHidden(true)
    }
}

struct TetherPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Studio.paper)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(minHeight: 48)
            .background(Studio.accent, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage(TetherAppearance.preferenceKey) private var appearance = TetherAppearance.system

    @StateObject private var studio = HermesStudioStore()
    @State private var place: TetherTab = .chat

    var body: some View {
        TabView(selection: $place) {
            ChatView(onSpaces: { place = .library })
                .tabItem { Label("Agent", systemImage: "circle.hexagongrid") }.tag(TetherTab.chat)
            TaskHistory(open: { place = .chat })
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }.tag(TetherTab.activity)
            BotsView().tabItem { Label("Bots", systemImage: "person.2") }.tag(TetherTab.bots)
            MiniAppsView()
                .tabItem { Label("Spaces", systemImage: "square.grid.2x2") }.tag(TetherTab.library)
            HomeView(tab: $place).tabItem { Label("Home", systemImage: "house") }.tag(TetherTab.home)
        }
        .environmentObject(studio)
        .task(id: model.selectedConnection) { await studio.configure(model.selectedConnection) }
        .task(id: model.selectedConnectionID) { await model.checkSelectedConnection() }
        .preferredColorScheme(appearance.colorScheme)
        .tint(Studio.accent)
        .alert("Tether", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            model.handleScenePhase(phase)
            if phase == .active { Task { await studio.refresh() } }
        }
    }
}
