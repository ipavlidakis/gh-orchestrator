import AppKit
import GHOrchestratorCore
import SwiftUI
import XCTest
@testable import GHOrchestrator

/// Renders the popover and Settings panes with design fixtures to PNGs so the UI can be compared with the design canvas.
@MainActor
final class DesignParityRenderingTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/gho-shots", isDirectory: true)

    func testRenderPopoverAndSettingsForDesignReview() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let repository = ObservedRepository(owner: "GetStream", name: "stream-video-swift")
        let other = ObservedRepository(owner: "ipavlidakis", name: "vesputio-fullstack")
        store.settings.observedRepositories = [repository, other]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())

        let model = MenuBarDashboardModel(settingsStore: store)
        model.authenticationState = .authenticated(username: "ipavlidakis")
        let pulls = fixturePullRequests(repository: repository)
        model.state = .loaded([RepositorySection(repository: repository, pullRequests: pulls)])
        model.expandedChecksPullRequestIDs = [pulls[0].id]
        model.lastRefreshedAt = Date().addingTimeInterval(-12)
        let log = GitHubRequestLogModel()
        await log.record(GitHubRequestRecord(
            method: "POST", endpoint: "api.github.com/graphql", statusCode: 200,
            rateLimit: GitHubRateLimitStatus(limit: 5000, remaining: 4955, used: 45, resetDate: .now, resource: "graphql"),
            errorMessage: nil
        ))

        let popover = MenuBarPlaceholderView(
            model: model, softwareUpdateModel: updates, requestLogModel: log,
            openSettingsAction: {}, openURLAction: { _ in }, onMenuVisibilityChange: { _ in }
        )
        .frame(width: 440, height: 740, alignment: .topLeading)
        try await render(popover, size: CGSize(width: 440, height: 740), name: "popover")

        let settingsModel = SettingsModel(store: store, authenticationState: .authenticated(username: "ipavlidakis"))
        let window = SettingsWindowView(
            model: settingsModel, softwareUpdateModel: updates, requestLogModel: log,
            menuVisibilityController: SettingsWindowMenuVisibilityController(mainMenuProvider: { nil }),
            onSettingsWindowVisibilityChange: { _ in }
        )
        try await render(window.environment(\.settingsGlassDisabled, true), size: CGSize(width: 820, height: 620), name: "settings-window")
        try await renderChrome(window, name: "settings-chrome")
        func page<V: View>(_ v: V) -> some View {
            VStack(alignment: .leading, spacing: 20) { v }.padding(28).frame(width: 624, alignment: .leading)
        }
        try await render(page(GitHubSettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 420), name: "pane-github")
        try await render(page(RepositorySettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 420), name: "pane-repositories")
        try await render(page(NotificationSettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 760), name: "pane-notifications")
        try await render(page(GitHubRequestUsagePane(requestLogModel: log)), size: CGSize(width: 624, height: 420), name: "pane-requests")
    }

    func testPopoverReportsHeightThatFitsItsContent() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let repository = ObservedRepository(owner: "GetStream", name: "stream-video-swift")
        store.settings.observedRepositories = [repository]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        let model = MenuBarDashboardModel(settingsStore: store)
        model.authenticationState = .authenticated(username: "ipavlidakis")
        let pulls = fixturePullRequests(repository: repository)
        var reported: [CGFloat] = []

        func render(collapsed: Bool) async throws -> CGFloat {
            model.state = .loaded([RepositorySection(repository: repository, pullRequests: pulls)])
            model.collapsedRepositoryIDs = collapsed ? [repository.normalizedLookupKey] : []
            reported = []
            let wired = MenuBarPlaceholderView(
                model: model, softwareUpdateModel: updates, maximumHeight: 620,
                onPreferredHeightChange: { reported.append($0) },
                openSettingsAction: {}, openURLAction: { _ in }, onMenuVisibilityChange: { _ in }
            )
            try await self.render(wired.frame(width: 440, height: 620, alignment: .topLeading), size: CGSize(width: 440, height: 620), name: collapsed ? "popover-collapsed" : "popover-full")
            return try XCTUnwrap(reported.last)
        }

        let collapsedHeight = try await render(collapsed: true)
        let fullHeight = try await render(collapsed: false)
        XCTAssertLessThan(collapsedHeight, 300, "A collapsed dashboard must not keep the fixed popover height")
        XCTAssertLessThanOrEqual(fullHeight, 620)
        XCTAssertGreaterThan(fullHeight, collapsedHeight)
    }

    private func fixturePullRequests(repository: ObservedRepository) -> [PullRequestItem] {
        let now = Date()
        func url(_ n: Int) -> URL { URL(string: "https://github.com/x/y/pull/\(n)")! }
        let pending = PullRequestItem(
            repository: repository, number: 1335,
            title: "[IOS-2105] Stop retrying unrecoverable join errors and evict failed calls",
            url: url(1335), isDraft: false, updatedAt: now.addingTimeInterval(-660),
            reviewStatus: .reviewRequired, unresolvedReviewThreadCount: 0, checkRollupState: .pending,
            workflowRuns: [
                WorkflowRunItem(id: 1, name: "SDK Size", status: "queued", detailsURL: url(1), jobs: [
                    ActionJobItem(id: 11, name: "Metrics", status: "queued", createdAt: now.addingTimeInterval(-1680))
                ]),
                WorkflowRunItem(id: 2, name: "CodeQL", status: "completed", conclusion: "success", detailsURL: url(2), jobs: [
                    ActionJobItem(id: 21, name: "Analyze (actions)", status: "completed", conclusion: "success",
                                  startedAt: now.addingTimeInterval(-100), completedAt: now.addingTimeInterval(-68))
                ]),
                WorkflowRunItem(id: 3, name: "Smoke Checks", status: "in_progress", detailsURL: url(3), jobs: [
                    ActionJobItem(id: 31, name: "Guard", status: "completed", conclusion: "success",
                                  startedAt: now.addingTimeInterval(-143), completedAt: now.addingTimeInterval(-100)),
                    ActionJobItem(id: 32, name: "Test LLC (Debug)", status: "queued", createdAt: now.addingTimeInterval(-1620)),
                    ActionJobItem(id: 33, name: "Test UIKit (Debug)", status: "queued", createdAt: now.addingTimeInterval(-1620))
                ])
            ]
        )
        let failing = PullRequestItem(
            repository: repository, number: 1329, title: "[IOS-2091] Fix audio route change on reconnect",
            url: url(1329), isDraft: false, updatedAt: now.addingTimeInterval(-10800),
            reviewStatus: .changesRequested, unresolvedReviewThreadCount: 0, checkRollupState: .failing
        )
        let ready = PullRequestItem(
            repository: repository, number: 1318, title: "[IOS-2077] Document call quality metrics",
            url: url(1318), isDraft: false, updatedAt: now.addingTimeInterval(-86400),
            reviewStatus: .approved, unresolvedReviewThreadCount: 0, checkRollupState: .passing
        )
        return [pending, failing, ready]
    }

    /// Renders the whole window frame (title bar and traffic lights included) through the theme frame view.
    private func renderChrome<Content: View>(_ content: Content, name: String) async throws {
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: hosting.fittingSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))
        let frameView = try XCTUnwrap(window.contentView?.superview)
        frameView.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds))
        frameView.cacheDisplay(in: frameView.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }

    private func render<Content: View>(_ content: Content, size: CGSize, name: String) async throws {
        let hostingView = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .titled, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(300))
        hostingView.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
