import SwiftUI
import WebKit

struct MiniAppsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingBuilder = false
    @State private var showingConnections = false

    var body: some View {
        NavigationStack {
            Group {
                if model.miniApps.isEmpty { emptyState }
                else {
                    List {
                        ForEach(model.miniApps) { app in
                            NavigationLink(value: app) {
                                Label {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.title).font(.headline)
                                        Text(app.updatedAt, format: .relative(presentation: .named))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "app.dashed").foregroundStyle(.tint)
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) { model.deleteMiniApp(app) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Mini Apps")
            .navigationDestination(for: MiniApp.self) { app in MiniAppRunnerView(app: app) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Build Mini App", systemImage: "plus") { showingBuilder = true }
                        .disabled(model.selectedConnection == nil)
                }
            }
            .sheet(isPresented: $showingBuilder) { NavigationStack { MiniAppBuilderView() } }
            .sheet(isPresented: $showingConnections) { NavigationStack { ConnectionListView() } }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Mini Apps Yet", systemImage: "square.grid.2x2")
        } description: {
            Text("Describe a small tool and your Hermes agent will build it as an isolated HTML app.")
        } actions: {
            if model.selectedConnection == nil {
                Button("Set Up Hermes") { showingConnections = true }.buttonStyle(.borderedProminent)
            } else {
                Button("Build a Mini App") { showingBuilder = true }.buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct MiniAppBuilderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var request = ""

    var body: some View {
        Form {
            Section("Mini app") {
                TextField("Name", text: $title)
                TextField("Describe what it should do", text: $request, axis: .vertical)
                    .lineLimit(5...12)
            }
            Section {
                Button {
                    Task {
                        if await model.buildMiniApp(title: title, request: request) { dismiss() }
                    }
                } label: {
                    HStack {
                        Label("Build with Hermes", systemImage: "hammer")
                        Spacer()
                        if model.isBuildingMiniApp { ProgressView() }
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          model.isBuildingMiniApp)
            } footer: {
                if model.isBuildingMiniApp {
                    Text("Hermes is generating and validating the HTML… \(model.miniAppBuildCharacterCount) characters received")
                } else {
                    Text("Mini apps can use inline HTML, CSS, and JavaScript. Network access and shared browser storage are blocked by the harness.")
                }
            }
        }
        .navigationTitle("Build Mini App")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }.disabled(model.isBuildingMiniApp)
            }
        }
        .interactiveDismissDisabled(model.isBuildingMiniApp)
    }
}

private struct MiniAppRunnerView: View {
    @EnvironmentObject private var model: AppModel
    let app: MiniApp

    var body: some View {
        IsolatedWebView(fileURL: model.miniAppURL(for: app))
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(app.title)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct IsolatedWebView: UIViewRepresentable {
    let fileURL: URL

    func makeCoordinator() -> Coordinator { Coordinator(allowedFileURL: fileURL) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isInspectable = false
        webView.loadFileURL(fileURL, allowingReadAccessTo: fileURL.deletingLastPathComponent())
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let allowedFileURL: URL

        init(allowedFileURL: URL) { self.allowedFileURL = allowedFileURL.standardizedFileURL }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            let allowed = url.isFileURL && url.standardizedFileURL == allowedFileURL
            return allowed ? .allow : .cancel
        }
    }
}
