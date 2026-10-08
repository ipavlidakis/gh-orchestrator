import AppKit
import GHOrchestratorCore
import SwiftUI
import WebKit

struct PRConversationWebView: NSViewRepresentable {
    let model: PRViewerModel
    let revision: Int
    let focusRevision: Int
    let openURL: (URL) -> Void
    let openBrowser: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model, openURL: openURL, openBrowser: openBrowser) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "prViewer")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.navigationDelegate = context.coordinator
        web.setAccessibilityLabel("Pull request summary and activity")
        context.coordinator.web = web
        context.coordinator.loadDocument()
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        context.coordinator.update(dark: colorScheme == .dark, revision: revision, focusRevision: focusRevision)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.cancel()
        web.stopLoading()
        web.navigationDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: "prViewer")
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        private let model: PRViewerModel
        private let openURL: (URL) -> Void
        private let openBrowser: (URL) -> Void
        private var ready = false
        private var failed = false
        private var retried = false
        private var revision = -1
        private var focusRevision = -1
        private var dark = false
        private var appliedDark: Bool?
        private var documentID = UUID()

        init(model: PRViewerModel, openURL: @escaping (URL) -> Void, openBrowser: @escaping (URL) -> Void) {
            self.model = model
            self.openURL = openURL
            self.openBrowser = openBrowser
        }

        func loadDocument() {
            documentID = UUID()
            ready = false
            failed = false
            revision = -1
            focusRevision = -1
            appliedDark = nil
            guard let url = Bundle.main.url(forResource: "PRConversation", withExtension: "html"),
                  let html = try? String(contentsOf: url, encoding: .utf8) else { showFailure(); return }
            web?.loadHTMLString(html.replacingOccurrences(of: "__NONCE__", with: UUID().uuidString), baseURL: model.address.url)
        }

        func update(dark: Bool, revision: Int, focusRevision: Int) {
            self.dark = dark
            if failed, self.revision != revision { loadDocument() }
            guard ready, let web else { return }
            let token = documentID
            if appliedDark != dark {
                appliedDark = dark
                var colors: [String: String] = [:]
                NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                    for (name, color) in ["background": NSColor.windowBackgroundColor, "card": .controlBackgroundColor,
                                          "rail": .labelColor.withAlphaComponent(0.05), "branch": .systemBlue.withAlphaComponent(0.12),
                                          "status-neutral": NSColor(StatusTint.neutral.color), "status-success": NSColor(StatusTint.success.color),
                                          "status-danger": NSColor(StatusTint.danger.color),
                                          "text": .labelColor, "secondary": .secondaryLabelColor, "border": .separatorColor,
                                          "code": .quaternaryLabelColor, "link": .linkColor, "blue": .systemBlue,
                                          "green": .systemGreen, "purple": .systemPurple, "orange": .systemOrange, "red": .systemRed] {
                        if let rgb = color.usingColorSpace(.sRGB) {
                            colors[name] = "rgba(\(rgb.redComponent * 255),\(rgb.greenComponent * 255),\(rgb.blueComponent * 255),\(rgb.alphaComponent))"
                        }
                    }
                }
                web.callAsyncJavaScript("window.prConversation.setTheme(colors, dark)", arguments: ["colors": colors, "dark": dark], in: nil, in: .page) { [weak self] result in self?.check(result, token: token) }
            }
            if self.revision != revision {
                do {
                    let rows = try JSONSerialization.jsonObject(with: JSONEncoder().encode(model.rows))
                    self.revision = revision
                    web.callAsyncJavaScript("window.prConversation.setRows(rows)", arguments: ["rows": rows], in: nil, in: .page) { [weak self] result in self?.check(result, token: token) }
                } catch { showFailure() }
            }
            if self.focusRevision != focusRevision {
                self.focusRevision = focusRevision
                if let id = model.focusedRowID {
                    web.callAsyncJavaScript("window.prConversation.focus(id)", arguments: ["id": id], in: nil, in: .page) { [weak self] result in self?.check(result, token: token) }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.webView === web,
                  let value = message.body as? [String: String] else { return }
            switch value["kind"] {
            case "link", "browser":
                if let raw = value["url"], let url = URL(string: raw), ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                    if value["kind"] == "browser" { openBrowser(url) } else { openURL(url) }
                }
            case "replies":
                if let id = value["id"], model.rows.contains(where: { $0.threadID == id }) { model.loadReplies(id) }
            case "reply":
                if let id = value["id"] { model.compose(threadID: id) }
            case "resolve":
                if let id = value["id"] { model.toggleResolved(id) }
            case "reaction":
                if let id = value["id"], let raw = value["content"], let content = PRReactionContent(rawValue: raw) {
                    model.toggleReaction(subjectID: id, content: content)
                }
            default: break
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !failed else { return }
            ready = true
            update(dark: dark, revision: model.revision, focusRevision: model.focusRevision)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
               ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { openURL(url) }
            decisionHandler(!ready && navigationAction.navigationType == .other ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { showFailure() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { showFailure() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if retried { showFailure() } else { retried = true; loadDocument() }
        }

        func cancel() { ready = false; documentID = UUID() }

        private func check(_ result: Result<Any, any Error>, token: UUID) {
            guard ready, documentID == token else { return }
            if case .failure = result { showFailure() }
        }

        private func showFailure() {
            guard !failed else { return }
            documentID = UUID()
            failed = true
            ready = false
            revision = model.revision
            web?.loadHTMLString("<p style='font:14px -apple-system;padding:24px'>Pull request content could not be displayed. Use Refresh to try again, or Open in Browser.</p>", baseURL: nil)
        }
    }
}
