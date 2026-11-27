import SwiftUI
import WebKit

struct MiniAppsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingBuilder = false
    @State private var showingConnections = false
    @State private var deleting: MiniApp?
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "square.on.square.dashed").font(.largeTitle)
                        Text("Make a space").font(.system(.title, design: .rounded, weight: .bold))
                        Text("Describe a tool for your routine. Hermes builds it, and you can keep shaping it here.")
                        Button(model.selectedConnection == nil ? "Connect to Hermes" : "Create a space") {
                            if model.selectedConnection == nil { showingConnections = true }
                            else { showingBuilder = true }
                        }.buttonStyle(TetherPrimaryButtonStyle()).disabled(model.hasSavedMiniAppBuild)
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Studio.wash, in: RoundedRectangle(cornerRadius: 26))
                    if !model.miniApps.isEmpty {
                        Text("Your spaces").font(.title2.bold())
                        ForEach(model.miniApps) { app in
                            HStack {
                                NavigationLink(value: app) {
                                    HStack(spacing: 14) {
                                        Image(systemName: "square.grid.2x2.fill").foregroundStyle(Studio.accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(app.title).font(.headline)
                                            Text(app.updatedAt, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }
                                Menu {
                                    Button("Delete space", role: .destructive) { deleting = app }
                                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                                .accessibilityLabel("Options for " + app.title)
                            }.padding(14).background(Studio.paper, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }.foregroundStyle(Studio.ink).padding(20).frame(maxWidth: 640)
            }.frame(maxWidth: .infinity).background(Studio.canvas)
            .navigationTitle("Spaces")
            .alert("Delete this space?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { app in
                Button("Delete", role: .destructive) { model.deleteMiniApp(app) }
                Button("Cancel", role: .cancel) {}
            } message: { Text($0.title) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("What would you like to make?").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Start with an idea").font(.headline)
                ScrollView(.horizontal) {
                    HStack {
                        starter("Reading list", prompt: "Track books I want to read, with notes and a finished shelf.")
                        starter("Day planner", prompt: "Organize my day into time blocks with a checklist for each block.")
                        starter("Meal planner", prompt: "Plan meals for the week and collect ingredients in a grocery list.")
                    }
                }.scrollIndicators(.hidden)
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Space name", text: $title).font(.headline)
                    Divider()
                    TextField("Describe how it should work", text: $request, axis: .vertical)
                        .lineLimit(5...12).focused($inputFocused)
                }.padding(18).background(Studio.paper, in: RoundedRectangle(cornerRadius: 20))
                NavigationLink {
                    StudioModelPicker(choices: model.modelChoices, selected: modelChoice) { modelChoice = $0 }
                } label: {
                    LabeledContent("Model", value: modelChoice?.model ?? model.defaultModelName ?? "Hermes default")
                }
                Text("Once Hermes accepts the build, you can leave and return to Spaces to see the result.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button {
                    submitting = true
                    inputFocused = false
                    Task {
                        if await model.buildMiniApp(title: title, request: request, modelChoice: modelChoice) { dismiss() }
                        submitting = false
                    }
                } label: {
                    HStack {
                        if submitting { ProgressView() }
                        Text(submitting ? "Building…" : "Build space")
                    }
                }.buttonStyle(TetherPrimaryButtonStyle())
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              model.hasSavedMiniAppBuild || submitting)
            }.padding(22).frame(maxWidth: 600)
        }.frame(maxWidth: .infinity).background(Studio.canvas)
        .navigationTitle("New space")
        .task { await model.refreshModelChoices() }
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
    private func starter(_ name: String, prompt: String) -> some View {
        Button(name) { title = name; request = prompt }
            .buttonStyle(.bordered).buttonBorderShape(.capsule)
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
                Text("Refine").tag(true)
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
            .background(Studio.canvas)
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
