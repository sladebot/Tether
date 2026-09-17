import SwiftUI
import WebKit

struct MiniAppsView: View {
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
            .navigationTitle("Mini Apps")
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
                                Text("You can leave this screen. Once submitted, Hermes keeps building; Agenty catches up when you return.")
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
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
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
                Text("This removes Agenty’s saved checkpoint only. It does not stop a build that may still be running on Hermes. Starting another build can duplicate work.")
            }
        }
    }

    @ViewBuilder private var recoveryActions: some View {
        Button("Connections") { showingConnections = true }
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
                Button("Set Up Hermes") { showingConnections = true }.buttonStyle(AgentyPrimaryButtonStyle())
            } else {
                Button("Build a Mini App") { showingBuilder = true }.buttonStyle(AgentyPrimaryButtonStyle())
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
                Button {
                    submitting = true
                    inputFocused = false
                    Task {
                        if await model.buildMiniApp(title: title, request: request) { dismiss() }
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
                Text("Your build is saved immediately. Once Hermes accepts it, you can close Agenty and return later for the result. Mini apps run privately with no network access.")
            }
        }
        .navigationTitle("Build Mini App")
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
                IsolatedWebView(fileURL: model.miniAppURL(for: current)).id(current.updatedAt)
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
