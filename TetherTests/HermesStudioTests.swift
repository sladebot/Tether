import XCTest
import WebKit
import SwiftUI
@testable import Tether

@MainActor
final class HermesStudioTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func connection() -> AgentConnection {
        AgentConnection(name: "Studio", baseURL: "https://studio.example.ts.net", route: .tailscale)
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 8, _ condition: () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out: \(description)")
    }

    func testChatSwitchClearsOldApproval() throws {
        let suite = "review-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let connection = connection()
        let storage = ConnectionStore(defaults: defaults)
        storage.save([connection], selectedID: connection.id)
        let model = AppModel(store: storage)
        model.pendingApproval = RunApproval(runID: "old", command: "old", choices: ["once"])
        model.newConversation()
        XCTAssertNil(model.pendingApproval)
    }

    func testActualMiniAppPreviewLoadsGeneratedDocument() async throws {
        let root = try temporaryRoot()
        let file = root.appending(path: "index.html")
        try MiniAppDocument.prepare("<html><head><title>Counter</title></head><body><button id='increment' onclick='this.textContent=Number(this.textContent)+1'>0</button></body></html>").write(to: file, atomically: true, encoding: .utf8)
        let host = UIHostingController(rootView: VStack(spacing: 0) {
            Text("Preview")
            MiniAppPreview(fileURL: file)
        })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func findWeb(_ view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.lazy.compactMap(findWeb).first
        }
        try await waitUntil("webview mounted") { findWeb(host.view) != nil }
        let web = try XCTUnwrap(findWeb(host.view))
        print("Mounted preview bounds:", web.bounds)
        XCTAssertGreaterThan(web.bounds.height, 100)
        try await waitUntil("actual preview content") {
            let ready = try? await web.evaluateJavaScript("Boolean(document.getElementById('increment'))")
            return ready as? Bool == true
        }
        let value = try await web.evaluateJavaScript("document.getElementById('increment').click(); document.getElementById('increment').textContent")
        XCTAssertEqual(value as? String, "1")
    }

    func testPolicyPrecedesCommentedHeadAndBlocksWebKitSubresources() async throws {
        let escaped = expectation(description: "Network resource must be blocked")
        escaped.isInverted = true
        let loaded = expectation(description: "Document loaded")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let handler = BlockedResourceProbe(escaped)
        configuration.setURLSchemeHandler(handler, forURLScheme: "review")
        let web = WKWebView(frame: .zero, configuration: configuration)
        let delegate = DocumentLoadProbe(loaded)
        web.navigationDelegate = delegate
        let html = try MiniAppDocument.prepare("<!DOCTYPE html><!-- <head> --><html><head></head><body><h1>Usable</h1><script>window.tetherTest=42</script><img src='review://outside/leak'></body></html>")
        XCTAssertLessThan(try XCTUnwrap(html.range(of: "Content-Security-Policy")?.lowerBound), try XCTUnwrap(html.range(of: "<!--")?.lowerBound))
        web.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [loaded], timeout: 15)
        let result = try await web.evaluateJavaScript("window.tetherTest")
        XCTAssertEqual(result as? Int, 42, "Inline mini-app functionality is preserved")
        await fulfillment(of: [escaped], timeout: 0.3)
        withExtendedLifetime(delegate) {}
        withExtendedLifetime(web) {}
    }
}

@MainActor
private final class BlockedResourceProbe: NSObject, WKURLSchemeHandler {
    let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        expectation.fulfill()
        urlSchemeTask.didFailWithError(URLError(.resourceUnavailable))
    }
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

@MainActor
private final class DocumentLoadProbe: NSObject, WKNavigationDelegate {
    let expectation: XCTestExpectation
    init(_ expectation: XCTestExpectation) { self.expectation = expectation }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { expectation.fulfill() }
}
