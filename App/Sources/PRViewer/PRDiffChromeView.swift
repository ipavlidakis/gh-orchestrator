import AppKit
import GHOrchestratorCore
import SwiftUI
import WebKit

struct PRDiffChrome: Decodable {
    let headers: [PRDiffChromeFrame]
    let comment: PRDiffChromeFrame?
    let visiblePath: String?
    let threads: [PRDiffThreadFrame]?
}

struct PRDiffThreadFrame: Decodable {
    let id, path: String
    let fileLevel: Bool
    let x, y, width, height: CGFloat
    var rect: NSRect? {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, width < 20_000, height > 0, height <= 100_000 else { return nil }
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

struct PRDiffChromeFrame: Decodable {
    let path: String
    let x, y, width, height: CGFloat
    let line: Int?
    let side: String?

    var rect: NSRect? {
        guard [x, y, width, height].allSatisfy(\.isFinite), width > 0, width < 20_000, height > 0, height <= 100 else { return nil }
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class PRDiffChromeView: NSView {
    let web: WKWebView
    private var files: [String: PRDiffFile] = [:]
    var appearanceChanged: (() -> Void)?
    private(set) var headers: [String: NSHostingView<PRDiffFileHeader>] = [:]
    private var commentButton: NSHostingView<PRDiffLineCommentButton>?
    private(set) var reviewThreads: [String: NSHostingView<PRDiffThreadView>] = [:]
    private var threadsByID: [String: PRThread] = [:]
    private var threadHeights: [String: CGFloat] = [:]
    override var isFlipped: Bool { true }

    init(web: WKWebView) {
        self.web = web
        super.init(frame: .zero)
        wantsLayer = true; layer?.masksToBounds = true
        web.autoresizingMask = [.width, .height]
        addSubview(web)
    }
    required init?(coder: NSCoder) { nil }

    override func layout() { super.layout(); web.frame = bounds }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); appearanceChanged?() }
    override func scrollWheel(with event: NSEvent) { web.scrollWheel(with: event) }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }
    override func mouseExited(with event: NSEvent) {
        commentButton?.isHidden = true
        web.evaluateJavaScript("window.prDiff?.clearHover()")
    }

    func resetThreadLayout() {
        reviewThreads.values.forEach { $0.removeFromSuperview() }
        reviewThreads = [:]; threadHeights = [:]
    }

    func updateFiles(model: PRDiffModel, openBrowser: @escaping (URL) -> Void, reviewModel: PRViewerModel? = nil) {
        files = Dictionary(uniqueKeysWithValues: model.files.map { ($0.path, $0) })
        for (path, header) in headers {
            if let file = files[path] { header.rootView = PRDiffFileHeader(file: file, model: model, openBrowser: openBrowser) }
        }
        threadsByID = Dictionary(uniqueKeysWithValues: (reviewModel?.threads ?? []).map { ($0.id, $0) })
        if let reviewModel {
            for (id, host) in reviewThreads {
                if let thread = threadsByID[id] { host.rootView = threadView(thread, fileLevel: host.rootView.fileLevel, model: reviewModel, openBrowser: openBrowser) }
            }
        }
    }

    func update(chrome: PRDiffChrome, model: PRDiffModel, openBrowser: @escaping (URL) -> Void, reviewModel: PRViewerModel? = nil) {
        if let path = chrome.visiblePath { model.syncVisibleFile(path) }
        var visible: Set<String> = []
        for entry in chrome.headers.prefix(128) {
            guard let file = files[entry.path], let rect = entry.rect, rect.intersects(bounds) else { continue }
            visible.insert(entry.path)
            let header = headers[entry.path] ?? NSHostingView(rootView: PRDiffFileHeader(file: file, model: model, openBrowser: openBrowser))
            if headers[entry.path] == nil {
                header.sizingOptions = []; headers[entry.path] = header; addSubview(header)
            }
            header.frame = rect
        }
        for path in Set(headers.keys).subtracting(visible) { headers.removeValue(forKey: path)?.removeFromSuperview() }
        var visibleThreads: Set<String> = []
        if let reviewModel {
            for entry in (chrome.threads ?? []).prefix(128) {
                guard let thread = threadsByID[entry.id], thread.path == entry.path, let rect = entry.rect, rect.intersects(bounds) else { continue }
                visibleThreads.insert(entry.id)
                let host = reviewThreads[entry.id] ?? NSHostingView(rootView: threadView(thread, fileLevel: entry.fileLevel, model: reviewModel, openBrowser: openBrowser))
                if reviewThreads[entry.id] == nil { host.sizingOptions = []; reviewThreads[entry.id] = host; addSubview(host) }
                host.frame = NSRect(x: rect.minX, y: rect.minY, width: min(rect.width, bounds.width / 2), height: rect.height)
            }
        }
        for id in Set(reviewThreads.keys).subtracting(visibleThreads) { reviewThreads.removeValue(forKey: id)?.removeFromSuperview() }
        guard let target = chrome.comment, files[target.path] != nil, let line = target.line,
              let side = target.side.flatMap(PRDiffLineSelection.Side.init(rawValue:)),
              let selection = PRDiffLineSelection(path: target.path, start: line, end: line, startSide: side, endSide: side),
              let rect = target.rect, rect.intersects(bounds), !model.collapsed.contains(target.path) else {
            commentButton?.isHidden = true; return
        }
        let view = PRDiffLineCommentButton(selection: selection, model: model)
        if let commentButton { commentButton.rootView = view }
        else {
            let button = NSHostingView(rootView: view)
            button.sizingOptions = []; commentButton = button; addSubview(button)
        }
        commentButton?.frame = rect; commentButton?.isHidden = false
    }

    private func threadView(_ thread: PRThread, fileLevel: Bool, model: PRViewerModel, openBrowser: @escaping (URL) -> Void) -> PRDiffThreadView {
        PRDiffThreadView(thread: thread, fileLevel: fileLevel, model: model, openBrowser: openBrowser) { [weak self] height in
            guard let self, height.isFinite, height > 0 else { return }
            let height = ceil(height)
            guard threadHeights[thread.id] != height else { return }
            threadHeights[thread.id] = height
            web.callAsyncJavaScript("window.prDiff.setThreadHeight(id, height)", arguments: ["id": thread.id, "height": height], in: nil, in: .page) { [weak self] result in
                if case .failure(let error) = result, self?.window != nil { model.diffs?.rendererFailed(error.localizedDescription) }
            }
        }
    }
}
