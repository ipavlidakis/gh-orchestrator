import AppKit
import GHOrchestratorCore
import SwiftUI
import Vision
import WebKit
import XCTest
@testable import GHOrchestrator

@MainActor
final class PRDiffTests: XCTestCase {
    func testWindowPreloadsFilesWithoutMountingDiffRenderer() async throws {
        let pages = PRDiffPagedFixtureService()
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(pagedDiffs: pages), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close(); Task { await pages.release() } }
        let model = try XCTUnwrap(controller.model.diffs)
        try await wait { model.files.count == 100 && model.patches.count == 100 }
        XCTAssertFalse(controller.model.showsDiffs)
        XCTAssertNil(diffWeb(in: try XCTUnwrap(controller.window?.contentView)), "Preloading must not mount the hidden diff renderer")
        controller.present(url: address.url)
        let requests = await pages.patchPages
        XCTAssertEqual(requests, [1, 2], "Reopening the same window must share its in-flight loads")
        controller.close()
        await pages.release()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.files.count, 100, "Closing the window must cancel pending catalog publication")
        XCTAssertEqual(model.patches.count, 100, "Closing the window must cancel pending patch publication")
        XCTAssertFalse(model.loading)
    }

    func testConversationNavigationWaitsForLaterCatalogAndPatchPages() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let pages = PRDiffPagedFixtureService(linesPerFile: 6000, fileCount: 2100)
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffReviewThreads: true, diffThreadPath: "Sources/File2099.swift", pagedDiffs: pages), openBrowser: { _ in XCTFail("Navigation must stay in the viewer") }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close(); Task { await pages.release() } }
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.center(); window.level = .floating; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { model.files.count == 100 && model.patches.count == 100 && controller.model.threads.count == 3 }
        let conversation = try XCTUnwrap(conversationWeb(in: XCTUnwrap(window.contentView)))
        controller.model.focus(rowID: "reply-3")
        try await wait { (try? await conversation.evaluateJavaScript("!!document.querySelector('[data-row-id=\"reply-3\"] .disclosure-title')")) as? Bool == true }
        try await clickElement("[data-row-id='reply-3'] .disclosure-title", in: conversation)
        try await wait { controller.model.showsDiffs }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(diffWeb(in: try XCTUnwrap(window.contentView)), "Wait for the requested file instead of mounting an unrelated batch")
        XCTAssertEqual(model.selectedPath, "Sources/File2099.swift")
        XCTAssertEqual(model.focusedThreadID, "thread-2")
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try captureNative(window, to: directory.appendingPathComponent("pending-file-navigation.png"))
        await pages.releaseCatalog()
        try await wait { model.files.count == 2100 }
        XCTAssertNil(diffWeb(in: try XCTUnwrap(window.contentView)), "The target's patch has not arrived yet")
        await pages.releasePatches()
        try await wait { !model.loading && self.diffWeb(in: window.contentView!) != nil }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { chrome.reviewThreads["thread-2"] != nil }
        try await Task.sleep(for: .milliseconds(700))
        let card = try XCTUnwrap(chrome.reviewThreads["thread-2"])
        XCTAssertTrue(card.frame.intersects(chrome.bounds), "The delayed target comment must be visible without another click")
        XCTAssertFalse(card.rootView.fileLevel, "Navigate to the requested line after its patch arrives")
        XCTAssertEqual(model.visiblePath, "Sources/File2099.swift")
        XCTAssertTrue(model.errors.isEmpty, "\(model.errors)")
        try captureNative(window, to: directory.appendingPathComponent("late-file-comment-navigation.png"))
    }

    func testFilteringRemovesDirectoriesAndKeepsTreeRowsCompact() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let paths = ["api/neteq/neteq.h", "api/neteq/neteq.cc", "test/fuzzers/neteq_fuzzer.cc"] + (0..<2_100).map { "Sources/Module\($0 / 100)/File\($0).swift" }
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffFileCount: paths.count, diffFilePaths: paths, diffLinesPerFile: 2), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        controller.model.showsDiffs = true
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.level = .floating; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { !model.loading && model.files.count == paths.count }
        func table(in view: NSView) -> NSTableView? {
            if let table = view as? NSTableView { return table }
            return view.subviews.lazy.compactMap { table(in: $0) }.first
        }
        var list = try XCTUnwrap(table(in: XCTUnwrap(window.contentView)))
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertLessThan((0..<list.numberOfRows).map { list.rect(ofRow: $0).height }.max() ?? 0, 48, "Tree folders must not combine multiple files into an oversized row")
        list.scrollRowToVisible(list.numberOfRows / 2)
        try await Task.sleep(for: .milliseconds(200))
        let search = try XCTUnwrap(searchField(in: XCTUnwrap(window.contentView)))
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [NSSize(width: 1180, height: 820), NSSize(width: 860, height: 600)] {
            window.setContentSize(size)
            window.contentView?.layoutSubtreeIfNeeded()
            list.scrollRowToVisible(list.numberOfRows - 1)
            try await Task.sleep(for: .milliseconds(200))
            let viewport = try XCTUnwrap(list.enclosingScrollView).contentView
            let viewportFrame = viewport.convert(viewport.bounds, to: nil)
            let searchFrame = search.convert(search.bounds, to: nil)
            XCTAssertGreaterThanOrEqual(viewportFrame.minY, searchFrame.maxY, "Scrolling file rows must stop above the search footer")
            let lastRowFrame = list.convert(list.rect(ofRow: list.numberOfRows - 1), to: nil)
            XCTAssertGreaterThanOrEqual(lastRowFrame.minY, viewportFrame.minY, "The final file must scroll fully above the footer")
            try captureNative(window, to: directory.appendingPathComponent("sidebar-footer-\(Int(size.width)).png"))
        }
        window.setContentSize(NSSize(width: 1180, height: 820))
        XCTAssertTrue(window.makeFirstResponder(search))
        let editor = try XCTUnwrap(search.currentEditor() as? NSTextView)
        for character in "neteq.h" {
            editor.insertText(String(character), replacementRange: editor.selectedRange())
            try await Task.sleep(for: .milliseconds(100))
        }
        try await wait { model.query == "neteq.h" }
        try await Task.sleep(for: .milliseconds(400))
        window.contentView?.layoutSubtreeIfNeeded()
        list = try XCTUnwrap(table(in: XCTUnwrap(window.contentView)))
        try captureNative(window, to: directory.appendingPathComponent("filtered-tree.png"))
        XCTAssertEqual(model.filteredPaths, ["api/neteq/neteq.h"])
        XCTAssertLessThanOrEqual(list.numberOfRows, 3, "A single match must show only its folder, file and count header")
        for index in 0..<list.numberOfRows {
            XCTAssertLessThan(list.rect(ofRow: index).height, 48, "Filtering must not retain oversized directory rows")
        }
        editor.insertText("", replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try await wait { model.query.isEmpty && model.filteredPaths.count == paths.count }
        XCTAssertTrue(searchField(in: window.contentView!) === search, "Filtering must preserve the focused search control")
        model.query = "no-matching-file"
        try await Task.sleep(for: .milliseconds(200))
        list = try XCTUnwrap(table(in: XCTUnwrap(window.contentView)))
        XCTAssertTrue(model.fileTree.isEmpty)
        XCTAssertLessThanOrEqual(list.numberOfRows, 1, "No matches must remove all directory and file rows")
        model.query = ""; model.extensions = ["kt"]
        try await Task.sleep(for: .milliseconds(200))
        list = try XCTUnwrap(table(in: XCTUnwrap(window.contentView)))
        XCTAssertLessThanOrEqual(list.numberOfRows, 1, "Extension filtering must also remove empty directories")
    }

    func testConversationFilenameOpensInlineReviewThread() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(threadBody: String(repeating: "A longer review comment must wrap within its card while preserving the following code and controls. ", count: 5), diffReviewThreads: true), openBrowser: { _ in XCTFail("Thread navigation must remain in the PR viewer") }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { controller.model.threads.count == 3 && !controller.model.rows.isEmpty }
        let conversation = try XCTUnwrap(conversationWeb(in: XCTUnwrap(window.contentView)))
        controller.model.focus(rowID: "reply-0")
        controller.model.diffs?.query = "README"
        controller.model.diffs?.extensions = ["md"]
        try await wait { (try? await conversation.evaluateJavaScript("!!document.querySelector('[data-row-id=\"reply-0\"] .disclosure-title')")) as? Bool == true }
        try await clickElement("[data-row-id='reply-0'] .disclosure-title", in: conversation)
        try await Task.sleep(for: .milliseconds(200))
        guard controller.model.showsDiffs else { XCTFail("Clicking the thread filename must open Files changed at the comment"); return }
        let model = try XCTUnwrap(controller.model.diffs)
        try await wait { !model.loading && self.diffWeb(in: window.contentView!) != nil }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { chrome.reviewThreads["thread-1"] != nil }
        XCTAssertEqual(model.selectedPath, "Sources/Video.SWIFT")
        XCTAssertEqual(model.focusedThreadID, "thread-1")
        XCTAssertEqual(model.query, ""); XCTAssertTrue(model.extensions.isEmpty)
        XCTAssertFalse(model.collapsed.contains("Sources/Video.SWIFT"))
        let first = try XCTUnwrap(chrome.reviewThreads["thread-1"])
        XCTAssertTrue(first.frame.intersects(chrome.bounds))
        XCTAssertFalse(first.rootView.fileLevel, "A current comment must sit beside its actual diff line")
        XCTAssertEqual(accessibilityButton("Load more replies", in: first)?.accessibilityPerformPress?(), true)
        try await wait { chrome.reviewThreads["thread-1"]?.rootView.thread.comments.nodes.count == 2 }
        XCTAssertEqual(accessibilityButton("Reply…", in: chrome.reviewThreads["thread-1"]!)?.accessibilityPerformPress?(), true)
        try await wait { controller.model.composerPresented && window.attachedSheet != nil }
        XCTAssertEqual(controller.model.composerThreadID, "thread-1")
        controller.model.composerPresented = false
        try await wait { window.attachedSheet == nil }
        XCTAssertEqual(accessibilityButton("Resolve conversation", in: chrome.reviewThreads["thread-1"]!)?.accessibilityPerformPress?(), true)
        try await wait { chrome.reviewThreads["thread-1"]?.rootView.thread.isResolved == true }
        XCTAssertEqual(controller.model.threads.first?.isResolved, true)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(chrome.reviewThreads["thread-1"]).frame.minY, 0, "Loading replies must keep the thread header visible")
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(150))
            try captureNative(window, to: directory.appendingPathComponent("inline-thread-\(name).png"))
        }
        for width in [1180.0, 860.0] {
            window.setContentSize(NSSize(width: width, height: 820))
            try await Task.sleep(for: .milliseconds(250))
            let card = try XCTUnwrap(chrome.reviewThreads["thread-1"])
            XCTAssertLessThanOrEqual(card.frame.width, chrome.bounds.width / 2 + 1, "Inline comments must occupy at most half of the diff pane")
            XCTAssertGreaterThan(card.frame.width, 200, "The compact comment must retain readable width")
            try captureNative(window, to: directory.appendingPathComponent("inline-half-width-\(Int(width)).png"))
        }
        controller.model.openDiffThread("thread-2")
        try await wait { chrome.reviewThreads["thread-2"] != nil }
        XCTAssertEqual(chrome.reviewThreads["thread-2"]?.rootView.thread.diffSide, "LEFT")
        XCTAssertFalse(try XCTUnwrap(chrome.reviewThreads["thread-2"]).rootView.fileLevel)
        XCTAssertNil(accessibilityButton("Actions for comment by morgan", in: chrome.reviewThreads["thread-2"]!, role: nil), "Other users' comments must not expose deletion")
        controller.model.openDiffThread("thread-3")
        try await wait { chrome.reviewThreads["thread-3"] != nil }
        XCTAssertTrue(try XCTUnwrap(chrome.reviewThreads["thread-3"]).rootView.fileLevel, "Outdated locations belong at the file header, never an unrelated current line")
        model.style = "split"; model.wraps = true
        try await wait { (try? await web.evaluateJavaScript("!!document.querySelector('diffs-container')?.shadowRoot?.querySelector('[data-diff-type=split]')")) as? Bool == true }
        XCTAssertTrue(model.errors.isEmpty, "Inline threads must not fail in the renderer: \(model.errors)")
        try await wait { !controller.model.isWriting && !model.loading }
        let threadRevision = controller.model.threadRevision
        let refresh = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "refresh" }?.view)
        try click(NSPoint(x: refresh.bounds.midX, y: refresh.bounds.midY), in: refresh)
        try await wait { controller.model.threadRevision > threadRevision }
        XCTAssertEqual(controller.model.threads.first?.isResolved, false, "Refresh must replace cached thread data with GitHub's latest state")
        controller.model.showsDiffs = false
        try await wait { self.conversationWeb(in: window.contentView!) != nil }
        let restoredConversation = try XCTUnwrap(conversationWeb(in: window.contentView!))
        controller.model.focus(rowID: "reply-0")
        try await wait { (try? await restoredConversation.evaluateJavaScript("!!document.querySelector('[data-row-id=\"reply-0\"] .comment-date')")) as? Bool == true }
        try await clickElement("[data-row-id='reply-0'] .comment-date", in: restoredConversation)
        try await wait { controller.model.showsDiffs && model.focusedThreadID == "thread-1" }
    }

    func testOwnCommentDeletionFromNativeMenusInBothViews() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let recorder = PRViewerDeletionRecorder()
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffReviewThreads: true, deletionRecorder: recorder), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window), model = controller.model
        window.center(); window.level = .floating; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { model.threads.count == 3 }
        model.openDiffThread("thread-1")
        try await wait { self.diffWeb(in: window.contentView!)?.superview is PRDiffChromeView }
        let chrome = try XCTUnwrap(diffWeb(in: window.contentView!)?.superview as? PRDiffChromeView)
        try await wait { chrome.reviewThreads["thread-1"] != nil }
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated {
                guard let menu = notification.object as? NSMenu, let index = menu.items.firstIndex(where: { $0.title == "Delete comment" }) else { return }
                DispatchQueue.main.async { menu.performActionForItem(at: index); menu.cancelTracking() }
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        for confirmation in ["Cancel", "Delete"] {
            let actions = try XCTUnwrap(accessibilityButton("Actions for comment by morgan", in: XCTUnwrap(chrome.reviewThreads["thread-1"]), role: nil))
            try clickAccessibility(actions, in: window)
            try await wait { model.deleteConfirmationPresented && window.attachedSheet != nil }
            let sheet = try XCTUnwrap(window.attachedSheet)
            sheet.makeKeyAndOrderFront(nil)
            if confirmation == "Delete" {
                try captureNative(sheet, to: URL(fileURLWithPath: "/tmp/gho-pr-diff/delete-comment-confirmation.png"))
            }
            try await wait { sheet.isKeyWindow }
            try await Task.sleep(for: .milliseconds(200))
            try clickAccessibility(XCTUnwrap(accessibilityButton(confirmation, in: sheet)), in: sheet)
            try await wait { window.attachedSheet == nil }
            if confirmation == "Cancel" {
                let requests = await recorder.requests
                XCTAssertTrue(requests.isEmpty)
            }
        }
        try await wait { !model.isWriting && !model.rows.contains { $0.id == "reply-0" } }
        try await wait { chrome.reviewThreads["thread-1"]?.rootView.thread.comments.nodes.first?.id == "reply-2" }
        model.showsDiffs = false
        try await wait { self.conversationWeb(in: window.contentView!) != nil }
        let conversation = try XCTUnwrap(conversationWeb(in: window.contentView!))
        model.focus(rowID: "event-0")
        try await wait { (try? await conversation.evaluateJavaScript("!!document.querySelector('[data-row-id=\"event-0\"] .comment-actions')")) as? Bool == true }
        try await clickElement("[data-row-id='event-0'] .comment-actions", in: conversation)
        try await wait { model.deleteConfirmationPresented && window.attachedSheet != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        sheet.makeKeyAndOrderFront(nil)
        try await wait { sheet.isKeyWindow }
        try await Task.sleep(for: .milliseconds(200))
        try clickAccessibility(XCTUnwrap(accessibilityButton("Delete", in: sheet)), in: sheet)
        try await wait { !model.isWriting && !model.rows.contains { $0.id == "event-0" } }
        let requests = await recorder.requests
        XCTAssertEqual(requests, ["reply-0", "event-0"])
    }

    func testEmptyDiffBodiesHaveNativeRowsAndIndependentDisclosure() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffEmptyFiles: true), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        controller.model.showsDiffs = true
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.level = .floating; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { !model.loading && model.patches.count == 4 }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { chrome.headers.count == 4 && chrome.headers.values.allSatisfy { $0.frame.height > 70 } }
        XCTAssertTrue(model.errors.isEmpty)
        let ordered = model.filteredPaths.compactMap { chrome.headers[$0] }
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.frame.minY, pair.0.frame.maxY + 10, "Native message rows must reserve space in the virtualized document")
        }
        XCTAssertNil(accessibilityButton("No text diff", in: window))
        let header = try XCTUnwrap(chrome.headers[".agents/.style.mdformat"])
        try await wait { window.isKeyWindow && NSApp.isActive }
        try click(NSPoint(x: 180, y: header.isFlipped ? 22 : header.bounds.height - 22), in: header)
        try await wait { model.collapsed.contains(".agents/.style.mdformat") }
        try await wait { chrome.headers[".agents/.style.mdformat"]?.frame.height == 44 }
        XCTAssertFalse(model.viewed.contains(".agents/.style.mdformat"))
        try click(NSPoint(x: 180, y: 22), in: XCTUnwrap(chrome.headers[".agents/.style.mdformat"]))
        try await wait { chrome.headers[".agents/.style.mdformat"]?.frame.height == 80 }
        XCTAssertTrue(model.errors.isEmpty, "Empty diff disclosure must not fail in the renderer: \(model.errors)")
        let visibleCodeLines = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('diffs-container')).flatMap(e => Array.from(e.shadowRoot.querySelectorAll('[data-line],[data-column-number]'))).filter(e => e.getBoundingClientRect().height > 0).length")
        XCTAssertEqual(visibleCodeLines as? Int, 0, "Empty diffs must not show a synthetic code line below the native message")
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(200))
            try captureNative(window, to: directory.appendingPathComponent("empty-diffs-\(name).png"))
        }
    }

    func testLargePRScrollTrackingKeepsRendererBounded() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let started = Date()
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffFileCount: 2_100, diffLinesPerFile: 250), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        controller.model.showsDiffs = true
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.level = .floating; window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { !model.loading && model.patches.count == 2_100 }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { (try? await web.evaluateJavaScript("window.__INSTANCE?.items.length")) as? Int == 2_100 && model.visiblePath != nil }
        let loadMilliseconds = Date().timeIntervalSince(started) * 1_000
        XCTAssertTrue(model.errors.isEmpty)
        try await web.evaluateJavaScript("window.configurationCalls = 0; const configure = window.prDiff.configure; window.prDiff.configure = (...args) => { window.configurationCalls++; return configure(...args); }; void 0")
        let selected = model.selectedPath, navigationRevision = model.navigationRevision
        var nativeTimes: [Double] = [], renderTimes: [Double] = [], maxLines = 0, maxHeaders = 0
        for index in stride(from: 0, to: 2_100, by: 53) {
            let path = "Sources/Module\(index / 100)/File\(index).swift"
            let start = Date()
            let sample = try await web.callAsyncJavaScript("""
            const start = performance.now(), view = window.__INSTANCE;
            document.getElementById('diffs').scrollTop = view.getTopForItem(path) + 800;
            view.render(true);
            const renderMS = performance.now() - start;
            await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)));
            return {renderMS, scrollTop:view.getScrollTop(), lines:Array.from(document.querySelectorAll('diffs-container')).reduce((count, item) => count + (item.shadowRoot?.querySelectorAll('[data-line]').length ?? 0), 0)};
            """, arguments: ["path": path], in: nil, contentWorld: .page) as? [String: Any]
            try await wait { model.visiblePath == path }
            window.contentView?.layoutSubtreeIfNeeded()
            nativeTimes.append(Date().timeIntervalSince(start) * 1_000)
            renderTimes.append(try XCTUnwrap(sample?["renderMS"] as? Double))
            XCTAssertGreaterThan(sample?["lines"] as? Int ?? 0, 20, "The stress run must scroll rendered code, not empty placeholders")
            maxLines = max(maxLines, sample?["lines"] as? Int ?? 0); maxHeaders = max(maxHeaders, chrome.headers.count)
            let scrollValue = try await web.evaluateJavaScript("window.__INSTANCE.getScrollTop()")
            let settledScroll = try XCTUnwrap(scrollValue as? Double)
            XCTAssertEqual(settledScroll, try XCTUnwrap(sample?["scrollTop"] as? Double), accuracy: 1, "Tree synchronization must not jump the diff back to its header")
        }
        XCTAssertEqual(model.selectedPath, selected, "Scroll tracking must not become a navigation request")
        XCTAssertEqual(model.navigationRevision, navigationRevision)
        let configurationValue = try await web.evaluateJavaScript("window.configurationCalls")
        let configurationCalls = try XCTUnwrap(configurationValue as? Int)
        XCTAssertEqual(configurationCalls, 0, "Scrolling must not resend/reconfigure the full catalog")
        XCTAssertLessThan(maxLines, 200); XCTAssertLessThan(maxHeaders, 30)
        XCTAssertTrue(model.errors.isEmpty, "Large-PR renderer errors: \(model.errors)")
        let sortedRender = renderTimes.sorted(), sortedNative = nativeTimes.sorted()
        let report: [String: Any] = ["files": 2_100, "changedLines": 525_000, "loadMilliseconds": loadMilliseconds, "jumps": renderTimes.count,
            "renderP95Milliseconds": sortedRender[Int(Double(sortedRender.count - 1) * 0.95)], "nativeP95Milliseconds": sortedNative[Int(Double(sortedNative.count - 1) * 0.95)],
            "maximumMountedLines": maxLines, "maximumNativeHeaders": maxHeaders, "configurationCallsDuringScrolling": configurationCalls]
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("large-pr-performance.json"))
        try captureNative(window, to: directory.appendingPathComponent("large-pr-scroll-sync.png"))
        model.selectFile()
        try await wait {
            let scroll = (try? await web.evaluateJavaScript("window.__INSTANCE.getScrollTop()")) as? Double
            return model.visiblePath == selected && (scroll ?? .infinity) < 20
        }
        let restoredScroll = try await web.evaluateJavaScript("window.__INSTANCE.getScrollTop()")
        XCTAssertLessThan(try XCTUnwrap(restoredScroll as? Double), 20, "Selecting the initial file after scrolling must navigate back to its header")
    }

    func testRecoveredRendererClearsWarningWhileCurrentFailureStaysVisible() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let service = PRDiffPagedFixtureService()
        let model = PRDiffModel(address: address, service: service)
        defer { model.cancel(); Task { await service.release() } }
        model.load()
        try await wait { model.files.count == 100 && model.patches.count == 100 }
        let hosting = NSHostingView(rootView: PRDiffView(model: model, columnVisibility: .constant(.all), openBrowser: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = hosting; window.orderFrontRegardless()
        defer { window.close() }
        try await wait { self.diffWeb(in: hosting) != nil }
        let web = try XCTUnwrap(diffWeb(in: hosting))
        try await wait { (try? await web.evaluateJavaScript("window.__INSTANCE?.items.length")) as? Int == 100 }
        try await web.evaluateJavaScript("window.failedDocument = true; window.dispatchEvent(new ErrorEvent('error', {message:'Script error.'}))")
        try await wait { model.errors["Renderer"] == "Script error." }
        model.rendererFailed("This file could not be rendered.", path: "Sources/File0.swift")
        await service.releaseCatalog(); await service.releasePatches()
        try await wait { !model.loading && model.patches.count == 230 }
        try await wait { (try? await web.evaluateJavaScript("!window.failedDocument && window.__INSTANCE?.items.length === 230")) as? Bool == true }
        XCTAssertNil(model.errors["Renderer"], "A successfully reloaded renderer must clear its previous warning")
        XCTAssertNotNil(model.renderErrors["Sources/File0.swift"], "Recovery must preserve independent file errors")
        try await web.evaluateJavaScript("window.dispatchEvent(new ErrorEvent('error', {message:'Current renderer failure'}))")
        try await wait { model.errors["Renderer"] == "Current renderer failure" }
        model.toggleCollapsed("Sources/File0.swift")
        try await wait { (try? await web.evaluateJavaScript("window.__INSTANCE?.items[0]?.item.collapsed")) as? Bool == true }
        XCTAssertEqual(model.errors["Renderer"], "Current renderer failure", "A configuration callback must not clear a failure in the current document")
    }

    func testLargePRPublishesPagesAndAutomaticallyLoadsRemainingDiffs() async throws {
        let service = PRDiffPagedFixtureService()
        let model = PRDiffModel(address: address, service: service)
        defer { model.cancel(); Task { await service.release() } }
        model.load()
        try await wait { model.files.count == 100 && model.patches.count == 100 }
        XCTAssertTrue(model.loading, "First-page content must remain usable while the rest loads")
        await service.releaseCatalog()
        try await wait { model.files.count == 230 }
        model.selectedPath = "Sources/File229.swift"
        for _ in 0..<3 { model.selectFile() }
        let requestedPages = await service.patchPages
        XCTAssertEqual(requestedPages, [1, 2], "Repeated selections must share the pending request")
        let pendingFile = try XCTUnwrap(model.selectedFile)
        let header = NSHostingView(rootView: PRDiffFileHeader(file: pendingFile, model: model, openBrowser: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = header
        window.orderFrontRegardless()
        defer { window.close() }
        try await wait { self.accessibilityControls(in: header).contains { $0.contains("Loading diff for Sources/File229.swift") } }
        XCTAssertNil(accessibilityButton("Retry loading", in: header), "A pending request must not invite repeated clicks")
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try captureNative(window, to: directory.appendingPathComponent("diff-loading.png"))
        await service.releasePatches()
        try await wait { !model.loading }
        XCTAssertEqual(model.patches.count, 230, "All pages must load without repeated clicks")
        XCTAssertNotNil(model.selectedPatch?.patch)
        let finalPages = await service.patchPages
        XCTAssertEqual(finalPages, [1, 2, 3])
        XCTAssertTrue(model.errors.isEmpty)
    }

    func testFileTreeGroupsPathsWithoutCouplingFolderAndDiffDisclosure() async throws {
        let nodes = PRDiffTreeNode.nodes(paths: ["Sources/Video/v2/Call.swift", "Sources/Video/v2/Audio.swift", "Sources/UI/Button.swift", "README.md", "Makefile"])
        XCTAssertEqual(nodes.map(\.name), ["Sources", "Makefile", "README.md"])
        let children = try XCTUnwrap(nodes.first?.children)
        XCTAssertEqual(children.map(\.name), ["UI", "Video/v2"])
        XCTAssertEqual(children.last?.children?.map(\.id), ["Sources/Video/v2/Audio.swift", "Sources/Video/v2/Call.swift"])
        XCTAssertTrue(children.last?.children?.allSatisfy { $0.children == nil } == true)
        XCTAssertEqual(nodes.flatMap(\.filePaths), ["Sources/UI/Button.swift", "Sources/Video/v2/Audio.swift", "Sources/Video/v2/Call.swift", "Makefile", "README.md"])
        let model = PRDiffModel(address: address, service: PRViewerFixtureService())
        model.load()
        try await wait { !model.loading && model.patches.count == 4 }
        let tree = model.fileTree, viewed = model.viewed, collapsed = model.collapsed, selected = model.selectedPath
        XCTAssertEqual(model.filteredPaths, ["android/Call.kt", "Sources/Audio.swift", "Sources/Video.SWIFT", "README.md"])
        model.collapsedDirectories.insert("Sources")
        XCTAssertEqual(model.fileTree, tree)
        XCTAssertEqual(model.viewed, viewed)
        XCTAssertEqual(model.collapsed, collapsed)
        XCTAssertEqual(model.selectedPath, selected)
        XCTAssertEqual(model.filteredPaths, tree.flatMap(\.filePaths), "Folder disclosure must not hide or reorder main-pane diffs")
        model.query = "VIDEO"; model.filterSelection()
        XCTAssertEqual(model.fileTree.first?.children?.map(\.id), ["Sources/Video.SWIFT"])
        XCTAssertEqual(model.selectedPath, "Sources/Video.SWIFT")
        model.query = ""; model.extensions = ["kt"]; model.filterSelection()
        XCTAssertEqual(model.fileTree.map(\.name), ["android"])
        XCTAssertEqual(model.fileTree.first?.children?.map(\.name), ["Call.kt"])
        XCTAssertTrue(model.collapsedDirectories.contains("Sources"), "Filtering must preserve directory disclosure")
        model.selectedPath = "Sources/Audio.swift"; model.selectFile()
        XCTAssertTrue(model.collapsed.contains("Sources/Audio.swift"), "Selecting a viewed file must preserve its collapsed header")
    }
    func testViewedFiltersFailureRefreshAndCancellation() async throws {
        let recorder = PRDiffFixtureRecorder()
        let model = PRDiffModel(address: address, service: PRViewerFixtureService(diffRecorder: recorder))
        model.load()
        try await wait { !model.loading && model.patches.count == 4 }
        XCTAssertTrue(model.viewed.contains("Sources/Audio.swift"))
        XCTAssertTrue(model.collapsed.contains("Sources/Audio.swift"))
        model.extensions = ["swift"]
        XCTAssertEqual(model.filteredPaths, ["Sources/Audio.swift", "Sources/Video.SWIFT"])
        model.query = "VIDEO"
        XCTAssertEqual(model.filteredPaths, ["Sources/Video.SWIFT"])
        model.extensions = ["kt"]
        XCTAssertTrue(model.filteredPaths.isEmpty)
        model.query = ""; model.extensions = []
        model.setViewed("Sources/Audio.swift", false)
        try await wait { !model.isWriting }
        XCTAssertFalse(model.viewed.contains("Sources/Audio.swift"))
        XCTAssertFalse(model.collapsed.contains("Sources/Audio.swift"))
        model.toggleCollapsed("Sources/Audio.swift")
        XCTAssertFalse(model.viewed.contains("Sources/Audio.swift"), "Manual disclosure does not write viewed state")
        model.setViewed("Sources/Audio.swift", true)
        try await wait { !model.isWriting }
        await recorder.setFailure(true)
        model.setViewed("Sources/Audio.swift", false)
        try await wait { !model.isWriting }
        XCTAssertTrue(model.viewed.contains("Sources/Audio.swift"))
        XCTAssertTrue(model.collapsed.contains("Sources/Audio.swift"))
        XCTAssertNotNil(model.errors["Sources/Audio.swift"])
        await recorder.setFailure(false)
        await recorder.setViewed("Sources/Audio.swift", false)
        model.refresh()
        try await wait { !model.loading && model.patches.count == 4 }
        XCTAssertFalse(model.viewed.contains("Sources/Audio.swift"), "Refresh imports changes made on GitHub")
        await recorder.setDelayed(true)
        model.setViewed("Sources/Audio.swift", true)
        try await wait { await recorder.waiting }
        model.cancel()
        await recorder.complete()
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.viewed.contains("Sources/Audio.swift"), "A late completion cannot update a closed viewer")
    }

    func testCommentDraftSurvivesFailureAndPostsSelectedRange() async throws {
        let recorder = PRDiffFixtureRecorder()
        let model = PRDiffModel(address: address, service: PRViewerFixtureService(diffRecorder: recorder))
        model.load()
        try await wait { !model.loading && model.patches.count == 4 }
        model.selectedPath = "Sources/Video.SWIFT"
        model.selectLines(path: "Sources/Video.SWIFT", start: 2, end: 4, startSide: .right, endSide: .right)
        model.composeComment(); model.commentDraft = "Please rename these."
        await recorder.setFailure(true)
        model.postComment()
        try await wait { !model.postingComment }
        XCTAssertTrue(model.composerPresented)
        XCTAssertEqual(model.commentDraft, "Please rename these.")
        XCTAssertNotNil(model.errors["Comment"])
        await recorder.setFailure(false)
        model.postComment()
        try await wait { !model.postingComment }
        XCTAssertFalse(model.composerPresented)
        XCTAssertEqual(model.postedComment?.body, "Please rename these.")
        let selection = await recorder.commentSelection
        XCTAssertEqual(selection?.start, 2); XCTAssertEqual(selection?.end, 4)
        XCTAssertEqual(selection?.endSide, .right)
        XCTAssertEqual(model.commentDraft, "")
    }

    func testLargeFileCatalogKeepsNativeHeadersBounded() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffFileCount: 3_000), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        controller.model.showsDiffs = true
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        try await wait { !model.loading && model.files.count == 3_000 && window.isKeyWindow && NSApp.isActive }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        try await wait { (try? await web.evaluateJavaScript("window.__INSTANCE?.items.length === 3000")) as? Bool == true }
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { !chrome.headers.isEmpty }
        let initialScroll = try await web.evaluateJavaScript("window.__INSTANCE.getScrollTop()") as? Double
        XCTAssertEqual(try XCTUnwrap(initialScroll), 0, accuracy: 1, "Initial loading must not turn default selection into navigation")
        XCTAssertLessThan(chrome.headers.count, 30, "Only visible file headers may have native hosting views")
        model.selectedPath = "Sources/Module29/File2999.swift"
        try await wait { chrome.headers["Sources/Module29/File2999.swift"] != nil }
        XCTAssertLessThan(chrome.headers.count, 30)
        XCTAssertEqual(model.fileTree.first?.children?.count, 30)
        XCTAssertTrue(chrome.web === web, "File navigation must retain the single code surface")
    }

    func testNavigationToolbarAndDiffChrome() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.level = .floating
        window.orderFrontRegardless()
        try await wait { controller.model.rows.count == 7 }
        let hosting = try XCTUnwrap(window.contentView)
        try await wait { window.toolbar?.items.contains { $0.itemIdentifier.rawValue.contains("section") } == true }
        XCTAssertFalse(window.toolbar?.items.contains { $0 is NSSearchToolbarItem } == true)
        window.contentView?.layoutSubtreeIfNeeded()
        let conversation = try XCTUnwrap(conversationWeb(in: XCTUnwrap(window.contentView)))
        let conversationWidth = conversation.bounds.width
        let conversationLeading = try XCTUnwrap(window.toolbar?.items.first { !$0.isHidden && $0.itemIdentifier != .flexibleSpace }?.view)
            .convert(.zero, to: nil).x
        controller.model.showsDiffs = true
        try await wait { !model.loading && model.patches.count == 4 && self.searchField(in: hosting) != nil }
        model.selectedPath = "Sources/Video.SWIFT"
        try await wait { self.diffWeb(in: hosting) != nil }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        try await wait { (try? await web.evaluateJavaScript("Array.from(document.querySelectorAll('diffs-container')).some(e=>e.shadowRoot?.querySelector('[data-line]'))")) as? Bool == true }
        window.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(web.bounds.width, conversationWidth + 50, "Hiding the conversation inspector must give its space to the diff")
        let search = try XCTUnwrap(searchField(in: hosting))
        search.stringValue = "VIDEO"
        search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
        try await wait { model.filteredPaths == ["Sources/Video.SWIFT"] }
        search.stringValue = ""
        search.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: search))
        try await wait { model.query.isEmpty }
        model.toggleCollapsed("Sources/Video.SWIFT")
        model.toggleCollapsed("android/Call.kt")
        model.selectedPath = "README.md"
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, width, appearance) in [("glass-light", 1180.0, NSAppearance.Name.aqua), ("glass-dark", 1180.0, .darkAqua), ("glass-compact", 860.0, .aqua)] {
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(NSSize(width: width, height: 820))
            window.center()
            window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(400))
            let items = try XCTUnwrap(window.toolbar).items
            let controls = items.filter { !$0.isHidden && $0.itemIdentifier != .flexibleSpace }
            if name == "glass-light" {
                let diffLeading = try XCTUnwrap(controls.first?.view).convert(.zero, to: nil).x
                XCTAssertEqual(diffLeading, conversationLeading, accuracy: 6, "The split-view sidebar must not reserve empty space before leading toolbar controls")
            }
            XCTAssertEqual(controls.first?.label, "Hide Sidebar")
            XCTAssertFalse(items.contains { $0.itemIdentifier.rawValue == "copy" })
            XCTAssertTrue(items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }.allSatisfy(\.isHidden))
            XCTAssertEqual(items.suffix(3).map { $0.itemIdentifier.rawValue }, ["refresh", "browser", "fileSettings"])
            XCTAssertFalse(items.contains { $0.itemIdentifier.rawValue == "fileFilters" })
            XCTAssertFalse(items.contains { $0 is NSSearchToolbarItem }, "File search belongs below the tree")
            let searchFrame = search.convert(search.bounds, to: nil)
            XCTAssertLessThan(searchFrame.maxY, 60, "Search must remain at the bottom of the sidebar")
            XCTAssertLessThan(searchFrame.maxX, web.convert(web.bounds, to: nil).minX, "Search must stay inside the file sidebar")
            let filters = try XCTUnwrap(accessibilityButton("File filters", in: window, role: nil))
            let filterFrame = try XCTUnwrap(filters.accessibilityFrame?())
            let searchScreenFrame = window.convertToScreen(searchFrame)
            XCTAssertLessThanOrEqual(filterFrame.maxX, searchScreenFrame.minX, "Extension filters belong immediately before search")
            XCTAssertEqual(filterFrame.midY, searchScreenFrame.midY, accuracy: 4)
            do { try await wait { window.isKeyWindow && NSApp.isActive } }
            catch {
                try captureNative(window, to: directory.appendingPathComponent("toolbar-order-inactive.png"))
                throw error
            }
            window.contentView?.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(web.bounds.width, 400, "The compact diff must remain usable")
            if name == "glass-light" {
                try XCTUnwrap(splitView(in: XCTUnwrap(window.contentView))).setPosition(220, ofDividerAt: 0)
                window.contentView?.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(100))
                let selectionCapture = directory.appendingPathComponent("file-selection.png")
                try captureNative(window, to: selectionCapture)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.regionOfInterest = CGRect(x: 0, y: 0, width: 240 / window.frame.width, height: 1)
                try VNImageRequestHandler(url: selectionCapture).perform([request])
                let leaf = try XCTUnwrap(request.results?.first { $0.topCandidates(1).first?.string.lowercased().contains("audio.swift") == true })
                let point = NSPoint(x: 240 * leaf.boundingBox.midX, y: window.frame.height * leaf.boundingBox.midY)
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                    NSApp.postEvent(event, atStart: false)
                }
                do { try await wait { model.selectedPath == "Sources/Audio.swift" } }
                catch {
                    XCTFail("File click at \(point); OCR \(leaf.boundingBox); window \(window.frame); selected \(model.selectedPath ?? "nil")")
                    try captureNative(window, to: directory.appendingPathComponent("file-selection-failure.png"))
                    throw error
                }
                XCTAssertTrue(model.collapsed.contains("Sources/Audio.swift"))
                XCTAssertTrue(model.viewed.contains("Sources/Audio.swift"))
                model.selectedPath = "README.md"
                try await Task.sleep(for: .milliseconds(100))
            }
            try captureNative(window, to: directory.appendingPathComponent("diff-\(name).png"))
            if appearance == .darkAqua {
                let header = try XCTUnwrap((web.superview as? PRDiffChromeView)?.headers["README.md"])
                XCTAssertEqual(header.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
                let point = header.convert(NSPoint(x: header.bounds.midX, y: header.bounds.midY), to: nil)
                let bitmap = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: directory.appendingPathComponent("diff-\(name).png"))))
                let x = Int(point.x * CGFloat(bitmap.pixelsWide) / window.frame.width)
                let y = Int((window.frame.height - point.y) * CGFloat(bitmap.pixelsHigh) / window.frame.height)
                let color = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                XCTAssertLessThan(max(color.redComponent, color.greenComponent, color.blueComponent), 0.5, "Native headers must remain dark in the active dark window")
            }
        }
        window.setContentSize(NSSize(width: 1180, height: 820))
        window.contentView?.layoutSubtreeIfNeeded()
        let sidebarVisibleWidth = web.bounds.width
        let hideSidebar = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "diffSidebar" }?.view)
        try click(NSPoint(x: hideSidebar.bounds.midX, y: hideSidebar.bounds.midY), in: hideSidebar)
        try await wait { self.accessibilityButton("Show Sidebar", in: window) != nil && web.bounds.width > sidebarVisibleWidth + 150 }
        let showSidebar = try XCTUnwrap(window.toolbar?.items.first { $0.itemIdentifier.rawValue == "diffSidebar" }?.view)
        try click(NSPoint(x: showSidebar.bounds.midX, y: showSidebar.bounds.midY), in: showSidebar)
        try await wait { self.accessibilityButton("Hide Sidebar", in: window) != nil && abs(web.bounds.width - sidebarVisibleWidth) < 2 }
        controller.model.showsDiffs = false
        try await wait { window.toolbar?.items.contains { $0 is NSSearchToolbarItem } == false && self.conversationWeb(in: hosting) != nil }
        try await Task.sleep(for: .milliseconds(400))
        window.contentView?.layoutSubtreeIfNeeded()
        let restored = try XCTUnwrap(conversationWeb(in: XCTUnwrap(window.contentView)))
        XCTAssertEqual(restored.bounds.width, conversationWidth, accuracy: 2, "Conversation must restore its inspector")
        let conversationItems = try XCTUnwrap(window.toolbar).items
        let refreshIndex = try XCTUnwrap(conversationItems.firstIndex { $0.itemIdentifier.rawValue == "refresh" })
        XCTAssertGreaterThan(refreshIndex, 0)
        XCTAssertEqual(conversationItems[refreshIndex - 1].itemIdentifier, .flexibleSpace, "Conversation actions must be pushed to the trailing edge")
        XCTAssertEqual(conversationItems.suffix(2).map { $0.itemIdentifier.rawValue }, ["refresh", "browser"])
        XCTAssertFalse(conversationItems.contains { $0.itemIdentifier.rawValue == "copy" })
        try captureNative(window, to: directory.appendingPathComponent("conversation-glass-toolbar.png"))
    }

    func testPierreRendersCodeOnlyAndVirtualizesLargeDiff() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(previousPolicy) }
        let recorder = PRDiffFixtureRecorder()
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(diffRecorder: recorder), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window), model = try XCTUnwrap(controller.model.diffs)
        window.level = .floating
        window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
        controller.model.showsDiffs = true
        try await wait { !model.loading && model.patches.count == 4 }
        try await wait { window.isKeyWindow && NSApp.isActive }
        window.contentView?.layoutSubtreeIfNeeded()
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        let containers = "Array.from(document.querySelectorAll('diffs-container'))"
        model.selectedPath = "Sources/Video.SWIFT"
        do {
            try await wait { (try? await web.evaluateJavaScript("\(containers).some(e=>e.shadowRoot?.querySelector('[data-line]'))")) as? Bool == true }
        } catch {
            let document = try? await web.evaluateJavaScript("JSON.stringify({ready:document.readyState,api:!!window.prDiff,height:document.getElementById('diffs')?.clientHeight,pool:window.__INSTANCE?.workerManager?.getStats(),items:window.__INSTANCE?.items.map(i=>({id:i.item.id,height:i.height,collapsed:i.item.collapsed})),html:document.getElementById('diffs')?.innerHTML.slice(0,3000)})")
            XCTFail("Renderer errors: \(model.errors); selected: \(model.selectedPath ?? "nil"), patch: \(model.selectedPatch?.patch?.count ?? -1), frame: \(web.frame); document: \(String(describing: document))")
            throw error
        }
        let nativeControls = try await web.evaluateJavaScript("document.querySelectorAll('input,textarea,button').length + \(containers).reduce((n,e)=>n+(e.shadowRoot?.querySelectorAll('input,textarea,button').length??0),0)")
        XCTAssertEqual(nativeControls as? Int, 0, "The file controls and composer must stay native")
        let backing = try await web.evaluateJavaScript("getComputedStyle(document.querySelector('diffs-container')).backgroundColor")
        XCTAssertEqual(backing as? String, "rgba(0, 0, 0, 0)", "The renderer must not place an opaque surface behind native glass headers")
        let allFiles = try await web.evaluateJavaScript("window.__INSTANCE.items.map(entry => entry.item.id)")
        XCTAssertEqual(allFiles as? [String], model.filteredPaths, "The diff pane must include every filtered file, including collapsed headers")
        XCTAssertEqual(allFiles as? [String], model.fileTree.flatMap(\.filePaths), "Rendered order must exactly match depth-first sidebar order")
        window.contentView?.layoutSubtreeIfNeeded()
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-diff")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try captureNative(window, to: directory.appendingPathComponent("diff-initial.png"))
        do { try await wait { self.accessibilityButton("Viewed Sources/Video.SWIFT", in: window) != nil } }
        catch {
            XCTFail("Native viewed button: key=\(window.isKeyWindow), active=\(NSApp.isActive), controls=\(accessibilityControls(in: window))")
            throw error
        }
        let viewed = try XCTUnwrap(accessibilityButton("Viewed Sources/Video.SWIFT", in: window), "Native controls: \(accessibilityControls(in: window))")
        XCTAssertTrue(viewed.isAccessibilityEnabled?() == true)
        let initialHeader = try XCTUnwrap((web.superview as? PRDiffChromeView)?.headers["Sources/Video.SWIFT"])
        try click(NSPoint(x: initialHeader.bounds.width - 30, y: 22), in: initialHeader)
        try await wait { model.viewed.contains("Sources/Video.SWIFT") && model.collapsed.contains("Sources/Video.SWIFT") }
        try await wait { (try? await web.evaluateJavaScript("\(containers).find(e=>e.querySelector('[data-native-header]')?.dataset.nativeHeader==='Sources/Video.SWIFT')?.shadowRoot?.querySelectorAll('[data-line]').length === 0")) as? Bool == true }
        try await wait { self.accessibilityButton("Viewed Sources/Video.SWIFT", in: window) != nil }
        let unviewed = try XCTUnwrap(accessibilityButton("Viewed Sources/Video.SWIFT", in: window))
        XCTAssertTrue(unviewed.accessibilityPerformPress?() == true)
        try await wait { !model.viewed.contains("Sources/Video.SWIFT") && !model.collapsed.contains("Sources/Video.SWIFT") }
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { chrome.headers["Sources/Video.SWIFT"] != nil }
        let header = try XCTUnwrap(chrome.headers["Sources/Video.SWIFT"])
        try click(NSPoint(x: 150, y: 22), in: header)
        try await wait { model.collapsed.contains("Sources/Video.SWIFT") }
        XCTAssertFalse(model.viewed.contains("Sources/Video.SWIFT"), "Header disclosure must not mark a file as viewed")
        try await wait { chrome.headers["Sources/Video.SWIFT"] != nil }
        let collapsedHeader = try XCTUnwrap(chrome.headers["Sources/Video.SWIFT"])
        try click(NSPoint(x: collapsedHeader.bounds.midX, y: 22), in: collapsedHeader)
        try await wait { !model.collapsed.contains("Sources/Video.SWIFT") }
        try await wait { (try? await web.evaluateJavaScript("\(containers).some(e=>e.shadowRoot?.querySelector('[data-column-number=\"2\"]'))")) as? Bool == true }
        try await web.evaluateJavaScript("""
        const shadow=Array.from(document.querySelectorAll('diffs-container')).map(e=>e.shadowRoot).find(s=>s?.querySelector('[data-column-number="2"]'));
        function clickLine(number,shift=false) {
          const target=shadow.querySelector(`[data-column-number="${number}"]`), rect=target.getBoundingClientRect();
          const options={bubbles:true,composed:true,pointerId:1,pointerType:'mouse',clientX:rect.x+rect.width/2,clientY:rect.y+rect.height/2,shiftKey:shift};
          target.dispatchEvent(new PointerEvent('pointerdown',{...options,buttons:1}));
          target.dispatchEvent(new PointerEvent('pointerup',options));
        }
        clickLine(2);
        """)
        try await wait { model.selection?.start == 2 && model.selection?.end == 2 }
        try await web.evaluateJavaScript("clickLine(4,true)")
        try await wait { model.selection?.start == 2 && model.selection?.end == 4 }
        try await wait { self.accessibilityButton("Comment on selection", in: window) != nil }
        let commentHeader = try XCTUnwrap(chrome.headers["Sources/Video.SWIFT"])
        try click(NSPoint(x: commentHeader.bounds.width - 70, y: 22), in: commentHeader)
        try await wait { window.attachedSheet != nil && model.composerPresented }
        XCTAssertFalse(model.collapsed.contains("Sources/Video.SWIFT"), "Clicking a header action must not toggle disclosure")
        model.composerPresented = false
        try await wait { window.attachedSheet == nil }
        try await web.evaluateJavaScript("""
        const hovered=shadow.querySelector('[data-column-number="4"]'), hoverRect=hovered.getBoundingClientRect();
        hovered.dispatchEvent(new PointerEvent('pointermove',{bubbles:true,composed:true,pointerId:1,pointerType:'mouse',clientX:hoverRect.x+hoverRect.width/2,clientY:hoverRect.y+hoverRect.height/2}));
        """)
        let plusLabel = "Add comment on \(model.selection?.endSide == .left ? "old" : "new") line 4"
        try await wait { self.accessibilityButton(plusLabel, in: window) != nil }
        try captureNative(window, to: directory.appendingPathComponent("diff-line-comment-plus.png"))
        let plus = try XCTUnwrap(accessibilityButton(plusLabel, in: window))
        XCTAssertTrue(plus.accessibilityPerformPress?() == true)
        try await wait { window.attachedSheet != nil && model.composerPresented }
        XCTAssertFalse(model.collapsed.contains("Sources/Video.SWIFT"), "Comment actions must not toggle header disclosure")
        XCTAssertEqual(model.commentSelection?.start, 2)
        XCTAssertEqual(model.commentSelection?.end, 4, "The line plus must preserve the selected range")
        model.commentDraft = "Please rename these."
        let sheet = try XCTUnwrap(window.attachedSheet)
        try await wait { sheet.isKeyWindow && self.accessibilityButton("Post comment", in: sheet)?.isAccessibilityEnabled?() == true }
        try captureNative(sheet, to: directory.appendingPathComponent("diff-comment-sheet.png"))
        let submit = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: sheet.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertTrue(sheet.performKeyEquivalent(with: submit))
        try await wait { model.postedComment != nil && !model.composerPresented }
        model.selectedPath = "README.md"
        try await wait { (try? await web.evaluateJavaScript("\(containers).some(e=>e.shadowRoot?.textContent.includes('window.untrustedRan'))")) as? Bool == true }
        let untrustedRan = try await web.evaluateJavaScript("window.untrustedRan === true")
        XCTAssertEqual(untrustedRan as? Bool, false)
        model.query = "README"; model.extensions = ["swift"]
        XCTAssertTrue(model.filteredPaths.isEmpty)
        try await wait { model.selectedPath == nil }
        XCTAssertTrue(diffWeb(in: try XCTUnwrap(window.contentView)) === web, "An empty filter must preserve the single WebKit renderer")
        model.extensions = []; model.query = "VIDEO"
        XCTAssertEqual(model.filteredPaths, ["Sources/Video.SWIFT"])
        try await wait { model.selectedPath == "Sources/Video.SWIFT" }
        model.style = "split"; model.wraps = true
        try await wait { (try? await web.evaluateJavaScript("!!document.querySelector('diffs-container')?.shadowRoot?.querySelector('[data-diff-type=split]')")) as? Bool == true }
        model.query = ""; model.wraps = false; model.style = "unified"
        for (name, width, appearance) in [("light", 1180.0, NSAppearance.Name.aqua), ("dark", 1180.0, .darkAqua), ("compact", 860.0, .aqua)] {
            window.appearance = NSAppearance(named: appearance); window.setContentSize(NSSize(width: width, height: 820))
            try await Task.sleep(for: .milliseconds(200))
            try captureNative(window, to: directory.appendingPathComponent("diff-\(name).png"))
        }
        XCTAssertNil(model.errors["Renderer"])
        model.query = "Video"
        window.makeKeyAndOrderFront(nil); window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
        XCTAssertTrue(window.isVisible)
        XCTAssertTrue(web.window === window, "The benchmark must use the mounted renderer")
        let script = """
        const root=document.getElementById('diffs'), view=window.__INSTANCE, times=[]; let maxLines=0, maxLineNumber=0;
        // Measure renderer CPU and layout directly: occluded XCTest windows pause animation callbacks.
        for(let i=0;i<30;i++) {
          root.scrollTop=(root.scrollHeight-root.clientHeight)*i/29;
          root.dispatchEvent(new Event('scroll'));
          const start=performance.now(); view.render(true); root.getBoundingClientRect(); times.push(performance.now()-start);
          const shadows=Array.from(document.querySelectorAll('diffs-container')).map(e=>e.shadowRoot).filter(Boolean);
          const lines=shadows.reduce((n,s)=>n+s.querySelectorAll('[data-line]').length,0); maxLines=Math.max(maxLines,lines);
          for(const shadow of shadows) for(const line of shadow.querySelectorAll('[data-column-number]')) maxLineNumber=Math.max(maxLineNumber,Number(line.dataset.columnNumber)||0);
        }
        times.sort((a,b)=>a-b); return JSON.stringify({maxLines,maxLineNumber,p95_render_ms:times[Math.floor(times.length*.95)]??null,renderCount:times.length,scrollHeight:root.scrollHeight,visibility:document.visibilityState,measurement:'renderer CPU and layout; excludes frame delivery and painting'});
        """
        let result: String = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                do { continuation.resume(returning: try XCTUnwrap(try result.get() as? String)) }
                catch { continuation.resume(throwing: error) }
            }
        }
        let data = Data(result.utf8)
        let metrics = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        try data.write(to: directory.appendingPathComponent("performance.json"))
        XCTAssertGreaterThan(try XCTUnwrap(metrics["scrollHeight"] as? Double), 100_000)
        XCTAssertGreaterThan(try XCTUnwrap(metrics["maxLines"] as? Int), 0)
        XCTAssertLessThan(try XCTUnwrap(metrics["maxLines"] as? Int), 500, "A 12,000-line diff must keep its mounted lines bounded")
        XCTAssertGreaterThan(try XCTUnwrap(metrics["maxLineNumber"] as? Int), 5_500, "The benchmark must render the end of the diff")
        XCTAssertGreaterThan(try XCTUnwrap(metrics["renderCount"] as? Int), 20)
        XCTAssertLessThan(try XCTUnwrap(metrics["p95_render_ms"] as? Double), 16.7, "Renderer CPU and layout must fit a 60 Hz frame budget")
        for text in ["First-render", "Updated-render"] {
            _ = try await web.callAsyncJavaScript("""
            window.prDiff.setFiles([{path:'README.md',changeType:'MODIFIED'}], [{filename:'README.md',sha:text,patch:'@@ -1 +1 @@\\n-old\\n+'+text}]);
            window.prDiff.configure(['README.md'], {collapsed:[],selectedPath:'README.md',focus:true}, {style:'unified',wraps:false,dark:false});
            """, arguments: ["text": text], in: nil, contentWorld: .page)
            try await wait { (try? await web.evaluateJavaScript("\(containers).some(e=>e.shadowRoot?.textContent.includes('\(text)'))")) as? Bool == true }
        }
        _ = try await web.callAsyncJavaScript("""
        window.prDiff.setFiles([{path:'Sources/Audio.swift',changeType:'MODIFIED'}], [{filename:'Sources/Audio.swift',sha:'bad-hunk',patch:'@@ -1,1 +1,1 @@\\n!invalid'}], false);
        window.prDiff.configure(['Sources/Audio.swift','README.md'], {collapsed:[],selectedPath:'README.md',focus:true}, {style:'unified',wraps:false,dark:false});
        """, arguments: [:], in: nil, contentWorld: .page)
        try await wait { model.renderErrors["Sources/Audio.swift"] != nil }
        let retained = try await web.evaluateJavaScript("\(containers).some(e=>e.shadowRoot?.textContent.includes('Updated-render'))")
        XCTAssertEqual(retained as? Bool, true, "A failed patch must not remove another file or its previously loaded diff")
        XCTAssertNil(model.errors["Renderer"], "Per-file parsing errors must not become global renderer warnings")
    }

    private var address: PullRequestAddress { PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!)! }
    private func wait(file: StaticString = #filePath, line: UInt = #line, _ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 { if await condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        XCTFail("Diff viewer did not reach the expected state", file: file, line: line); throw CancellationError()
    }
    private func diffWeb(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView, web.accessibilityLabel() == "Pull request file diffs" { return web }
        return view.subviews.lazy.compactMap { self.diffWeb(in: $0) }.first
    }
    private func conversationWeb(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView, web.accessibilityLabel() != "Pull request file diffs" { return web }
        return view.subviews.lazy.compactMap { self.conversationWeb(in: $0) }.first
    }
    private func searchField(in view: NSView) -> NSSearchField? {
        if let search = view as? NSSearchField { return search }
        return view.subviews.lazy.compactMap { self.searchField(in: $0) }.first
    }
    private func clickElement(_ selector: String, in web: WKWebView) async throws {
        let result: Any = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("const node = document.querySelector(selector); node.scrollIntoView({block: 'center'}); await new Promise(requestAnimationFrame); const r = node.getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2];", arguments: ["selector": selector], in: nil, in: .page) { continuation.resume(with: $0) }
        }
        let point = try XCTUnwrap(result as? [Double])
        try click(NSPoint(x: point[0], y: web.isFlipped ? point[1] : web.bounds.height - point[1]), in: web)
    }
    private func clickAccessibility(_ element: AnyObject, in window: NSWindow) throws {
        let rect = try XCTUnwrap(element.accessibilityFrame?())
        XCTAssertGreaterThan(rect.width, 0)
        let view = try XCTUnwrap(window.contentView)
        let point = view.convert(window.convertPoint(fromScreen: NSPoint(x: rect.midX, y: rect.midY)), from: nil)
        try click(point, in: view)
    }
    private func accessibilityButton(_ label: String, in element: Any, role: NSAccessibility.Role? = .button) -> AnyObject? {
        let element = element as AnyObject
        if (role == nil || element.accessibilityRole?() == role) && element.accessibilityLabel?() == label { return element }
        return (element.accessibilityChildren?() ?? []).lazy.compactMap { self.accessibilityButton(label, in: $0, role: role) }.first
    }
    private func splitView(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.isVertical { return split }
        return view.subviews.lazy.compactMap { self.splitView(in: $0) }.first
    }
    private func accessibilityControls(in element: Any) -> [String] {
        let element = element as AnyObject
        let own = ["\(String(describing: element.accessibilityRole?())): \(String(describing: element.accessibilityLabel?()))"]
        return own + (element.accessibilityChildren?() ?? []).flatMap { self.accessibilityControls(in: $0) }
    }
    private func captureNative(_ window: NSWindow, to url: URL) throws {
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try capture.run(); capture.waitUntilExit()
        XCTAssertEqual(capture.terminationStatus, 0)
    }

    private func click(_ point: NSPoint, in view: NSView) throws {
        let window = try XCTUnwrap(view.window)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            NSApp.postEvent(event, atStart: false)
        }
    }
}

extension PRViewerFixtureService: PullRequestDiffLoading {
    func diffSnapshot(_ address: PullRequestAddress, after: String?) async throws -> PRDiffSnapshot {
        if let pagedDiffs { return try await pagedDiffs.diffSnapshot(address, after: after) }
        if diffEmptyFiles {
            let cases = [(".agents/.style.mdformat", "MODIFIED", 0), ("empty.txt", "ADDED", 0), ("renamed.txt", "RENAMED", 0), ("unavailable.swift", "MODIFIED", 5)]
            return try decodeDiffFixture(["id": "PR42", "baseRefOid": "base", "headRefOid": "head", "changedFiles": cases.count,
                "files": ["nodes": cases.map { ["path": $0.0, "changeType": $0.1, "additions": $0.2, "deletions": 0, "viewerViewedState": "UNVIEWED"] }, "pageInfo": ["hasNextPage": false]]])
        }
        let paths = diffFilePaths ?? (diffFileCount == 4 ? ["Sources/Audio.swift", "Sources/Video.SWIFT", "android/Call.kt", "README.md"]
            : (0..<diffFileCount).map { "Sources/Module\($0 / 100)/File\($0).swift" })
        let viewed = await diffRecorder?.viewed ?? ["Sources/Audio.swift"]
        let nodes: [[String: Any]] = paths.map { path in
            ["path": path, "additions": diffLinesPerFile > 0 ? diffLinesPerFile : path.contains("Video") ? 6_000 : 1,
             "deletions": diffLinesPerFile > 0 ? 0 : path.contains("Video") ? 6_000 : 1,
             "changeType": diffLinesPerFile > 0 ? "ADDED" : "MODIFIED", "viewerViewedState": viewed.contains(path) ? "VIEWED" : "UNVIEWED"]
        }
        return try decodeDiffFixture(["id": "PR42", "baseRefOid": "base", "headRefOid": "head", "changedFiles": paths.count, "files": ["nodes": nodes, "pageInfo": ["hasNextPage": false]]])
    }
    func diffPatches(_ address: PullRequestAddress, page: Int) async throws -> [PRDiffPatch] {
        if let pagedDiffs { return try await pagedDiffs.diffPatches(address, page: page) }
        if diffEmptyFiles {
            return try decodeDiffFixture([".agents/.style.mdformat", "empty.txt", "renamed.txt", "unavailable.swift"].map { ["filename": $0, "sha": "empty-\($0)"] })
        }
        if diffLinesPerFile > 0 {
            let start = (page - 1) * PRDiffPatch.pageSize, end = min(start + PRDiffPatch.pageSize, diffFileCount)
            let patch = "@@ -0,0 +1,\(diffLinesPerFile) @@\n" + (0..<diffLinesPerFile).map { "+let value\($0) = \($0)\n" }.joined()
            return try decodeDiffFixture((start..<end).map { ["filename": diffFilePaths?[$0] ?? "Sources/Module\($0 / 100)/File\($0).swift", "sha": "file\($0)", "patch": patch] })
        }
        let large = "@@ -1,6000 +1,6000 @@\n" + (0..<6_000).map { "-let old\($0) = 1\n+let new\($0) = 2\n" }.joined()
        return try decodeDiffFixture([
            ["filename": "Sources/Audio.swift", "sha": "audio", "patch": "@@ -1 +1 @@\n-old\n+new"],
            ["filename": "Sources/Video.SWIFT", "sha": "video", "patch": large],
            ["filename": "android/Call.kt", "sha": "kotlin", "patch": "@@ -1 +1 @@\n-val x = 1\n+val x = 2"],
            ["filename": "README.md", "sha": "readme", "patch": "@@ -1 +1 @@\n-old\n+<script>window.untrustedRan=true</script>"]
        ])
    }
    func setFileViewed(_ address: PullRequestAddress, path: String, viewed: Bool, expected: PRDiffRevision) async throws {
        try await diffRecorder?.record(path, viewed)
    }
    func addLineComment(_ address: PullRequestAddress, selection: PRDiffLineSelection, body: String, expected: PRDiffRevision) async throws -> PRComment {
        try await diffRecorder?.comment(selection, body)
        return try decodeDiffFixture(["id": "new-comment", "body": body, "url": "https://github.com/orbit/nova/pull/42#discussion_r123", "createdAt": "2026-10-10T00:00:00Z"])
    }
}

private func decodeDiffFixture<T: Decodable>(_ value: Any) throws -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
}

actor PRDiffPagedFixtureService: PullRequestDiffLoading {
    let linesPerFile: Int
    let fileCount: Int
    private var catalogReleased = false, patchesReleased = false
    private var catalogGate: CheckedContinuation<Void, Never>?
    private var patchGate: CheckedContinuation<Void, Never>?
    private(set) var patchPages: [Int] = []

    init(linesPerFile: Int = 1, fileCount: Int = 230) { self.linesPerFile = linesPerFile; self.fileCount = fileCount }

    func releaseCatalog() { catalogReleased = true; catalogGate?.resume(); catalogGate = nil }
    func releasePatches() { patchesReleased = true; patchGate?.resume(); patchGate = nil }
    func release() { releaseCatalog(); releasePatches() }

    func diffSnapshot(_ address: PullRequestAddress, after: String?) async throws -> PRDiffSnapshot {
        let start = Int(after ?? "0") ?? 0, end = min(start + 100, fileCount)
        if start == 100, !catalogReleased { await withCheckedContinuation { catalogGate = $0 } }
        try Task.checkCancellation()
        return try decodeDiffFixture(["id": "PR42", "baseRefOid": "base", "headRefOid": "head", "changedFiles": fileCount,
            "files": ["nodes": (start..<end).map { ["path": "Sources/File\($0).swift", "additions": 1, "deletions": 1, "changeType": "MODIFIED", "viewerViewedState": "UNVIEWED"] },
                "pageInfo": ["hasNextPage": end < fileCount, "endCursor": String(end)]]])
    }
    func diffRevision(_ address: PullRequestAddress) async throws -> PRDiffRevision {
        try decodeDiffFixture(["id": "PR42", "baseRefOid": "base", "headRefOid": "head"])
    }
    func diffPatches(_ address: PullRequestAddress, page: Int) async throws -> [PRDiffPatch] {
        patchPages.append(page)
        if page == 2, !patchesReleased { await withCheckedContinuation { patchGate = $0 } }
        try Task.checkCancellation()
        let start = (page - 1) * 100, end = min(start + 100, fileCount)
        let patch = "@@ -1,\(linesPerFile) +1,\(linesPerFile) @@\n" + (0..<linesPerFile).map { "-let old\($0) = 1\n+let new\($0) = 2\n" }.joined()
        let prefixLines = min(linesPerFile, 250)
        let prefixPatch = "@@ -0,0 +1,\(prefixLines) @@\n" + (0..<prefixLines).map { "+let value\($0) = \($0)\n" }.joined()
        return try decodeDiffFixture((start..<end).map { ["filename": "Sources/File\($0).swift", "sha": "blob\($0)", "patch": $0 == fileCount - 1 ? patch : prefixPatch] })
    }
    func setFileViewed(_ address: PullRequestAddress, path: String, viewed: Bool, expected: PRDiffRevision) async throws {}
    func addLineComment(_ address: PullRequestAddress, selection: PRDiffLineSelection, body: String, expected: PRDiffRevision) async throws -> PRComment {
        throw GitHubAPIClientError.invalidResponse(message: "This fixture does not post comments.")
    }
}

actor PRDiffFixtureRecorder {
    private(set) var viewed: Set<String> = ["Sources/Audio.swift"]
    private var fails = false, delayed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var commentSelection: PRDiffLineSelection?
    var waiting: Bool { continuation != nil }
    func setFailure(_ value: Bool) { fails = value }
    func setDelayed(_ value: Bool) { delayed = value }
    func setViewed(_ path: String, _ value: Bool) { if value { viewed.insert(path) } else { viewed.remove(path) } }
    func record(_ path: String, _ value: Bool) async throws {
        if delayed { await withCheckedContinuation { continuation = $0 } }
        if fails { throw GitHubAPIClientError.invalidResponse(message: "GitHub denied the viewed-state update.") }
        setViewed(path, value)
    }
    func complete() { continuation?.resume(); continuation = nil }
    func comment(_ selection: PRDiffLineSelection, _ body: String) throws {
        if fails { throw GitHubAPIClientError.invalidResponse(message: "GitHub denied the line comment.") }
        commentSelection = selection
    }
}
