import XCTest
import WebKit
@testable import Tether

/// Opt-in acceptance against the actual Studio. Never substitutes a network client.
@MainActor
final class LiveStudioTests: XCTestCase {
    func testRealStudioCreatesEditsAndRendersMiniApp() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["TETHER_LIVE_ACCEPTANCE"] == "1",
              let url = environment["TETHER_LIVE_API_URL"],
              let token = environment["TETHER_LIVE_API_TOKEN"], !token.isEmpty else {
            throw XCTSkip("Requires an explicit live Studio acceptance run.")
        }
        let connection = AgentConnection(name: "Live Studio acceptance", baseURL: url, route: .tailscale)
        XCTAssertEqual(connection.normalizedBaseURL?.scheme, "https")
        XCTAssertTrue(connection.normalizedBaseURL?.host?.hasSuffix(".ts.net") == true)
        let suite = "live-studio-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = ConnectionStore(defaults: defaults)
        storage.save([connection], selectedID: connection.id)
        try storage.saveCredential(token, for: connection)
        defer { storage.removeCredentials(for: connection.id) }
        let root = FileManager.default.temporaryDirectory.appending(path: suite)
        let appStore = MiniAppStore(root: root)
        let model = AppModel(store: storage, miniAppStore: appStore)
        guard !model.hasSavedMiniAppBuild else { throw XCTSkip("A saved build must be preserved before live acceptance can run.") }
        let started = await model.buildMiniApp(title: "Studio counter verification", request: "Build a compact counter with a span id=count initially showing 0 and a button id=increment labelled Increment that adds one. Use no tools, access no files, return complete HTML directly.")
        XCTAssertTrue(started)
        try await waitForBuild(model)
        let app = try XCTUnwrap(model.miniApps.first)
        XCTAssertEqual(app.connectionID, connection.id)
        XCTAssertEqual(model.miniApps.count, 1)
        print("Live Studio mini-app artifact:", app.id)
        let original = try String(contentsOf: model.miniAppURL(for: app), encoding: .utf8)
        let preview = MiniAppPreviewController()
        let web = preview.makeWebView(fileURL: model.miniAppURL(for: app))
        web.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        try await waitUntil { !preview.isLoading }
        XCTAssertNil(preview.error)
        let value = try await web.evaluateJavaScript("document.getElementById('increment').click();document.getElementById('count').textContent")
        XCTAssertEqual(value as? String, "1")
        let editing = await model.buildMiniApp(title: app.title, request: "Keep the counter's count and increment element IDs. Change the button label to Add one and add a Reset button id=reset that sets count to 0. Return the complete updated HTML, no tools or files.", updating: app)
        XCTAssertTrue(editing)
        try await waitForBuild(model)
        XCTAssertEqual(model.miniApps.count, 1)
        let updated = try XCTUnwrap(model.miniApps.first)
        XCTAssertEqual(updated.id, app.id)
        preview.load(model.miniAppURL(for: updated))
        try await waitUntil { !preview.isLoading }
        let reset = try await web.evaluateJavaScript("document.getElementById('increment').click();document.getElementById('reset').click();document.getElementById('count').textContent")
        XCTAssertEqual(reset as? String, "0")
        XCTAssertEqual(appStore.chat(for: updated).filter { $0.role == .user }.count, 1)
        model.rollbackMiniApp(updated)
        XCTAssertEqual(try String(contentsOf: model.miniAppURL(for: updated), encoding: .utf8), original)
        print("Live Studio creation, interaction, edit, reset, and rollback passed")
    }
    private func waitForBuild(_ model: AppModel) async throws {
        try await waitUntil(timeout: 180) { !model.isBuildingMiniApp }
        XCTAssertEqual(model.miniAppBuildStatus, "Ready", model.miniAppBuildStatus)
        XCTAssertFalse(model.hasSavedMiniAppBuild, model.miniAppBuildStatus)
    }
    private func waitUntil(timeout: TimeInterval = 30, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(100)) }
        if !condition() { throw NSError(domain: "LiveStudioTests", code: 1, userInfo: [NSLocalizedDescriptionKey:"Timed out waiting for Studio or preview."]) }
    }
}
