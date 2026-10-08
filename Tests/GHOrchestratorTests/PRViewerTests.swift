import AppKit
import GHOrchestratorCore
import SwiftUI
import Vision
import WebKit
import XCTest
@testable import GHOrchestrator

@MainActor
final class PRViewerTests: XCTestCase {
    func testConflictSidebarHandlesStatesAndOpensGitHubResolution() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gho-merge-conflicts-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        print("Merge conflict visual evidence: \(directory.path)")
        for (state, mergeable, expected) in [
            ("OPEN", "CONFLICTING", "This branch has conflicts that must be resolved"),
            ("OPEN", "UNKNOWN", "GitHub is calculating merge status"),
            ("OPEN", "MERGEABLE", "Can merge without conflicts"),
            ("CLOSED", "CONFLICTING", "Pull request closed"),
            ("MERGED", "CONFLICTING", "Pull request merged")
        ] {
            let service = PRViewerFixtureService(eventCount: 0, threadCount: 0, mergeable: mergeable, state: state)
            var browserURLs: [URL] = []
            let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!))
            let controller = PRViewerWindowController(address: address, service: service, openBrowser: { browserURLs.append($0) }, onClose: {})
            controller.present(url: address.url)
            let window = try XCTUnwrap(controller.window)
            window.level = .floating
            window.setContentSize(NSSize(width: 1180, height: 820))
            defer { controller.close() }
            try await wait { controller.model.summary != nil && controller.model.rows.count == 2 }
            window.contentView?.layoutSubtreeIfNeeded()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(200))
            func captureSidebar(_ name: String) throws -> [VNRecognizedTextObservation] {
                let url = directory.appendingPathComponent("merge-sidebar-\(name).png")
                let screenshot = Process()
                screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                screenshot.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
                try screenshot.run(); screenshot.waitUntilExit()
                XCTAssertEqual(screenshot.terminationStatus, 0)
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                let sidebarStart = (window.frame.width - 280) / window.frame.width
                request.regionOfInterest = CGRect(x: sidebarStart, y: 0, width: 1 - sidebarStart, height: 1)
                try VNImageRequestHandler(url: url).perform([request])
                return request.results ?? []
            }
            var observations = try captureSidebar("\(state)-\(mergeable)")
            var text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            for _ in 0..<10 where state == "OPEN" && mergeable == "CONFLICTING" && !text.contains("develop") {
                try await Task.sleep(for: .milliseconds(100))
                observations = try captureSidebar("\(state)-\(mergeable)")
                text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            }
            XCTAssertTrue(text.contains(expected), "Merge status must be visible in the sidebar: \(text)")
            let resolve = observations.first { $0.topCandidates(1).first?.string == "Resolve conflicts" }
            if state != "OPEN" || mergeable != "CONFLICTING" {
                XCTAssertNil(resolve, "Only open conflicting PRs need conflict resolution")
                continue
            }
            XCTAssertTrue(text.contains("develop"), "Guidance must identify the target branch: \(text)")
            let action = try XCTUnwrap(resolve)
            let point = NSPoint(x: window.frame.width - 280 + 280 * action.boundingBox.midX, y: window.frame.height * action.boundingBox.midY)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                NSApp.postEvent(event, atStart: false)
            }
            try await wait { !browserURLs.isEmpty }
            XCTAssertEqual(browserURLs.first?.absoluteString, "https://github.com/orbit/nova/pull/42/conflicts")
            for (name, width, appearance) in [("light", 1180.0, NSAppearance.Name.aqua), ("dark", 1180.0, .darkAqua), ("compact", 860.0, .aqua)] {
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(NSSize(width: width, height: 820))
                window.contentView?.layoutSubtreeIfNeeded()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                try await Task.sleep(for: .milliseconds(200))
                let captured = try captureSidebar(name).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                XCTAssertTrue(captured.contains(expected))
                XCTAssertTrue(captured.contains("Resolve conflicts"))
            }
        }
    }

    func testFileConversationAlignsRepliesAndPlacesActionsAfterLastComment() async throws {
        let model = makeModel(service: PRViewerFixtureService())
        model.refresh()
        try await wait { model.rows.count == 7 }
        let hosting = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); model.cancel() }
        hosting.layoutSubtreeIfNeeded()
        try await wait { self.descendant(WKWebView.self, in: hosting) != nil }
        let web = try XCTUnwrap(descendant(WKWebView.self, in: hosting))
        model.focus(rowID: "reply-0")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"reply-1\"]') !== null")) as? Bool == true }
        let conversation = try await web.evaluateJavaScript("""
        (() => {const root=document.querySelector('article[data-row-id="reply-0"]'), reply=document.querySelector('article[data-row-id="reply-1"]');return {
          aligned:root.style.left===reply.style.left,
          replyVisible:!reply.querySelector('.markdown-body').hidden,
          rootActions:root.querySelectorAll('button.reply,button.resolve').length,
          finalActions:reply.querySelectorAll('button.reply,button.resolve').length
        }})()
        """) as? [String: Any]
        XCTAssertEqual(conversation?["aligned"] as? Bool, true, "Starter and replies belong to one aligned file conversation")
        XCTAssertEqual(conversation?["replyVisible"] as? Bool, true)
        XCTAssertEqual(conversation?["rootActions"] as? Int, 0)
        XCTAssertEqual(conversation?["finalActions"] as? Int, 2)
    }

    func testReviewOwnsItsConversationsRatherThanInterleavingCommentDates() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let activity = try decoder.decode([PRActivity].self, from: Data("""
        [{"__typename":"PullRequestReview","id":"review-a","body":"","state":"COMMENTED","createdAt":"2026-10-08T01:00:00Z","author":{"login":"morgan"},"comments":{"totalCount":1}},
         {"__typename":"IssueComment","id":"issue","body":"Separate discussion","createdAt":"2026-10-08T01:30:00Z","author":{"login":"morgan"}},
         {"__typename":"PullRequestReview","id":"review-b","body":"Another review","state":"COMMENTED","createdAt":"2026-10-08T03:00:00Z","author":{"login":"morgan"},"comments":{"totalCount":0}}]
        """.utf8))
        let threadJSON = """
        [{"id":"thread","path":"Audio.swift","isResolved":true,"isOutdated":false,"viewerCanReply":true,"viewerCanUnresolve":true,
          "comments":{"nodes":[
            {"id":"root","body":"Why?","url":"https://github.com/orbit/nova/pull/42#discussion_r1","createdAt":"2026-10-08T00:30:00Z","author":{"login":"morgan"},"pullRequestReview":{"id":"review-a"}},
            {"id":"reply","body":"Because","url":"https://github.com/orbit/nova/pull/42#discussion_r2","createdAt":"2026-10-08T02:00:00Z","author":{"login":"alex"},"pullRequestReview":{"id":"other-review"}}],"pageInfo":{"hasNextPage":false}}}]
        """
        let threads = try decoder.decode([PRThread].self, from: Data(threadJSON.utf8))
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!))
        let rows = PRViewerRow.prepare(address: address, summary: nil, activity: activity, threads: threads)
        XCTAssertEqual(rows.map(\.id), ["activity-heading", "review-a", "root", "reply", "issue", "review-b"])
        XCTAssertEqual(rows.first { $0.id == "review-a" }?.kind, "review", "Empty review bodies need a review header, not an empty comment card")
        XCTAssertEqual(rows.first { $0.id == "root" }?.parentID, "review-a")
        XCTAssertEqual(rows.first { $0.id == "reply" }?.parentID, "root", "A reply remains in the starter's conversation even when posted under another review")
        XCTAssertTrue(rows.first { $0.id == "review-a" }?.badgeResolved == true)
        XCTAssertTrue(rows.first { $0.id == "root" }?.badgeResolved == true)
        XCTAssertFalse(rows.first { $0.id == "root" }?.defaultExpanded ?? true)
        XCTAssertFalse(rows.first { $0.id == "review-a" }?.defaultExpanded ?? true)
        XCTAssertTrue(rows.first { $0.id == "issue" }?.defaultExpanded == true)
        XCTAssertFalse(rows.first { $0.id == "review-b" }?.badgeResolved == true)
        let unloaded = PRViewerRow.prepare(address: address, summary: nil, activity: [], threads: threads)
        XCTAssertEqual(unloaded.map(\.id), ["activity-heading", "root", "reply"])
        XCTAssertNil(unloaded.first { $0.id == "root" }?.parentID, "Threads must remain visible before their review page arrives")
        var open = threads
        open[0].isResolved = false
        let reopened = PRViewerRow.prepare(address: address, summary: nil, activity: activity, threads: open)
        XCTAssertFalse(reopened.first { $0.id == "review-a" }?.badgeResolved == true)
        let outdated = try decoder.decode([PRThread].self, from: Data(threadJSON.replacingOccurrences(of: "\"isResolved\":true", with: "\"isResolved\":false").replacingOccurrences(of: "\"isOutdated\":false", with: "\"isOutdated\":true").utf8))
        let completed = PRViewerRow.prepare(address: address, summary: nil, activity: activity, threads: outdated)
        XCTAssertTrue(completed.first { $0.id == "review-a" }?.badgeResolved == true)
        XCTAssertFalse(completed.first { $0.id == "root" }?.defaultExpanded ?? true)
        XCTAssertFalse(completed.first { $0.id == "review-a" }?.defaultExpanded ?? true)
    }

    func testPaginationPreservesCommentsAndLinkedCommentFocus() async throws {
        let model = makeModel(service: PRViewerFixtureService(eventCount: 1))
        let link = URL(string: "https://github.com/orbit/nova/pull/42#discussion_r1")!
        model.focus(url: link)
        model.refresh()
        try await wait { model.rows.count == 5 }
        XCTAssertEqual(model.focusedRowID, "reply-1")
        XCTAssertNil(model.pendingCommentURL)
        XCTAssertEqual(model.activityCursor, "page-2")
        let hosting = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        try await wait { self.descendant(WKWebView.self, in: hosting) != nil }
        let web = try XCTUnwrap(descendant(WKWebView.self, in: hosting))
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"reply-1\"] .markdown-body:not([hidden])') !== null")) as? Bool == true }
        model.loadActivity()
        model.loadReplies("thread-1")
        try await wait { model.rows.count == 7 }
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article.review .disclosure[aria-expanded=true]') !== null && document.querySelector('article[data-row-id=\"reply-1\"]') !== null")) as? Bool == true }
        XCTAssertEqual(Set(model.rows.map(\.id)).count, model.rows.count)
        XCTAssertTrue(model.rows.contains { $0.body.contains("A later reply") })
        XCTAssertNil(model.activityCursor)
        model.cancel()
    }

    func testCloseCancelsLateLoadingAndRefreshRejectsOldResults() async throws {
        let service = DelayedPRViewerService()
        let model = makeModel(service: service)
        model.refresh()
        try await wait { await service.waitingCount == 1 }
        model.refresh()
        try await wait { await service.waitingCount == 2 }
        try await service.completeFirst(title: "Old response")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.summary)
        try await service.completeFirst(title: "Current response")
        try await wait { model.summary?.title == "Current response" }
        model.refresh()
        try await wait { await service.waitingCount == 1 }
        model.cancel()
        try await service.completeFirst(title: "After close")
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertNil(model.summary)
        XCTAssertTrue(model.loading.isEmpty)
    }

    func testGitHubHTMLRendersBotTablesAlertsAndNestedContent() async throws {
        let model = makeModel(service: PRViewerFixtureService())
        model.refresh()
        try await wait { model.rows.count == 7 }
        var browserURLs: [URL] = [], contentURLs: [URL] = []
        let hosting = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: { browserURLs.append($0) }, openContentURL: { contentURLs.append($0) }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); model.cancel() }
        hosting.layoutSubtreeIfNeeded()
        let web = try XCTUnwrap(descendant(WKWebView.self, in: hosting), "GitHub HTML needs an HTML rendering surface")
        try await wait {
            (try? await web.evaluateJavaScript("document.querySelectorAll('.markdown-body table').length")) as? Int == 1
        }
        let header = try await web.evaluateJavaScript("({status:document.querySelector('.status').textContent, author:document.querySelector('.pr-subtitle .author').href, branches:Array.from(document.querySelectorAll('.branch')).map(n=>n.textContent)})") as? [String: Any]
        XCTAssertEqual(header?["status"] as? String, "Draft")
        XCTAssertEqual(header?["author"] as? String, "https://github.com/alex")
        XCTAssertEqual(header?["branches"] as? [String], ["develop", "fix/audio-initialization"])
        let content = try await web.evaluateJavaScript("document.querySelector('.markdown-body').innerText") as? String
        XCTAssertTrue(content?.contains("Draft PR not reviewed") == true)
        XCTAssertFalse(content?.contains("HIDDEN_BOT_METADATA") == true)
        let table = try await web.evaluateJavaScript("document.querySelector('table td').textContent") as? String
        let alert = try await web.evaluateJavaScript("document.querySelector('.markdown-alert-important h2').textContent") as? String
        let disabled = try await web.evaluateJavaScript("document.querySelector('.task-list-item input').disabled") as? Bool
        let details = try await web.evaluateJavaScript("document.querySelector('details summary').textContent") as? String
        XCTAssertEqual(table, "Draft")
        XCTAssertEqual(alert, "Draft PR not reviewed")
        XCTAssertEqual(disabled, true)
        XCTAssertEqual(details, "Configuration")
        let safe = try await web.evaluateJavaScript("window.untrustedRan !== true && document.querySelector('.markdown-body script') === null && document.querySelector('.markdown-body a').getAttribute('href') === null") as? Bool
        XCTAssertEqual(safe, true, "Comment content must not execute scripts or JavaScript links")
        let closedHeight = try await web.evaluateJavaScript("document.querySelector('details').clientHeight") as? Double
        _ = try await web.evaluateJavaScript("document.querySelector('details').open = true")
        let openHeight = try await web.evaluateJavaScript("document.querySelector('details').clientHeight") as? Double
        XCTAssertGreaterThan(try XCTUnwrap(openHeight), try XCTUnwrap(closedHeight))
        _ = try await web.evaluateJavaScript("document.querySelector('.markdown-body a[href*=issues]').click()")
        try await wait { contentURLs.count == 1 }
        XCTAssertEqual(contentURLs.first?.absoluteString, "https://github.com/orbit/nova/issues/7")
        _ = try await web.evaluateJavaScript("document.querySelector('.summary .external-link').click()")
        try await wait { browserURLs.count == 1 }
        XCTAssertEqual(browserURLs.first, model.address.url)
        model.focus(rowID: "reply-1")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('.reply') !== null")) as? Bool == true }
        let commentUI = try await web.evaluateJavaScript("({avatar:document.querySelector('article.card > .avatar img')?.getAttribute('src'), header:document.querySelector('.comment-card > header .author')?.textContent})") as? [String: Any]
        XCTAssertNotNil(commentUI?["avatar"] as? String)
        XCTAssertNotNil(commentUI?["header"] as? String)
        let commitID = try XCTUnwrap(model.rows.first { $0.kind == "commit" }?.id)
        model.focus(rowID: commitID)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article.commit .commit-sha')?.textContent")) as? String == "abcdef1" }
        _ = try await web.evaluateJavaScript("document.querySelector('article.commit .disclosure').click()")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article.commit .disclosure')?.getAttribute('aria-expanded')")) as? String == "false" }
        let commitHeight = try await web.evaluateJavaScript("document.querySelector('article.commit')?.clientHeight") as? Double
        XCTAssertLessThan(try XCTUnwrap(commitHeight), 80)
        model.focus(rowID: "reply-1")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('footer button.reply') !== null")) as? Bool == true }
        _ = try await web.evaluateJavaScript("document.querySelector('footer button.reply').click()")
        try await wait { model.composerPresented }
        XCTAssertEqual(model.composerThreadID, "thread-1")
        model.composerPresented = false
        _ = try await web.evaluateJavaScript("document.querySelector('.resolve').click()")
        try await wait { model.threads.first?.isResolved == true }
    }

    func testWebViewerRenderingAndLargeConversationScrolling() async throws {
        let model = makeModel(service: PRViewerFixtureService(eventCount: 2000, title: "Fix audio initialization order during call joins, preserve cancellation checks, and prepare final publisher and subscriber transports before capture starts"))
        model.refresh()
        try await wait("large activity rows loaded") { model.rows.count == 2004 }
        let hosting = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); model.cancel() }
        hosting.layoutSubtreeIfNeeded()
        let web = try XCTUnwrap(descendant(WKWebView.self, in: hosting))
        try await wait { (try? await web.evaluateJavaScript("document.querySelectorAll('article').length > 0")) as? Bool == true }
        window.setContentSize(NSSize(width: 1180, height: 820))
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertGreaterThan(web.bounds.width, 700, "The initial viewer must retain its requested width")
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-viewer")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await Task.sleep(for: .milliseconds(100))
        try await capture(web, to: directory.appendingPathComponent("html-summary-light.png"))

        let lastID = try XCTUnwrap(model.rows.last?.id)
        for _ in 0..<2 {
            model.focus(rowID: lastID)
            try await wait("repeated last-comment navigation") {
                (try? await web.evaluateJavaScript("Array.from(document.querySelectorAll('article')).some(n => n.dataset.rowId === '\(lastID)' && n.getBoundingClientRect().top < innerHeight && n.getBoundingClientRect().bottom > 0)")) as? Bool == true
            }
            try await Task.sleep(for: .milliseconds(100))
            let stillVisible = try await web.evaluateJavaScript("Array.from(document.querySelectorAll('article')).some(n => n.dataset.rowId === '\(lastID)' && n.getBoundingClientRect().top < innerHeight && n.getBoundingClientRect().bottom > 0)") as? Bool
            XCTAssertEqual(stillVisible, true, "Measuring an expanded comment above the target must preserve navigation")
            _ = try await web.evaluateJavaScript("window.scrollTo(0, 0)")
            try await Task.sleep(for: .milliseconds(50))
        }
        model.focus(rowID: "event-0")
        try await wait("long comment focus") { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"] .disclosure[aria-expanded=true]') !== null")) as? Bool == true }
        _ = try await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"] .disclosure').click()")
        try await Task.sleep(for: .milliseconds(100))
        let collapsed = try await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"]').clientHeight") as? Double
        _ = try await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"] .disclosure').click()")
        try await wait("comment expansion") {
            let height = (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"]').clientHeight")) as? Double
            return (height ?? 0) > (collapsed ?? 0)
        }
        _ = try await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"] .disclosure').click()")
        try await wait("comment collapse") { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"event-0\"]').clientHeight")) as? Double == collapsed }

        let ids = stride(from: 10, to: model.rows.count - 10, by: 25).map { model.rows[$0].id }
        let metrics: Any = try await withCheckedThrowingContinuation { continuation in
        web.callAsyncJavaScript("""
        const times = [];
        let maxMounted = 0;
        for (const id of ids) {
            await new Promise(resolve => { requestAnimationFrame(resolve); setTimeout(resolve, 100); });
            const start = performance.now();
            window.prConversation.focus(id);
            for (const node of document.querySelectorAll('article')) void node.offsetHeight;
            times.push(performance.now() - start);
            maxMounted = Math.max(maxMounted, document.querySelectorAll('article').length);
        }
        times.sort((a,b) => a-b);
        return {rows: total, samples: times.length, p95_viewport_layout_ms: times[Math.floor((times.length-1)*.95)], max_viewport_layout_ms: times[times.length-1], max_mounted_comments: maxMounted};
        """, arguments: ["ids": ids, "total": model.rows.count], in: nil, in: .page) { continuation.resume(with: $0) }
        }
        let result = try XCTUnwrap(metrics as? [String: Any])
        XCTAssertLessThan(try XCTUnwrap(result["max_mounted_comments"] as? Int), 40, "Offscreen comments must remain unmounted")
        XCTAssertLessThan(try XCTUnwrap(result["p95_viewport_layout_ms"] as? Double), 16.7, "Viewport update and layout should fit a 60 Hz frame")
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("html-performance.json"))

        model.focus(rowID: "event-0")
        window.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(150))
        try await capture(web, to: directory.appendingPathComponent("html-activity-dark.png"))
        model.focus(rowID: "summary")
        try await Task.sleep(for: .milliseconds(100))
        try await capture(web, to: directory.appendingPathComponent("html-summary-dark.png"))
        let wide = try await web.evaluateJavaScript("document.querySelector('h1').clientHeight") as? Double
        window.setContentSize(NSSize(width: 860, height: 600))
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        try await capture(web, to: directory.appendingPathComponent("html-compact-dark.png"))
        let compact = try await web.evaluateJavaScript("({height:document.querySelector('h1')?.clientHeight, width:innerWidth, scrollY})") as? [String: Any]
        XCTAssertGreaterThan(try XCTUnwrap(compact?["height"] as? Double), try XCTUnwrap(wide), "Compact title must wrap; web: \(web.bounds), host: \(hosting.bounds), DOM: \(compact ?? [:])")
    }

    func testOpenConversationsExpandAndCompletionChangesDisclosureDefaults() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!))
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(eventCount: 2, completedChecksOnly: true), openBrowser: { _ in }, onClose: {})
        let model = controller.model
        controller.present(url: address.url)
        try await wait("open conversation rows loaded") { model.rows.count == 6 }
        let window = try XCTUnwrap(controller.window)
        window.level = .floating
        window.setContentSize(NSSize(width: 1180, height: 820))
        let hosting = try XCTUnwrap(window.contentView)
        defer { controller.close() }
        hosting.layoutSubtreeIfNeeded()
        try await wait { self.descendant(WKWebView.self, in: hosting) != nil }
        let web = try XCTUnwrap(descendant(WKWebView.self, in: hosting))
        try await wait("open conversation document ready") { (try? await web.evaluateJavaScript("window.prConversation !== undefined")) as? Bool == true }
        model.focus(rowID: "event-1")
        try await wait("open conversation visible") { (try? await web.evaluateJavaScript("document.querySelector('article.thread .disclosure') !== null")) as? Bool == true }
        let open = try await web.evaluateJavaScript("document.querySelector('article.thread .disclosure').getAttribute('aria-expanded')") as? String
        XCTAssertEqual(open, "true", "Open conversations must expand without a click")
        let parentReactions = try await web.evaluateJavaScript("document.querySelector('article.review .reactions') !== null") as? Bool
        XCTAssertEqual(parentReactions, false)
        _ = try await web.evaluateJavaScript("document.querySelector('article.thread .disclosure').click()")
        model.toggleReaction(subjectID: "reply-0", content: .heart)
        try await wait { model.rows.first { $0.id == "reply-0" }?.reactionGroups.first?.content == .heart }
        try await wait("manual collapse survives reaction update") { (try? await web.evaluateJavaScript("document.querySelector('article.thread .disclosure')?.getAttribute('aria-expanded')")) as? String == "false" }
        model.toggleResolved("thread-1")
        try await wait { model.rows.first { $0.id == "event-1" }?.badgeResolved == true }
        try await wait("resolved review auto collapsed") { (try? await web.evaluateJavaScript("document.querySelector('article.review .disclosure')?.getAttribute('aria-expanded')")) as? String == "false" }
        model.toggleResolved("thread-1")
        try await wait { model.rows.first { $0.id == "reply-0" }?.isResolved == false }
        try await wait("reopened conversation auto expanded") { (try? await web.evaluateJavaScript("document.querySelector('article.thread .disclosure')?.getAttribute('aria-expanded')")) as? String == "true" }
        XCTAssertFalse(model.rows.first { $0.id == "event-1" }?.badgeResolved ?? true)
        model.focus(rowID: "event-1")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article.review .disclosure') !== null")) as? Bool == true }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        try await Task.sleep(for: .milliseconds(200))
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-viewer")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let screenshot = Process()
        screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screenshot.arguments = ["-x", "-o", "-l", String(window.windowNumber), directory.appendingPathComponent("viewer-sidebar-expanded.png").path]
        try screenshot.run(); screenshot.waitUntilExit()
        func sidebarText() throws -> [VNRecognizedTextObservation] {
            let imageURL = directory.appendingPathComponent("viewer-sidebar-current.png")
            let capture = Process()
            capture.executableURL = screenshot.executableURL
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), imageURL.path]
            try capture.run(); capture.waitUntilExit()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(url: imageURL).perform([request])
            return (request.results ?? []).filter { $0.boundingBox.minX > 0.75 }
        }
        let expandedText = try sidebarText()
        XCTAssertTrue(expandedText.contains { $0.topCandidates(1).first?.string.contains("Review Required") == true })
        XCTAssertTrue(expandedText.contains { $0.topCandidates(1).first?.string.contains("Test Core") == true })
        XCTAssertTrue(expandedText.contains { $0.topCandidates(1).first?.string.contains("Why is this changing?") == true })
        for title in ["Checks", "Reviews", "Threads"] {
            let header = try XCTUnwrap(expandedText.first { $0.topCandidates(1).first?.string.contains(title) == true })
            let point = NSPoint(x: window.frame.width - 54, y: window.frame.height * header.boundingBox.midY - 12)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                NSApp.postEvent(event, atStart: false)
            }
            try await Task.sleep(for: .milliseconds(150))
        }
        let collapsedText = try sidebarText().compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertFalse(collapsedText.contains("Review Required"), "The trailing header padding must collapse Reviews")
        XCTAssertFalse(collapsedText.contains("Test Core"), "The full Checks header must collapse its checks")
        XCTAssertFalse(collapsedText.contains("Why is this changing?"), "The full Threads header must collapse its comments")
        let collapsedObservations = try sidebarText()
        let checkTitle = try XCTUnwrap(collapsedObservations.first { $0.topCandidates(1).first?.string.contains("Checks") == true })
        let checkHeader = collapsedObservations.filter { abs($0.boundingBox.midY - checkTitle.boundingBox.midY) * window.frame.height < 8 }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(checkHeader.contains("15"), "Checks and its two-digit total must share one line")
        XCTAssertFalse(checkHeader.contains("0"), "Zero-value status indicators must be hidden")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(200))
            let capture = Process()
            capture.executableURL = screenshot.executableURL
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), directory.appendingPathComponent("viewer-sidebar-collapsed-\(name).png").path]
            try capture.run(); capture.waitUntilExit()
        }
    }

    func testGroupedDisclosuresKeepLargeReviewsVirtualizedAndBadgeOnlyCompleteGroups() async throws {
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!))
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(eventCount: 2, threadCount: 1000), openBrowser: { _ in }, onClose: {})
        let model = controller.model
        controller.present(url: address.url)
        defer { controller.close() }
        try await wait("large review rows loaded") { model.rows.count == 2004 }
        let window = try XCTUnwrap(controller.window)
        window.level = .floating
        window.setContentSize(NSSize(width: 1180, height: 820))
        let web = try XCTUnwrap(descendant(WKWebView.self, in: XCTUnwrap(window.contentView)))
        try await wait("large review document ready") { (try? await web.evaluateJavaScript("window.prConversation !== undefined")) as? Bool == true }
        model.focus(rowID: "event-1")
        try await wait("large review header visible") { (try? await web.evaluateJavaScript("document.querySelector('article.review .disclosure') !== null")) as? Bool == true }
        XCTAssertEqual(window.toolbar?.items.filter { $0.itemIdentifier != .flexibleSpace }.count, 4)
        let initial = try await web.evaluateJavaScript("({open:document.querySelectorAll('article.card.expanded').length, children:document.querySelectorAll('article.thread').length, expanded:document.querySelector('article.review .disclosure').getAttribute('aria-expanded')})") as? [String: Any]
        XCTAssertGreaterThan(try XCTUnwrap(initial?["open"] as? Int), 0)
        XCTAssertGreaterThan(try XCTUnwrap(initial?["children"] as? Int), 0)
        XCTAssertEqual(initial?["expanded"] as? String, "true")
        try await wait("large review child visible") { (try? await web.evaluateJavaScript("document.querySelector('article.thread') !== null")) as? Bool == true }
        let titleWidth = try await web.evaluateJavaScript("(() => {const b=document.querySelector('article.review .disclosure');return b.clientWidth/b.parentElement.clientWidth})()") as? Double
        XCTAssertGreaterThan(try XCTUnwrap(titleWidth), 0.99, "The entire title row must toggle disclosure")
        model.toggleResolved("thread-1")
        try await wait("large review first thread resolved") { model.rows.first { $0.id == "reply-0" }?.badgeResolved == true }
        model.focus(rowID: "event-1")
        try await wait("large review first thread badge visible") { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"reply-0\"] .resolved-badge') !== null")) as? Bool == true }
        let parentBadge = try await web.evaluateJavaScript("document.querySelector('article.review .resolved-badge') !== null") as? Bool
        XCTAssertEqual(parentBadge, false, "Resolving one of 1,000 conversations must not complete the whole review")
        _ = try await web.evaluateJavaScript("document.querySelector('article.review .disclosure').click()")
        let closed = try await web.evaluateJavaScript("document.querySelectorAll('article.thread,article.reply').length") as? Int
        XCTAssertEqual(closed, 0)
        model.focus(rowID: "reply-1498")
        try await wait("large review direct reply visible") { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"reply-1498\"] .markdown-body:not([hidden])') !== null")) as? Bool == true }
        let nested = try await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"reply-1498\"]').style.left") as? String
        XCTAssertEqual(nested, "48px", "A direct reply link opens both ancestors and aligns replies inside their file conversation")
        let ids = stride(from: 0, to: 1000, by: 12).map { "reply-\($0 * 3)" }
        let metrics: Any = try await withCheckedThrowingContinuation { continuation in
            web.callAsyncJavaScript("""
            let maxMounted = 0; const times=[];
            for (const id of ids) {
                await new Promise(resolve => { requestAnimationFrame(resolve); setTimeout(resolve, 100); });
                const start=performance.now(); window.prConversation.focus(id);
                for (const n of document.querySelectorAll('article')) void n.offsetHeight;
                times.push(performance.now()-start);
                maxMounted=Math.max(maxMounted,document.querySelectorAll('article').length);
            }
            times.sort((a,b)=>a-b);
            return {rows:2004,conversations:1000,samples:times.length,max_mounted:maxMounted,p95_viewport_layout_ms:times[Math.floor((times.length-1)*.95)]};
            """, arguments: ["ids": ids], in: nil, in: .page) { continuation.resume(with: $0) }
        }
        let result = try XCTUnwrap(metrics as? [String: Any])
        XCTAssertLessThan(try XCTUnwrap(result["max_mounted"] as? Int), 50)
        XCTAssertLessThan(try XCTUnwrap(result["p95_viewport_layout_ms"] as? Double), 16.7)
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-viewer")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("html-group-performance.json"))
        model.focus(rowID: "reply-1")
        try await Task.sleep(for: .milliseconds(150))
        model.focus(rowID: "event-1")
        try await Task.sleep(for: .milliseconds(150))
        try await capture(web, to: directory.appendingPathComponent("html-grouped-light.png"))
        let screenshot = Process()
        screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        screenshot.arguments = ["-x", "-l", String(window.windowNumber), directory.appendingPathComponent("viewer-glass-light.png").path]
        try screenshot.run()
        screenshot.waitUntilExit()
        window.appearance = NSAppearance(named: .darkAqua)
        try await Task.sleep(for: .milliseconds(500))
        try await capture(web, to: directory.appendingPathComponent("html-grouped-dark.png"))
        let darkScreenshot = Process()
        darkScreenshot.executableURL = screenshot.executableURL
        darkScreenshot.arguments = ["-x", "-l", String(window.windowNumber), directory.appendingPathComponent("viewer-glass-dark.png").path]
        try darkScreenshot.run()
        darkScreenshot.waitUntilExit()
        model.loadReplies("thread-1")
        try await wait { model.rows.contains { $0.id == "reply-2" } }
        XCTAssertEqual(model.rows.first { $0.id == "reply-2" }?.parentID, "reply-0")
        window.makeFirstResponder(web)
        let refreshKey = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "r", charactersIgnoringModifiers: "r", isARepeat: false, keyCode: 15))
        XCTAssertTrue(window.performKeyEquivalent(with: refreshKey), "Command-R must refresh while the conversation has keyboard focus")
    }

    func testCheckHeaderCountsSuccessFailureRunningAndNeutralStates() throws {
        let checks = try JSONDecoder().decode([PRCheck].self, from: Data("""
        [{"name":"Passed","status":"COMPLETED","conclusion":"SUCCESS"},
         {"context":"Status success","state":"SUCCESS"},
         {"name":"Failed","status":"COMPLETED","conclusion":"FAILURE"},
         {"context":"Status error","state":"ERROR"},
         {"name":"Timed out","status":"COMPLETED","conclusion":"TIMED_OUT"},
         {"name":"Running","status":"IN_PROGRESS"},
         {"name":"Queued","status":"QUEUED"},
         {"context":"Status pending","state":"PENDING"},
         {"name":"Skipped","status":"COMPLETED","conclusion":"SKIPPED"},
         {"name":"Cancelled","status":"COMPLETED","conclusion":"CANCELLED"},
         {"name":"Unknown completed","status":"COMPLETED"}]
        """.utf8))
        let counts = PRViewerCheckCounts(checks)
        XCTAssertEqual(counts.succeeded, 2)
        XCTAssertEqual(counts.failed, 3)
        XCTAssertEqual(counts.running, 3)
        XCTAssertEqual(counts.neutral, 3)
        let empty = PRViewerCheckCounts([])
        XCTAssertEqual(empty.failed + empty.succeeded + empty.running + empty.neutral, 0)
    }

    func testCommentDraftsAndThreadActionsUpdateLoadedConversation() async throws {
        let failed = makeModel(service: PRViewerFixtureService(failReply: true))
        failed.refresh()
        try await wait { failed.rows.count == 7 }
        failed.compose(threadID: "thread-1")
        failed.composerDraft = "Please keep this draft."
        failed.submitComment()
        try await wait { failed.errors["Comment"] != nil }
        XCTAssertTrue(failed.composerPresented)
        XCTAssertEqual(failed.composerDraft, "Please keep this draft.")
        failed.composerPresented = false
        failed.compose()
        failed.composerDraft = "A separate PR comment"
        failed.compose(threadID: "thread-1")
        XCTAssertEqual(failed.composerDraft, "Please keep this draft.")
        failed.cancel()

        let model = makeModel(service: PRViewerFixtureService())
        model.refresh()
        try await wait { model.rows.count == 7 }
        model.compose(threadID: "unknown-thread")
        XCTAssertFalse(model.composerPresented)
        model.compose(threadID: "thread-1")
        model.composerDraft = "A new thread reply"
        model.submitComment()
        model.submitComment()
        try await wait { model.rows.contains { $0.body == "A new thread reply" } }
        XCTAssertEqual(model.threads[0].comments.nodes.filter { $0.body == "A new thread reply" }.count, 1)
        XCTAssertEqual(model.activityCursor, "page-2")
        XCTAssertFalse(model.composerPresented)
        XCTAssertEqual(model.composerDraft, "")
        XCTAssertEqual(model.focusedRowID, "reply-98")
        model.toggleResolved("thread-1")
        try await wait { model.threads.first?.isResolved == true && model.loading.isEmpty }
        XCTAssertTrue(model.rows.filter { $0.threadID == "thread-1" }.allSatisfy(\.isResolved))
        model.toggleResolved("thread-1")
        try await wait { model.threads.first?.isResolved == false && model.loading.isEmpty }
        model.compose()
        model.composerDraft = "A new PR comment"
        model.submitComment()
        try await wait { model.activity.contains { $0.body == "A new PR comment" } }
        XCTAssertEqual(model.activityCursor, "page-2")
        model.cancel()
    }

    func testEmojiCompositionAndConfirmedReactionsThroughNativeAndWebControls() async throws {
        let recorder = PRViewerReactionRecorder()
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!))
        let controller = PRViewerWindowController(address: address, service: PRViewerFixtureService(reactionRecorder: recorder), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        let model = controller.model, window = try XCTUnwrap(controller.window)
        try await wait { model.rows.count == 7 }
        window.contentView?.layoutSubtreeIfNeeded()
        try await wait { self.descendant(WKWebView.self, in: window.contentView!) != nil }
        let web = try XCTUnwrap(descendant(WKWebView.self, in: XCTUnwrap(window.contentView)))
        model.focus(rowID: "reply-0")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article.thread .add-reaction') !== null")) as? Bool == true }
        _ = try await web.evaluateJavaScript("document.querySelector('article.thread .add-reaction').click()")
        let picker = try await web.evaluateJavaScript("document.querySelectorAll('article.thread .reaction-picker:not([hidden]) button').length") as? Int
        XCTAssertEqual(picker, 8)
        _ = try await web.evaluateJavaScript("document.querySelector('article.thread .reaction-picker button[aria-label=\"Add Heart reaction\"]').click()")
        model.toggleReaction(subjectID: "reply-0", content: .heart)
        try await wait { model.rows.first { $0.id == "reply-0" }?.reactionGroups.first?.viewerHasReacted == true }
        let addedRequests = await recorder.contents
        XCTAssertEqual(addedRequests, [.heart], "Duplicate writes must be rejected while the subject is loading")
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article.thread .reaction[aria-pressed=true]')?.textContent")) as? String == "❤️ 3" }
        _ = try await web.evaluateJavaScript("document.querySelector('article.thread .reaction[aria-pressed=true]').click()")
        try await wait { model.rows.first { $0.id == "reply-0" }?.reactionGroups.first?.viewerHasReacted == false }
        XCTAssertEqual(model.rows.first { $0.id == "reply-0" }?.reactionGroups.first?.reactors.totalCount, 2)
        model.loadReplies("thread-1")
        try await wait { model.rows.contains { $0.id == "reply-2" } }
        model.toggleReaction(subjectID: "reply-2", content: .rocket)
        model.toggleReaction(subjectID: "unknown", content: .rocket)
        _ = try await web.evaluateJavaScript("window.webkit.messageHandlers.prViewer.postMessage({kind:'reaction',id:'reply-0',content:'UNSUPPORTED'}); true")
        let requests = await recorder.contents
        XCTAssertEqual(requests, [.heart, .heart])
        let compactLink = try await web.evaluateJavaScript("document.querySelector('article.thread .external-link')?.getAttribute('aria-label')") as? String
        XCTAssertEqual(compactLink, "Open on GitHub")
        let oldLink = try await web.evaluateJavaScript("document.querySelector('article.thread .comment-link') !== null") as? Bool
        XCTAssertEqual(oldLink, false)

        model.compose(threadID: "thread-1")
        try await wait { window.attachedSheet?.contentView != nil }
        let sheet = try XCTUnwrap(window.attachedSheet)
        try await wait { self.descendant(NSTextView.self, in: sheet.contentView!) != nil }
        let editor = try XCTUnwrap(descendant(NSTextView.self, in: sheet.contentView!))
        XCTAssertTrue(editor.isEditable)
        let emojiText = "Ready 👍🏽 👩‍💻 🇬🇷 👨‍👩‍👧‍👦 :rocket:"
        sheet.makeFirstResponder(editor)
        editor.insertText(emojiText, replacementRange: editor.selectedRange())
        try await wait { model.composerDraft == emojiText }
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-viewer")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(for: .milliseconds(250))
            let screenshot = Process()
            screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            screenshot.arguments = ["-x", "-l", String(window.windowNumber), directory.appendingPathComponent("viewer-composer-\(name).png").path]
            try screenshot.run(); screenshot.waitUntilExit()
        }
        let send = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: sheet.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertTrue(sheet.performKeyEquivalent(with: send))
        try await wait { model.rows.contains { $0.id == "reply-98" } }
        XCTAssertEqual(model.threads[0].comments.nodes.last?.body, emojiText)
        try await wait { (try? await web.evaluateJavaScript("document.querySelector('article[data-row-id=\"reply-98\"] .markdown-body')?.textContent")) as? String == "Ready 👍🏽 👩‍💻 🇬🇷 👨‍👩‍👧‍👦 🚀" }

        let failed = makeModel(service: PRViewerFixtureService(failReaction: true))
        failed.refresh()
        try await wait { failed.rows.count == 7 }
        failed.toggleReaction(subjectID: "reply-0", content: .heart)
        try await wait { failed.errors["Reaction:reply-0"] != nil && failed.rows.first { $0.id == "reply-0" }?.isReacting == false }
        XCTAssertEqual(failed.rows.first { $0.id == "reply-0" }?.reactionGroups.first?.content, .thumbsUp, "Failed writes must preserve confirmed reactions")
        failed.cancel()
    }

    private func makeModel(service: any PullRequestDetailLoading) -> PRViewerModel {
        PRViewerModel(address: PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!)!, service: service)
    }

    private func wait(_ message: String = "Viewer did not reach the expected state", _ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail(message)
        throw CancellationError()
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    private func capture(_ web: WKWebView, to url: URL) async throws {
        let image = try await web.takeSnapshot(configuration: nil)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

struct PRViewerFixtureService: PullRequestDetailLoading {
    var eventCount = 3
    var title = "Fix audio initialization order during call joins"
    var completedChecksOnly = false
    var failReply = false
    var threadCount = 1
    var failReaction = false
    var reactionRecorder: PRViewerReactionRecorder? = nil
    var mergeable = "MERGEABLE"
    var state = "OPEN"

    func summary(_ address: PullRequestAddress, checksAfter: String?) async throws -> PRSummary {
        try Self.makeSummary(title: title, completedChecksOnly: completedChecksOnly, mergeable: mergeable, state: state)
    }

    static func makeSummary(title: String = "Fix audio initialization order during call joins", completedChecksOnly: Bool = false, mergeable: String = "MERGEABLE", state: String = "OPEN") throws -> PRSummary {
        try decode([
            "id": "PR-42", "locked": false, "title": title, "body": "<!-- HIDDEN_BOT_METADATA -->\n## Goal\nPrepare the audio session **before capture starts**.\n\n## Summary\n- Activate the audio session before capture starts.\n- Preserve cancellation checks.\n- Add focused regression coverage.\n\n## Implementation\n`CallAudioSession` applies the category and activation before microphone changes.\n\n```swift\nawait audioSession.activate()\ntry Task.checkCancellation()\n```\n\n## Validation\nFocused tests and app builds passed. [View the issue](https://github.com/orbit/nova/issues/7).",
            "bodyHTML": "<!-- HIDDEN_BOT_METADATA --><script>window.untrustedRan = true</script><a href=\"javascript:window.untrustedRan=true\">Unsafe link</a><div class=\"markdown-alert markdown-alert-important\"><p class=\"markdown-alert-title\">Important</p><h2>Draft PR not reviewed</h2><ul class=\"contains-task-list\"><li class=\"task-list-item\"><input type=\"checkbox\" disabled> Trigger a manual review</li></ul></div><table><thead><tr><th>Status</th></tr></thead><tbody><tr><td>Draft</td></tr></tbody></table><details><summary>Configuration</summary><pre><code>drafts: true</code></pre></details><p><a href=\"https://github.com/orbit/nova/issues/7\">Issue</a></p>",
            "state": state, "isDraft": true, "createdAt": "2026-10-08T00:00:00Z", "author": ["login": "alex", "url": "https://github.com/alex", "avatarUrl": "https://avatars.githubusercontent.com/u/583231?s=56"],
            "headRefName": "fix/audio-initialization", "baseRefName": "develop", "additions": 533, "deletions": 40,
            "mergeable": mergeable, "reviewDecision": "REVIEW_REQUIRED",
            "commits": ["totalCount": 2, "nodes": [["commit": ["statusCheckRollup": ["contexts": ["nodes": completedChecksOnly ? (0..<15).map { ["name": "Test Core \($0)", "status": "COMPLETED", "conclusion": "SUCCESS"] } + [["name": "Skipped check", "status": "COMPLETED", "conclusion": "SKIPPED"]] : [
                ["name": "Test Core (Debug)", "status": "IN_PROGRESS", "detailsUrl": "https://github.com/orbit/nova/actions/runs/1"],
                ["name": "Test SwiftUI (Debug)", "status": "QUEUED"],
                ["name": "Automated Code Review", "status": "COMPLETED", "conclusion": "SUCCESS"],
                ["context": "Quality Gate", "state": "SUCCESS", "targetUrl": "https://github.com/orbit/nova/pull/42"],
                ["name": "Failed check", "status": "COMPLETED", "conclusion": "FAILURE"],
                ["name": "Skipped check", "status": "COMPLETED", "conclusion": "SKIPPED"]
            ], "pageInfo": ["hasNextPage": false]]]]]]]
        ])
    }

    func activity(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRActivity> {
        let indices = after == nil ? Array(0..<eventCount) : [eventCount]
        var nodes: [[String: Any]] = []
        for index in indices {
            var node: [String: Any] = [:]
            node["__typename"] = index == 1 ? "PullRequestReview" : "IssueComment"
            node["id"] = "event-\(index)"
            if index % 4 == 0 {
                node["body"] = String(repeating: "## Review notes\nThis is a **long comment** with `inline code`.\n- Keep initialization ordered.\n- Preserve cancellation.\n\n", count: 24)
                node["bodyHTML"] = String(repeating: "<h2>Review notes</h2><p>This is a <strong>long comment</strong> with <code>inline code</code>.</p><ul><li>Keep initialization ordered.</li><li>Preserve cancellation.</li></ul>", count: 24)
            } else {
                node["body"] = "This change looks good. Please keep the regression for **session activation order**.\n\n```swift\ntry await session.activate()\n```"
                node["bodyHTML"] = "<p>This change looks good. Please keep the regression for <strong>session activation order</strong>.</p><pre><code>try await session.activate()</code></pre>"
            }
            node["url"] = "https://github.com/orbit/nova/pull/42#issuecomment-\(index)"
            node["createdAt"] = "2026-10-08T01:00:00Z"
            node["author"] = ["login": index % 4 == 0 ? "review-bot" : "morgan", "url": "https://github.com/morgan", "avatarUrl": "https://avatars.githubusercontent.com/u/583231?s=56"]
            node["state"] = "COMMENTED"
            node["viewerCanReact"] = true
            node["reactionGroups"] = [["content": "THUMBS_UP", "viewerHasReacted": false, "reactors": ["totalCount": 2]]]
            if index == 1 {
                node["comments"] = ["totalCount": threadCount]
                node["body"] = ""
                node["bodyHTML"] = ""
            }
            if index == 2 {
                node = ["__typename": "PullRequestCommit", "commit": ["oid": "abcdef123456789", "messageHeadline": "Fix audio initialization order", "committedDate": "2026-10-08T01:00:00Z", "url": "https://github.com/orbit/nova/commit/abcdef123456789", "author": ["name": "Morgan", "user": ["login": "morgan", "url": "https://github.com/morgan", "avatarUrl": "https://avatars.githubusercontent.com/u/583231?s=56"]]]]
            } else if index == 3 {
                node = ["__typename": "ConvertToDraftEvent", "id": "draft-event", "createdAt": "2026-10-08T01:00:00Z", "actor": ["login": "alex", "url": "https://github.com/alex"]]
            }
            nodes.append(node)
        }
        let pageInfo: [String: Any] = after == nil ? ["hasNextPage": true, "endCursor": "page-2"] : ["hasNextPage": false]
        return try Self.decode(["nodes": nodes, "pageInfo": pageInfo])
    }

    func threads(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRThread> {
        let nodes: [[String: Any]] = (0..<threadCount).map { index in
            ["id": "thread-\(index + 1)", "path": "Sources/Audio/CallAudioSession.swift", "line": 586 + index, "isResolved": false, "isOutdated": false, "viewerCanReply": true, "viewerCanResolve": true, "viewerCanUnresolve": false,
             "comments": ["nodes": [Self.comment(index * 3, body: "Why is this changing?", reviewID: "event-1"), Self.comment(index * 3 + 1, body: "The final transport must be ready before capture starts.")], "pageInfo": ["hasNextPage": true, "endCursor": "reply-page-2"]]]
        }
        return try Self.decode(["nodes": nodes, "pageInfo": ["hasNextPage": false]])
    }

    func replies(threadID: String, after: String?) async throws -> PRConnection<PRComment> {
        try Self.decode(["nodes": [Self.comment(2, body: "A later reply")], "pageInfo": ["hasNextPage": false]])
    }

    func addComment(pullRequestID: String, body: String) async throws -> PRComment {
        try Self.decode(Self.comment(99, body: body))
    }
    func reply(threadID: String, body: String) async throws -> PRComment {
        if failReply { throw GitHubAPIClientError.invalidResponse(message: "Could not post reply") }
        var result = Self.comment(98, body: body)
        if body == "Ready 👍🏽 👩‍💻 🇬🇷 👨‍👩‍👧‍👦 :rocket:" { result["bodyHTML"] = "<p dir=\"auto\">Ready 👍🏽 👩‍💻 🇬🇷 👨‍👩‍👧‍👦 🚀</p>" }
        return try Self.decode(result)
    }
    func setResolved(threadID: String, resolved: Bool) async throws -> PRThreadResolution {
        try Self.decode(["id": threadID, "isResolved": resolved, "viewerCanResolve": !resolved, "viewerCanUnresolve": resolved])
    }

    func setReaction(subjectID: String, content: PRReactionContent, added: Bool) async throws -> PRReactionSubject {
        await reactionRecorder?.record(content)
        try await Task.sleep(for: .milliseconds(30))
        if failReaction { throw GitHubAPIClientError.invalidResponse(message: "Could not update reaction") }
        return try Self.decode(["id": subjectID, "viewerCanReact": true, "reactionGroups": [["content": content.rawValue, "viewerHasReacted": added, "reactors": ["totalCount": added ? 3 : 2]]]])
    }

    private static func comment(_ index: Int, body: String, reviewID: String? = nil) -> [String: Any] {
        var result: [String: Any] = ["id": "reply-\(index)", "body": body, "bodyHTML": "<p>\(body)</p>", "url": "https://github.com/orbit/nova/pull/42#discussion_r\(index)", "createdAt": "2026-10-08T02:00:00Z", "author": ["login": "morgan", "url": "https://github.com/morgan", "avatarUrl": "https://avatars.githubusercontent.com/u/583231?s=56"]]
        if let reviewID { result["pullRequestReview"] = ["id": reviewID] }
        result["viewerCanReact"] = index != 2
        result["reactionGroups"] = [["content": "THUMBS_UP", "viewerHasReacted": false, "reactors": ["totalCount": 2]]]
        return result
    }
    private static func decode<T: Decodable>(_ value: [String: Any]) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
}

actor PRViewerReactionRecorder {
    private(set) var contents: [PRReactionContent] = []
    func record(_ content: PRReactionContent) { contents.append(content) }
}

private actor DelayedPRViewerService: PullRequestDetailLoading {
    private var pending: [CheckedContinuation<PRSummary, Never>] = []
    var waitingCount: Int { pending.count }
    func summary(_ address: PullRequestAddress, checksAfter: String?) async throws -> PRSummary {
        await withCheckedContinuation { pending.append($0) }
    }
    func completeFirst(title: String) throws { pending.removeFirst().resume(returning: try PRViewerFixtureService.makeSummary(title: title)) }
    func activity(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRActivity> { try await PRViewerFixtureService().activity(address, after: after) }
    func threads(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRThread> { try await PRViewerFixtureService().threads(address, after: after) }
    func replies(threadID: String, after: String?) async throws -> PRConnection<PRComment> { try await PRViewerFixtureService().replies(threadID: threadID, after: after) }
    func addComment(pullRequestID: String, body: String) async throws -> PRComment { try await PRViewerFixtureService().addComment(pullRequestID: pullRequestID, body: body) }
    func reply(threadID: String, body: String) async throws -> PRComment { try await PRViewerFixtureService().reply(threadID: threadID, body: body) }
    func setResolved(threadID: String, resolved: Bool) async throws -> PRThreadResolution { try await PRViewerFixtureService().setResolved(threadID: threadID, resolved: resolved) }
    func setReaction(subjectID: String, content: PRReactionContent, added: Bool) async throws -> PRReactionSubject { try await PRViewerFixtureService().setReaction(subjectID: subjectID, content: content, added: added) }
}
