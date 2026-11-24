import SwiftUI
import WebKit

struct MiniAppsView: View {
    var embedded = false
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingBuilder = false
    @State private var showingConnections = false
    @State private var confirmingDiscard = false

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
            .navigationTitle(embedded ? "Library" : "Mini Apps")
            .safeAreaInset(edge: .top) {
                if !model.miniAppBuildStatus.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        if model.isBuildingMiniApp { ProgressView().padding(.top, 3) }
                        else { Image(systemName: "info.circle").padding(.top, 3) }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.miniAppBuildStatus).font(.subheadline.weight(.medium))
                            if model.miniAppBuildNeedsAttention {
                                Button("Check saved build") { model.checkSavedMiniAppBuild() }.buttonStyle(.bordered)
                                ViewThatFits(in: .horizontal) {
                                    HStack { recoveryActions }
                                    VStack(alignment: .leading) { recoveryActions }
                                }.font(.caption)
                            }
                            if let approval = model.miniAppApproval {
                                Text(approval.command).font(.caption).textSelection(.enabled)
                                ViewThatFits(in: .horizontal) {
                                    HStack { approvalButtons(approval) }
                                    VStack(alignment: .leading) { approvalButtons(approval) }
                                }
                            }
                            if model.isBuildingMiniApp {
                                Text("You can leave this screen. Once submitted, Hermes keeps building; Tether catches up when you return.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                        .accessibilityElement(children: .contain)
                }
            }
            .task { model.resumeMiniAppBuild() }
            .navigationDestination(for: MiniApp.self) { app in MiniAppRunnerView(app: app) }
            .toolbar {
                if !embedded { ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Build Mini App", systemImage: "plus") { showingBuilder = true }
                        .disabled(model.selectedConnection == nil || model.hasSavedMiniAppBuild)
                }
            }
            .sheet(isPresented: $showingBuilder) { NavigationStack { MiniAppBuilderView() } }
            .sheet(isPresented: $showingConnections) { NavigationStack { ConnectionListView() } }
            .confirmationDialog("Discard saved build?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard saved build", role: .destructive) { model.discardSavedMiniAppBuild() }
                Button("Keep saved build", role: .cancel) {}
            } message: {
                Text("This removes Tether’s saved checkpoint only. It does not stop a build that may still be running on Hermes. Starting another build can duplicate work.")
            }
        }
    }

    @ViewBuilder private var recoveryActions: some View {
        Button("Providers") { showingConnections = true }
        Button("Discard saved build", role: .destructive) { confirmingDiscard = true }
    }

    @ViewBuilder private func approvalButtons(_ approval: RunApproval) -> some View {
        ForEach(approval.choices, id: \.self) { choice in
            Button(choice == "once" ? "Allow once" : choice.capitalized) {
                model.resolveMiniAppApproval(choice)
            }.buttonStyle(.bordered)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Mini Apps Yet", systemImage: "square.grid.2x2")
        } description: {
            Text("Describe a small tool and your Hermes agent will build it as an isolated HTML app.")
        } actions: {
            if model.selectedConnection == nil {
                Button("Add provider") { showingConnections = true }.buttonStyle(TetherPrimaryButtonStyle())
            } else {
                Button("Build a Mini App") { showingBuilder = true }.buttonStyle(TetherPrimaryButtonStyle())
                    .disabled(model.hasSavedMiniAppBuild)
            }
        }
    }
}

private struct MiniAppBuilderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var request = ""
    @State private var submitting = false
    @State private var modelChoice: ModelChoice?
    @FocusState private var inputFocused: Bool

    var body: some View {
        Form {
            Section("Mini app") {
                TextField("Name", text: $title)
                TextField("Describe what it should do", text: $request, axis: .vertical)
                    .lineLimit(5...12)
                    .focused($inputFocused)
            }
            Section {
                NavigationLink {
                    StudioModelPicker(choices: model.modelChoices, selected: modelChoice) { modelChoice = $0 }
                } label: {
                    LabeledContent("Model", value: modelChoice?.model ?? "Hermes default")
                }
            } footer: { Text("Generated through Hermes using a model available on your server.") }
            Section {
                Button {
                    submitting = true
                    inputFocused = false
                    Task {
                        if await model.buildMiniApp(title: title, request: request, modelChoice: modelChoice) { dismiss() }
                        submitting = false
                    }
                } label: {
                    HStack {
                        Label("Start building", systemImage: "hammer")
                        Spacer()
                        if submitting { ProgressView() }
                    }
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          model.hasSavedMiniAppBuild || submitting)
            } footer: {
                Text("Your build is saved immediately. Once Hermes accepts it, you can close Tether and return later for the result. Mini apps run privately with no network access.")
            }
        }
        .navigationTitle("Build Mini App")
        .task { await model.refreshModelChoices() }
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

private struct MiniAppRunnerView: View {
    @EnvironmentObject private var model: AppModel
    let app: MiniApp
    @State private var editing = false
    @State private var request = ""
    @State private var submitting = false
    @State private var history: [ChatMessage] = []
    private var current: MiniApp { model.miniApps.first { $0.id == app.id } ?? app }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $editing) {
                Text("Preview").tag(false)
                Text("Edit chat").tag(true)
            }.pickerStyle(.segmented).padding()
            if editing {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        Text("Ask Hermes to change this app. Your current version stays available until the update is ready.").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(history) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.role == .user ? "You" : "Hermes").font(.caption.bold()).foregroundStyle(.secondary)
                                Text(message.content).textSelection(.enabled)
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }
                HStack(alignment: .bottom) {
                    TextField("Describe a change…", text: $request, axis: .vertical).lineLimit(1...5)
                    Button("Send") {
                        submitting = true
                        Task {
                            if await model.buildMiniApp(title: current.title, request: request, updating: current) { request = "" }
                            history = model.miniAppChat(for: app)
                            submitting = false
                        }
                    }.disabled(submitting || model.hasSavedMiniAppBuild || request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding().background(.bar)
            } else {
                MiniAppPreview(fileURL: model.miniAppURL(for: current)).id(current.updatedAt)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
            .navigationTitle(app.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Restore previous version") { model.rollbackMiniApp(current) }.disabled(model.hasSavedMiniAppBuild)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .task { history = model.miniAppChat(for: app) }
            .onChange(of: model.miniAppBuildStatus) { _, _ in history = model.miniAppChat(for: app) }
    }
}

struct MiniAppPreview: View {
    let fileURL: URL
    @StateObject private var controller = MiniAppPreviewController()

    var body: some View {
        ZStack {
            IsolatedWebView(fileURL: fileURL, controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = controller.error {
                ContentUnavailableView {
                    Label("Preview couldn’t open", systemImage: "exclamationmark.triangle")
                } description: { Text(error) }
                actions: { Button("Reload preview") { controller.load(fileURL) } }
                .background(Color(.systemBackground))
            } else if controller.isLoading {
                ProgressView("Opening app…").padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

@MainActor
final class MiniAppPreviewController: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var error: String?
    @Published var isLoading = false
    private(set) var webView: WKWebView?

    func makeWebView(fileURL: URL) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = self
        web.isInspectable = false
        web.allowsLinkPreview = false
        webView = web
        load(fileURL)
        return web
    }

    func load(_ fileURL: URL) {
        error = nil
        isLoading = true
        do {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let document = try MiniAppDocument.prepare(source)
            webView?.loadHTMLString(document, baseURL: nil)
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Only the harness's string document may navigate this renderer.
        action.request.url?.absoluteString == "about:blank" ? .allow : .cancel
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { isLoading = false }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { fail(error) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        error = "The preview process stopped. Reload to open your app again."
        isLoading = false
    }
    private func fail(_ error: Error) { self.error = error.localizedDescription; isLoading = false }
}

struct IsolatedWebView: UIViewRepresentable {
    let fileURL: URL
    @ObservedObject var controller: MiniAppPreviewController

    init(fileURL: URL, controller: MiniAppPreviewController) {
        self.fileURL = fileURL
        self.controller = controller
    }
    func makeUIView(context: Context) -> WKWebView { controller.makeWebView(fileURL: fileURL) }
    func updateUIView(_ webView: WKWebView, context: Context) {}
}
