import AppKit
import GHOrchestratorCore
import SwiftUI
import XCTest
@testable import GHOrchestrator

@MainActor
final class PRViewerTests: XCTestCase {
    func testPaginationPreservesCommentsAndLinkedCommentFocus() async throws {
        let model = makeModel(service: PRViewerFixtureService(eventCount: 3))
        let link = URL(string: "https://github.com/orbit/nova/pull/42#discussion_r1")!
        model.focus(url: link)
        model.refresh()
        try await wait { model.rows.count == 7 }
        XCTAssertEqual(model.focusedRowID, "reply-1")
        XCTAssertNil(model.pendingCommentURL)
        XCTAssertEqual(model.activityCursor, "page-2")
        model.loadActivity()
        model.loadReplies("thread-1")
        try await wait { model.rows.count == 9 }
        XCTAssertEqual(Set(model.rows.map(\.id)).count, model.rows.count)
        XCTAssertTrue(model.rows.contains { $0.body.string.contains("A later reply") })
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

    func testNativeViewerRenderingAndLargeConversationScrolling() async throws {
        let model = makeModel(service: PRViewerFixtureService(eventCount: 2000))
        model.refresh()
        try await wait { model.rows.count == 2004 }
        let hosting = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); model.cancel() }
        try await Task.sleep(for: .milliseconds(300))
        hosting.layoutSubtreeIfNeeded()
        let table = try XCTUnwrap(descendant(NSTableView.self, in: hosting))
        let scroll = try XCTUnwrap(table.enclosingScrollView)
        XCTAssertEqual(table.numberOfRows, 2004)
        XCTAssertGreaterThan(table.bounds.width, 700)
        try await wait { table.rect(ofRow: 0).height > 500 }
        try await wait { table.rect(ofRow: table.numberOfRows - 1).height != 232 }
        let directory = URL(fileURLWithPath: "/tmp/gho-pr-viewer")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try capture(hosting, to: directory.appendingPathComponent("summary-light.png"))
        let lastID = try XCTUnwrap(model.rows.last?.id)
        model.focus(rowID: lastID)
        try await wait { NSLocationInRange(table.numberOfRows - 1, table.rows(in: scroll.documentVisibleRect)) }
        table.scrollRowToVisible(0)
        model.focus(rowID: lastID)
        try await wait { NSLocationInRange(table.numberOfRows - 1, table.rows(in: scroll.documentVisibleRect)) }
        let longCommentIndex = try XCTUnwrap(model.rows.firstIndex { !$0.isSummary && $0.body.length > 2000 })
        table.scrollRowToVisible(longCommentIndex)
        table.layoutSubtreeIfNeeded()
        let collapsedHeight = table.rect(ofRow: longCommentIndex).height
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: longCommentIndex, makeIfNecessary: true) as? PRConversationCell)
        cell.layoutSubtreeIfNeeded()
        let expand = try XCTUnwrap(cell.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first { $0.title == "Expand" })
        XCTAssertFalse(expand.isHidden)
        expand.performClick(nil)
        try await wait { table.rect(ofRow: longCommentIndex).height > collapsedHeight }
        let expandedCell = try XCTUnwrap(table.view(atColumn: 0, row: longCommentIndex, makeIfNecessary: true) as? PRConversationCell)
        let collapse = try XCTUnwrap(expandedCell.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }.first { $0.title == "Collapse" })
        collapse.performClick(nil)
        try await wait { table.rect(ofRow: longCommentIndex).height == collapsedHeight }
        try await wait { table.rect(ofRow: table.numberOfRows - 1).height != 232 }
        var durations: [Double] = []
        var scrollTimes: [Double] = [], layoutTimes: [Double] = [], displayTimes: [Double] = []
        for index in stride(from: 10, to: table.numberOfRows - 10, by: 25) {
            let start = CFAbsoluteTimeGetCurrent()
            table.scrollRowToVisible(index)
            let scrolled = CFAbsoluteTimeGetCurrent()
            scroll.layoutSubtreeIfNeeded()
            table.layoutSubtreeIfNeeded()
            let laidOut = CFAbsoluteTimeGetCurrent()
            window.displayIfNeeded()
            let displayed = CFAbsoluteTimeGetCurrent()
            scrollTimes.append((scrolled - start) * 1000)
            layoutTimes.append((laidOut - scrolled) * 1000)
            displayTimes.append((displayed - laidOut) * 1000)
            durations.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
        }
        let visible = table.rows(in: scroll.documentVisibleRect)
        XCTAssertLessThan(visible.length, 30, "The table must virtualize a large conversation")
        let cells = table.subviews.flatMap { $0.subviews }.compactMap { $0 as? PRConversationCell }
        XCTAssertGreaterThan(cells.count, 0)
        XCTAssertLessThan(cells.count, 60, "Offscreen rows must not retain thousands of native cells")
        durations.sort()
        let p95 = durations[Int(Double(durations.count - 1) * 0.95)]
        XCTAssertLessThan(p95, 16.7, "Scrolling should stay within a 60 Hz frame budget")
        let metrics: [String: Any] = ["rows": table.numberOfRows, "scroll_samples": durations.count, "p95_scroll_ms": p95, "max_scroll_ms": durations.last ?? 0, "visible_rows": visible.length, "mounted_cells": cells.count, "scroll_times": scrollTimes, "layout_times": layoutTimes, "display_times": displayTimes]
        try JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("performance.json"))
        window.appearance = NSAppearance(named: .darkAqua)
        table.scrollRowToVisible(table.numberOfRows - 1)
        try await Task.sleep(for: .milliseconds(150))
        try capture(hosting, to: directory.appendingPathComponent("activity-dark.png"))
        table.scrollRowToVisible(0)
        try capture(hosting, to: directory.appendingPathComponent("summary-dark.png"))
        let wideSummaryHeight = table.rect(ofRow: 0).height
        let wideTitleHeight = PRConversationLayout.measure(model.rows[0], width: table.frameOfCell(atColumn: 0, row: 0).width - 96, expanded: false).titleHeight
        window.setContentSize(NSSize(width: 860, height: 600))
        try await Task.sleep(for: .milliseconds(150))
        hosting.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(table.bounds.width, 500)
        try await wait { table.rect(ofRow: 0).height > wideSummaryHeight }
        let summaryCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? PRConversationCell)
        summaryCell.layoutSubtreeIfNeeded()
        let title = try XCTUnwrap(summaryCell.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }.first { $0.stringValue == model.summary?.title })
        XCTAssertGreaterThan(title.frame.height, wideTitleHeight, "The wrapped title must have room for every line after resizing")
        try capture(hosting, to: directory.appendingPathComponent("compact-dark.png"))
    }

    private func makeModel(service: any PullRequestDetailLoading) -> PRViewerModel {
        PRViewerModel(address: PullRequestAddress(url: URL(string: "https://github.com/orbit/nova/pull/42")!)!, service: service)
    }

    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Viewer did not reach the expected state")
        throw CancellationError()
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.descendant(type, in: $0) }.first
    }

    private func capture(_ view: NSView, to url: URL) throws {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

struct PRViewerFixtureService: PullRequestDetailLoading {
    var eventCount = 3

    func summary(_ address: PullRequestAddress, checksAfter: String?) async throws -> PRSummary {
        try Self.makeSummary()
    }

    static func makeSummary(title: String = "Fix audio initialization order during call joins") throws -> PRSummary {
        try decode([
            "title": title, "body": "## Goal\nPrepare the audio session **before capture starts**.\n\n## Summary\n- Activate the audio session before capture starts.\n- Preserve cancellation checks.\n- Add focused regression coverage.\n\n## Implementation\n`CallAudioSession` applies the category and activation before microphone changes.\n\n```swift\nawait audioSession.activate()\ntry Task.checkCancellation()\n```\n\n## Validation\nFocused tests and app builds passed. [View the issue](https://github.com/orbit/nova/issues/7).",
            "state": "OPEN", "isDraft": true, "createdAt": "2026-10-08T00:00:00Z", "author": ["login": "alex"],
            "headRefName": "fix/audio-initialization", "baseRefName": "develop", "additions": 533, "deletions": 40,
            "mergeable": "MERGEABLE", "reviewDecision": "REVIEW_REQUIRED",
            "commits": ["nodes": [["commit": ["statusCheckRollup": ["contexts": ["nodes": [
                ["name": "Test Core (Debug)", "status": "IN_PROGRESS", "detailsUrl": "https://github.com/orbit/nova/actions/runs/1"],
                ["name": "Test SwiftUI (Debug)", "status": "QUEUED"],
                ["name": "Automated Code Review", "status": "COMPLETED", "conclusion": "SUCCESS"],
                ["context": "Quality Gate", "state": "SUCCESS", "targetUrl": "https://github.com/orbit/nova/pull/42"]
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
            } else {
                node["body"] = "This change looks good. Please keep the regression for **session activation order**.\n\n```swift\ntry await session.activate()\n```"
            }
            node["url"] = "https://github.com/orbit/nova/pull/42#issuecomment-\(index)"
            node["createdAt"] = "2026-10-08T01:00:00Z"
            node["author"] = ["login": index % 4 == 0 ? "review-bot" : "morgan"]
            node["state"] = "COMMENTED"
            nodes.append(node)
        }
        let pageInfo: [String: Any] = after == nil ? ["hasNextPage": true, "endCursor": "page-2"] : ["hasNextPage": false]
        return try Self.decode(["nodes": nodes, "pageInfo": pageInfo])
    }

    func threads(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRThread> {
        try Self.decode(["nodes": [["id": "thread-1", "path": "Sources/Audio/CallAudioSession.swift", "line": 586, "isResolved": false, "isOutdated": false,
            "comments": ["nodes": [Self.comment(0, body: "Why is this changing?"), Self.comment(1, body: "The final transport must be ready before capture starts.")], "pageInfo": ["hasNextPage": true, "endCursor": "reply-page-2"]]]], "pageInfo": ["hasNextPage": false]])
    }

    func replies(threadID: String, after: String?) async throws -> PRConnection<PRComment> {
        try Self.decode(["nodes": [Self.comment(2, body: "A later reply")], "pageInfo": ["hasNextPage": false]])
    }

    private static func comment(_ index: Int, body: String) -> [String: Any] {
        ["id": "reply-\(index)", "body": body, "url": "https://github.com/orbit/nova/pull/42#discussion_r\(index)", "createdAt": "2026-10-08T02:00:00Z", "author": ["login": "morgan"]]
    }
    private static func decode<T: Decodable>(_ value: [String: Any]) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
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
}
