import AppKit
import GHOrchestratorCore
import WebKit
import XCTest
@testable import GHOrchestrator

@MainActor
final class PRViewerMarketingRenderingTests: XCTestCase {
    func testCaptureConversationAndFilesChanged() async throws {
        try await wait { NSRunningApplication.current.isFinishedLaunching }
        let activationPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        defer { NSApp.setActivationPolicy(activationPolicy) }
        let address = try XCTUnwrap(PullRequestAddress(url: URL(string: "https://github.com/orbit-labs/nova-app/pull/42")!))
        let controller = PRViewerWindowController(address: address, service: MarketingPRService(), openBrowser: { _ in }, onClose: {})
        controller.present(url: address.url)
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.appearance = NSAppearance(named: .aqua)
        window.center()
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let directory = URL(fileURLWithPath: "/tmp/gho-shots")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await wait { controller.model.loading.isEmpty && !controller.model.rows.isEmpty }
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(controller.model.errors.isEmpty, "\(controller.model.errors)")
        window.makeFirstResponder(nil)
        try capture(window, to: directory.appendingPathComponent("pr-viewer-conversation.png"))

        controller.model.openDiffThread("audio-review")
        let model = try XCTUnwrap(controller.model.diffs)
        try await wait { self.diffWeb(in: window.contentView!) != nil }
        let web = try XCTUnwrap(diffWeb(in: XCTUnwrap(window.contentView)))
        let chrome = try XCTUnwrap(web.superview as? PRDiffChromeView)
        try await wait { chrome.reviewThreads["audio-review"] != nil }
        try await Task.sleep(for: .seconds(1))
        model.selectFile()
        try await Task.sleep(for: .milliseconds(300))
        let comment = try XCTUnwrap(chrome.reviewThreads["audio-review"])
        XCTAssertTrue(comment.frame.intersects(chrome.bounds), "The marketing capture must include the inline review")
        XCTAssertEqual(model.visiblePath, MarketingPRService.path)
        XCTAssertTrue(model.errors.isEmpty)
        try capture(window, to: directory.appendingPathComponent("pr-viewer-files.png"))
    }

    private func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<1_000 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Marketing viewer did not finish rendering")
        throw CancellationError()
    }

    private func diffWeb(in view: NSView) -> WKWebView? {
        if let web = view as? WKWebView, web.accessibilityLabel() == "Pull request file diffs" { return web }
        return view.subviews.lazy.compactMap { self.diffWeb(in: $0) }.first
    }

    private func capture(_ window: NSWindow, to url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(window.windowNumber), url.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }
}

private struct MarketingPRService: PullRequestDetailLoading, PullRequestDiffLoading {
    static let path = "Sources/Audio/CallAudioSession.swift"
    private let base = PRViewerFixtureService()
    private static let author: [String: String] = ["login": "alex", "url": "https://github.com/orbit-labs"]
    private static let reviewer: [String: String] = ["id": "reviewer-1", "login": "morgan", "url": "https://github.com/orbit-labs"]
    private static let date = "2026-10-11T18:00:00Z"
    private static let files = [path, "Sources/Audio/AudioController.swift", "Tests/Audio/CallAudioSessionTests.swift", "CHANGELOG.md"]

    func summary(_ address: PullRequestAddress, checksAfter: String?) async throws -> PRSummary {
        try decode([
            "id": "PR-42", "title": "Prepare audio before joining a call", "body": "Activate the audio session before microphone capture starts.",
            "bodyHTML": "<h2>Summary</h2><p>Prepare the audio session <strong>before microphone capture starts</strong>, so the first frames are ready when you join a call.</p><ul><li>Activate the session before starting capture.</li><li>Preserve cancellation when a join is interrupted.</li><li>Add regression coverage for repeated joins.</li></ul><h2>Validation</h2><p>Audio session tests and the macOS build pass. Verified joining, leaving and rejoining a call.</p>",
            "state": "OPEN", "isDraft": false, "locked": false, "createdAt": Self.date, "author": Self.author,
            "headRefName": "fix/audio-initialization", "baseRefName": "main", "additions": 16, "deletions": 5, "changedFiles": 4,
            "mergeable": "MERGEABLE", "reviewDecision": "REVIEW_REQUIRED",
            "reviewRequests": ["nodes": [["id": "request-1", "requestedReviewer": Self.reviewer]], "pageInfo": ["hasNextPage": false]],
            "commits": ["totalCount": 2, "nodes": [["commit": ["statusCheckRollup": ["contexts": ["nodes": ["Build macOS", "Audio session tests", "Code review"].map { ["name": $0, "status": "COMPLETED", "conclusion": "SUCCESS"] }, "pageInfo": ["hasNextPage": false]]]]]]]
        ])
    }

    func activity(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRActivity> {
        try decode(["nodes": [["__typename": "PullRequestReview", "id": "review-1", "author": Self.reviewer, "createdAt": Self.date, "state": "COMMENTED", "body": "The activation order looks good. One question about cancellation below.", "bodyHTML": "<p>The activation order looks good. One question about cancellation below.</p>", "comments": ["totalCount": 1]]], "pageInfo": ["hasNextPage": false]])
    }

    func threads(_ address: PullRequestAddress, after: String?) async throws -> PRConnection<PRThread> {
        try decode(["nodes": [["id": "audio-review", "path": Self.path, "line": 16, "diffSide": "RIGHT", "isResolved": false, "isOutdated": false, "viewerCanReply": true, "viewerCanResolve": true,
            "comments": ["nodes": [["id": "audio-comment", "author": Self.reviewer, "createdAt": Self.date, "body": "Can we keep the cancellation check here? A join may be cancelled while the audio session is activating.", "bodyHTML": "<p>Can we keep the cancellation check here? A join may be cancelled while the audio session is activating.</p>", "pullRequestReview": ["id": "review-1"], "url": "https://github.com/orbit-labs/nova-app/pull/42#discussion_r1"]], "pageInfo": ["hasNextPage": false]]]], "pageInfo": ["hasNextPage": false]])
    }

    func diffSnapshot(_ address: PullRequestAddress, after: String?) async throws -> PRDiffSnapshot {
        try decode(["id": "PR-42", "baseRefOid": "base", "headRefOid": "head", "changedFiles": 4,
            "files": ["nodes": Self.files.map { ["path": $0, "additions": $0 == Self.path ? 13 : 1, "deletions": $0 == Self.path ? 2 : 1, "changeType": "MODIFIED", "viewerViewedState": $0 == Self.path ? "UNVIEWED" : "VIEWED"] }, "pageInfo": ["hasNextPage": false]]])
    }

    func diffPatches(_ address: PullRequestAddress, page: Int) async throws -> [PRDiffPatch] {
        let patch = """
        @@ -1,16 +1,27 @@
         import AVFoundation
         
         @MainActor
         final class CallAudioSession {
             private let session: AVAudioSession
             private let microphone: MicrophoneCapture
         
             func join() async throws {
        -        try await microphone.startCapture()
        -        try session.setActive(true)
        +        try session.setCategory(
        +            .playAndRecord,
        +            mode: .voiceChat,
        +            options: [.allowBluetoothHFP]
        +        )
        +        try await activateSession()
        +
        +        try Task.checkCancellation()
        +        try await microphone.startCapture()
             }
         
             func leave() async {
                 await microphone.stopCapture()
             }
        +
        +    private func activateSession() async throws {
        +        try session.setActive(true)
        +    }
         }
        """
        return try decode(Self.files.map { ["filename": $0, "sha": $0, "patch": $0 == Self.path ? patch : "@@ -1 +1 @@\n-Previous behavior\n+Prepare audio before capture starts"] })
    }

    func replies(threadID: String, after: String?) async throws -> PRConnection<PRComment> { try await base.replies(threadID: threadID, after: after) }
    func addComment(pullRequestID: String, body: String) async throws -> PRComment { try await base.addComment(pullRequestID: pullRequestID, body: body) }
    func reply(threadID: String, body: String) async throws -> PRComment { try await base.reply(threadID: threadID, body: body) }
    func deleteComment(commentID: String) async throws { try await base.deleteComment(commentID: commentID) }
    func setResolved(threadID: String, resolved: Bool) async throws -> PRThreadResolution { try await base.setResolved(threadID: threadID, resolved: resolved) }
    func setReaction(subjectID: String, content: PRReactionContent, added: Bool) async throws -> PRReactionSubject { try await base.setReaction(subjectID: subjectID, content: content, added: added) }
    func setDescriptionTask(_ address: PullRequestAddress, offset: Int, checked: Bool, expectedBody: String) async throws -> PRDescriptionUpdate { try await base.setDescriptionTask(address, offset: offset, checked: checked, expectedBody: expectedBody) }
    func updateText(_ address: PullRequestAddress, title: String, body: String, expectedTitle: String, expectedBody: String) async throws -> PRTextUpdate { try await base.updateText(address, title: title, body: body, expectedTitle: expectedTitle, expectedBody: expectedBody) }
    func reviewers(_ address: PullRequestAddress, query: String, after: String?) async throws -> PRConnection<PRReviewer> { try await base.reviewers(address, query: query, after: after) }
    func requestReviewers(_ address: PullRequestAddress, userIDs: [String]) async throws -> PRReviewersUpdate { try await base.requestReviewers(address, userIDs: userIDs) }
    func merge(_ address: PullRequestAddress, request: PRMergeRequest) async throws -> PRMergeUpdate { try await base.merge(address, request: request) }
    func setFileViewed(_ address: PullRequestAddress, path: String, viewed: Bool, expected: PRDiffRevision) async throws { try await base.setFileViewed(address, path: path, viewed: viewed, expected: expected) }
    func addLineComment(_ address: PullRequestAddress, selection: PRDiffLineSelection, body: String, expected: PRDiffRevision) async throws -> PRComment { try await base.addLineComment(address, selection: selection, body: body, expected: expected) }

    private func decode<T: Decodable>(_ value: Any) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: JSONSerialization.data(withJSONObject: value))
    }
}
