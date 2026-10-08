import AppKit
import GHOrchestratorCore
import SwiftUI
import XCTest
@testable import GHOrchestrator

/// Renders the popover and Settings panes with design fixtures to PNGs so the UI can be compared with the design canvas.
@MainActor
final class DesignParityRenderingTests: XCTestCase {
    private let outputDirectory = URL(fileURLWithPath: "/tmp/gho-shots", isDirectory: true)

    func testRenderGlobalCategoriesAndDiscoveredRepositoryFilter() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let repository = ObservedRepository(owner: "orbit-labs", name: "nova-app")
        let other = ObservedRepository(owner: "another-team", name: "tooling")
        for scope in [PullRequestScope.mine, .reviewRequested] {
            let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: storageURL) }
            let store = SettingsStore(storageURL: storageURL)
            store.settings = AppSettings(dashboardPullRequestScope: scope)
            let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
            let model = MenuBarDashboardModel(settingsStore: store)
            model.authenticationState = .authenticated(username: "alex")
            model.state = .loaded([
                RepositorySection(repository: repository, pullRequests: fixturePullRequests(repository: repository)),
                RepositorySection(repository: other, pullRequests: [fixturePullRequests(repository: other)[0]])
            ])
            let view = MenuBarPlaceholderView(model: model, softwareUpdateModel: updates, openSettingsAction: {}, openURLAction: { _ in }, onMenuVisibilityChange: { _ in })
                .frame(width: 440, alignment: .topLeading)
            try await render(view, size: CGSize(width: 440, height: 620), name: "global-\(scope.rawValue)")
            model.setFocusedRepositoryID(repository.id)
            try await render(view.environment(\.colorScheme, .dark), size: CGSize(width: 440, height: 620), name: "global-\(scope.rawValue)-filtered-dark", appearance: .darkAqua)
        }
    }

    func testRenderPopoverAndSettingsForDesignReview() async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let repository = ObservedRepository(owner: "orbit-labs", name: "nova-app")
        store.settings.observedRepositories = [repository]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())

        let model = MenuBarDashboardModel(settingsStore: store)
        model.authenticationState = .authenticated(username: "alex")
        let pulls = fixturePullRequests(repository: repository)
        model.state = .loaded([RepositorySection(repository: repository, pullRequests: pulls)])
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
        .frame(width: 440, alignment: .topLeading)
        try await render(popover, size: CGSize(width: 440, height: 570), name: "dashboard-overview")
        let allStorageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: allStorageURL) }
        let allStore = SettingsStore(storageURL: allStorageURL)
        allStore.settings = AppSettings(observedRepositories: [repository], dashboardPullRequestScope: .reviewRequested)
        let allModel = MenuBarDashboardModel(settingsStore: allStore)
        allModel.authenticationState = .authenticated(username: "alex")
        allModel.state = .loaded([RepositorySection(repository: repository, pullRequests: pulls)])
        let allPopover = MenuBarPlaceholderView(
            model: allModel, softwareUpdateModel: updates, requestLogModel: log,
            openSettingsAction: {}, openURLAction: { _ in }, onMenuVisibilityChange: { _ in }
        )
        .frame(width: 440, alignment: .topLeading)
        try await render(allPopover, size: CGSize(width: 440, height: 570), name: "dashboard-header-focus", focusHeader: true)
        try await render(allPopover.environment(\.colorScheme, .dark), size: CGSize(width: 440, height: 570), name: "dashboard-header-focus-dark", appearance: .darkAqua, focusHeader: true)
        model.state = .loaded([RepositorySection(repository: repository, pullRequests: [pulls[0]])])
        model.expandedChecksPullRequestIDs = [pulls[0].id]
        try await render(popover, size: CGSize(width: 440, height: 475), name: "dashboard-pr-details")
        model.state = .loaded([RepositorySection(repository: repository, pullRequests: [pulls[1]])])
        model.expandedCommentPullRequestIDs = [pulls[1].id]
        try await render(popover, size: CGSize(width: 440, height: 620), name: "dashboard-comments")
        try await render(popover.environment(\.colorScheme, .dark), size: CGSize(width: 440, height: 620), name: "dashboard-comments-dark", appearance: .darkAqua)

        let workflow = ActionsWorkflowItem(id: 2, name: "CodeQL", path: ".github/workflows/codeql.yml", state: "active")
        store.settings.actionsInsightsSelection = ActionsInsightsSelection(repositoryID: repository.id, workflowID: workflow.id, workflowName: workflow.name, period: .last7Days)
        let settingsModel = SettingsModel(store: store, authenticationState: .authenticated(username: "alex"), notificationAuthorizationStatus: .authorized)
        settingsModel.setRepositoryNotificationsEnabled(true, repositoryID: repository.id)
        settingsModel.workflowListStatesByRepositoryID[repository.id] = .loaded([workflow.name])
        settingsModel.workflowItemsByRepositoryID[repository.id] = [workflow]
        let jobKey = "\(RepositoryNotificationSettings.normalizedRepositoryID(repository.id))::\(RepositoryNotificationSettings.normalizedWorkflowName(workflow.name))"
        settingsModel.workflowJobListStatesByKey[jobKey] = .loaded(["Analyze (swift)"])
        settingsModel.setNotificationTrigger(.pullRequestCreated, isEnabled: false, repositoryID: repository.id)
        settingsModel.setNotificationTrigger(.approval, isEnabled: false, repositoryID: repository.id)
        settingsModel.setWorkflowNameFilter(workflow.name, isSelected: true, repositoryID: repository.id)
        settingsModel.setWorkflowJobNameFilter("Analyze (swift)", isSelected: true, repositoryID: repository.id, workflowName: workflow.name)
        let now = Date()
        let points = (0..<7).map { day in
            ActionsInsightsDataPoint(date: now.addingTimeInterval(Double(day - 6) * 86400), successCount: 20 + day % 3, failureCount: 4 - day % 3, averageDurationSeconds: Double(240 + day * 15))
        }
        settingsModel.actionsInsightsState = .loaded(ActionsInsightsDashboard(
            dateInterval: DateInterval(start: points[0].date, end: now),
            summary: ActionsInsightsSummary(totalCount: 168, successCount: 146, failureCount: 22, averageDurationSeconds: 285),
            dataPoints: points
        ))
        let window = SettingsWindowView(
            model: settingsModel, softwareUpdateModel: updates, requestLogModel: log,
            menuVisibilityController: SettingsWindowMenuVisibilityController(mainMenuProvider: { nil }),
            onSettingsWindowVisibilityChange: { _ in }
        )
        try await render(window.environment(\.settingsGlassDisabled, true), size: CGSize(width: 820, height: 620), name: "settings-window")
        try await renderChrome(window.environment(\.settingsGlassDisabled, true), name: "settings-chrome")
        func page<V: View>(_ v: V) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { v }.padding(28).frame(width: 624, alignment: .leading)
            }
            .environment(\.settingsGlassDisabled, true)
        }
        try await render(page(GitHubSettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 420), name: "pane-github")
        try await render(page(RepositorySettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 420), name: "pane-repositories")
        try await render(page(NotificationSettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 680), name: "settings-notifications")
        try await render(page(ActionsInsightsSettingsPane(model: settingsModel)), size: CGSize(width: 624, height: 1100), name: "settings-insights")
        try await render(page(GitHubRequestUsagePane(requestLogModel: log)), size: CGSize(width: 624, height: 420), name: "pane-requests")
    }

    func testPopoverReportsHeightThatFitsItsContent() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let repository = ObservedRepository(owner: "orbit-labs", name: "nova-app")
        store.settings.observedRepositories = [repository]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        let model = MenuBarDashboardModel(settingsStore: store)
        model.authenticationState = .authenticated(username: "alex")
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
            repository: repository, number: 42,
            title: "Add a smoother onboarding flow",
            url: url(42), isDraft: false, updatedAt: now.addingTimeInterval(-660),
            reviewStatus: .reviewRequired, mergeable: .unknown, unresolvedReviewThreadCount: 0, checkRollupState: .pending,
            workflowRuns: [
                WorkflowRunItem(id: 1, name: "App Build", status: "queued", detailsURL: url(1), jobs: [
                    ActionJobItem(id: 11, name: "Release build", status: "queued", createdAt: now.addingTimeInterval(-1680))
                ]),
                WorkflowRunItem(id: 2, name: "CodeQL", status: "completed", conclusion: "success", detailsURL: url(2), jobs: [
                    ActionJobItem(id: 21, name: "Analyze (swift)", status: "completed", conclusion: "success",
                                  startedAt: now.addingTimeInterval(-100), completedAt: now.addingTimeInterval(-68))
                ]),
                WorkflowRunItem(id: 3, name: "Smoke Checks", status: "in_progress", detailsURL: url(3), jobs: [
                    ActionJobItem(id: 31, name: "Lint", status: "completed", conclusion: "success",
                                  startedAt: now.addingTimeInterval(-143), completedAt: now.addingTimeInterval(-100)),
                    ActionJobItem(id: 32, name: "Unit tests", status: "queued", createdAt: now.addingTimeInterval(-1620)),
                    ActionJobItem(id: 33, name: "UI tests", status: "queued", createdAt: now.addingTimeInterval(-1620))
                ])
            ]
        )
        let failing = PullRequestItem(
            repository: repository, number: 38, title: "Keep favorites in sync across devices",
            url: url(38), isDraft: false, updatedAt: now.addingTimeInterval(-10800),
            reviewStatus: .changesRequested, mergeable: .conflicting, unresolvedReviewThreadCount: 2,
            unresolvedReviewComments: [UnresolvedReviewCommentItem(
                url: url(38), authorLogin: "octocat",
                bodyText: "Could we cover an offline edit before the next sync?",
                filePath: "Sources/Sync/FavoritesStore.swift",
                authorAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/583231?s=56&v=4"),
                createdAt: now.addingTimeInterval(-3600)
            ), UnresolvedReviewCommentItem(
                url: URL(string: "https://github.com/x/y/pull/38#discussion_r2")!,
                authorLogin: "reviewer-with-a-long-github-username",
                bodyText: "Please preserve the pending local changes while reconnecting.\n\nAn offline edit should still appear after the next sync, even when the remote version changed in the meantime. This final sentence should remain visible without truncation.",
                filePath: "Sources/Sync/Offline/Recovery/FavoritesReconnectionCoordinator.swift",
                createdAt: now.addingTimeInterval(-7200)
            )], checkRollupState: .failing
        )
        let ready = PullRequestItem(
            repository: repository, number: 35, title: "Polish the empty states",
            url: url(35), isDraft: false, updatedAt: now.addingTimeInterval(-86400),
            reviewStatus: .approved, mergeable: .mergeable, unresolvedReviewThreadCount: 0, checkRollupState: .passing
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

    private func render<Content: View>(_ content: Content, size: CGSize, name: String, appearance: NSAppearance.Name = .aqua, focusHeader: Bool = false) async throws {
        let hostingView = NSHostingView(rootView: content.frame(width: size.width, height: size.height, alignment: .topLeading).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .titled, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.contentView = hostingView
        let previousActivationPolicy = NSApp.activationPolicy()
        if focusHeader {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
        defer {
            window.orderOut(nil)
            if focusHeader { NSApp.setActivationPolicy(previousActivationPolicy) }
        }
        try await Task.sleep(for: .milliseconds(300))
        hostingView.layoutSubtreeIfNeeded()
        if focusHeader {
            window.makeFirstResponder(nil)
            window.selectNextKeyView(nil)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(window.isKeyWindow)
            XCTAssertNotNil(window.firstResponder as? NSView)
        }
        window.display()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: outputDirectory.appendingPathComponent("\(name).png"))
    }
}
