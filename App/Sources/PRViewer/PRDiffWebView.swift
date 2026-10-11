import AppKit
import GHOrchestratorCore
import SwiftUI
import WebKit

struct PRDiffWebView: NSViewRepresentable {
    let model: PRDiffModel
    let revision: String
    let openBrowser: (URL) -> Void
    var reviewModel: PRViewerModel? = nil
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(model: model, openBrowser: openBrowser, reviewModel: reviewModel) }
    func makeNSView(context: Context) -> PRDiffChromeView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "prDiff")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        web.underPageBackgroundColor = .clear
        web.setAccessibilityLabel("Pull request file diffs")
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        let container = PRDiffChromeView(web: web)
        context.coordinator.container = container
        let coordinator = context.coordinator
        container.appearanceChanged = { [weak coordinator] in
            guard let coordinator else { return }
            coordinator.update(dark: coordinator.dark)
        }
        context.coordinator.load()
        return container
    }
    func updateNSView(_ container: PRDiffChromeView, context: Context) { context.coordinator.update(dark: colorScheme == .dark) }
    static func dismantleNSView(_ container: PRDiffChromeView, coordinator: Coordinator) {
        let web = container.web
        coordinator.documentID = UUID(); coordinator.ready = false
        web.configuration.userContentController.removeScriptMessageHandler(forName: "prDiff")
        web.navigationDelegate = nil; web.stopLoading()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let model: PRDiffModel
        let openBrowser: (URL) -> Void
        let reviewModel: PRViewerModel?
        weak var web: WKWebView?
        weak var container: PRDiffChromeView?
        var ready = false, dark = false
        private var failed = false
        var documentID = UUID()
        private var dataRevision = -1
        private var loadRevision = -1, sentFiles = 0, sentPatches = 0
        private var configurationKey = ""
        private var threadRevision = -1

        init(model: PRDiffModel, openBrowser: @escaping (URL) -> Void, reviewModel: PRViewerModel?) { self.model = model; self.openBrowser = openBrowser; self.reviewModel = reviewModel }
        func load() {
            container?.resetThreadLayout()
            documentID = UUID(); ready = false; failed = false; dataRevision = -1; loadRevision = -1; sentFiles = 0; sentPatches = 0; configurationKey = ""; threadRevision = -1
            guard let htmlURL = Bundle.main.url(forResource: "PRDiff", withExtension: "html"),
                  let scriptURL = Bundle.main.url(forResource: "PRDiff", withExtension: "js"),
                  let html = try? String(contentsOf: htmlURL, encoding: .utf8),
                  let script = try? String(contentsOf: scriptURL, encoding: .utf8) else { failure("The bundled diff renderer is missing."); return }
            let nonce = UUID().uuidString
            web?.loadHTMLString(html.replacingOccurrences(of: "__NONCE__", with: nonce).replacingOccurrences(of: "__SCRIPT__", with: script.replacingOccurrences(of: "</script", with: "<\\/script", options: .caseInsensitive)), baseURL: nil)
        }
        func update(dark desiredDark: Bool) {
            let dark = container?.window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]).map { $0 == .darkAqua } ?? desiredDark
            let changedAppearance = self.dark != dark
            self.dark = dark
            if failed && model.dataRevision != dataRevision { load() }
            guard ready, let web else { return }
            let token = documentID
            do {
                let nextThreadRevision = reviewModel?.threadRevision ?? 0
                if changedAppearance || dataRevision != model.dataRevision || threadRevision != nextThreadRevision { container?.updateFiles(model: model, openBrowser: openBrowser, reviewModel: reviewModel) }
                let paths = model.filteredPaths
                let key = "\(model.dataRevision):\(model.stateRevision):\(model.selectedPath ?? ""): \(model.query):\(model.extensions.sorted()):\(model.style):\(model.wraps):\(dark):\(nextThreadRevision)"
                if configurationKey != key {
                    configurationKey = key
                    let reset = loadRevision != model.loadRevision || sentFiles > model.files.count || sentPatches > model.patches.count
                    if reset { sentFiles = 0; sentPatches = 0 }
                    let files = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(model.files.dropFirst(sentFiles))))
                    let patches = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(model.patches.dropFirst(sentPatches))))
                    sentFiles = model.files.count; sentPatches = model.patches.count; loadRevision = model.loadRevision; dataRevision = model.dataRevision
                    let state: [String: Any] = ["collapsed": paths.filter { model.collapsed.contains($0) }, "selectedPath": model.selectedPath as Any? ?? NSNull(), "navigationRevision": model.navigationRevision, "threadID": model.focusedThreadID as Any? ?? NSNull(), "focus": model.selectedPath != model.automaticallySelectedPath && model.selection?.path != model.selectedPath]
                    let options: [String: Any] = ["style": model.style, "wraps": model.wraps, "dark": dark]
                    let threads: Any = threadRevision == nextThreadRevision ? NSNull() : (reviewModel?.threads ?? []).map { thread -> [String: Any] in
                        ["id": thread.id, "path": thread.path, "line": thread.isOutdated ? 0 : thread.line ?? 0, "side": thread.diffSide == "LEFT" ? "deletions" : "additions"]
                    }
                    threadRevision = nextThreadRevision
                    web.callAsyncJavaScript("window.prDiff.setFiles(files, patches, reset); if (threads !== null) window.prDiff.setThreads(threads); window.prDiff.configure(paths, state, options)", arguments: ["files": files, "patches": patches, "reset": reset, "paths": paths, "state": state, "options": options, "threads": threads], in: nil, in: .page) { [weak self] result in self?.check(result, token: token) }
                }
            } catch { failure(error.localizedDescription) }
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, ready, let body = message.body as? [String: Any], let kind = body["kind"] as? String else { return }
            if kind == "error" { failure(body["message"] as? String ?? "Diff rendering failed."); return }
            if kind == "chrome" {
                if let data = try? JSONSerialization.data(withJSONObject: body), let chrome = try? JSONDecoder().decode(PRDiffChrome.self, from: data) {
                    container?.update(chrome: chrome, model: model, openBrowser: openBrowser, reviewModel: reviewModel)
                }
                return
            }
            if kind == "clear-selection" { model.clearLineSelection(); return }
            guard let path = body["path"] as? String, model.files.contains(where: { $0.path == path }) else { return }
            switch kind {
            case "file-error": model.rendererFailed(body["message"] as? String ?? "This file could not be rendered. Open it on GitHub.", path: path)
            case "selection":
                guard let start = body["start"] as? Int, let end = body["end"] as? Int else { return }
                let startSide: PRDiffLineSelection.Side = body["side"] as? String == "deletions" ? .left : .right
                let endSide: PRDiffLineSelection.Side = (body["endSide"] as? String).map { $0 == "deletions" ? .left : .right } ?? startSide
                model.selectedPath = path
                model.selectLines(path: path, start: startSide == endSide ? min(start, end) : start, end: startSide == endSide ? max(start, end) : end, startSide: startSide, endSide: endSide)
            default: break
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; update(dark: dark) }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) { decisionHandler(!ready && action.navigationType == .other ? .allow : .cancel) }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failure("The diff renderer stopped. Refresh files to retry.") }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { failure(error.localizedDescription) }
        private func check(_ result: Result<Any, any Error>, token: UUID) {
            guard token == documentID else { return }
            switch result {
            case .failure(let error): failure(error.localizedDescription)
            case .success: if !failed { model.rendererRecovered() }
            }
        }
        private func failure(_ message: String) { failed = true; model.rendererFailed(message) }
    }
}
