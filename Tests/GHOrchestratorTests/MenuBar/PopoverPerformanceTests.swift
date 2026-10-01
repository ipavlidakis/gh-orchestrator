import AppKit
import GHOrchestratorCore
import SwiftUI
import XCTest
@testable import GHOrchestrator

/// Times the collapse/expand path of a repository whose PRs carry many jobs.
@MainActor
final class PopoverPerformanceTests: XCTestCase {
    func testToggleRepositoryWithManyJobsStaysResponsive() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let repository = ObservedRepository(owner: "GetStream", name: "stream-video-swift")
        store.settings.observedRepositories = [repository]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        let model = MenuBarDashboardModel(settingsStore: store)
        model.authenticationState = .authenticated(username: "x")
        let now = Date()
        let pulls = (1...3).map { n in
            PullRequestItem(
                repository: repository, number: n, title: "PR \(n)", url: URL(string: "https://github.com/x/y/pull/\(n)")!,
                isDraft: false, createdAt: now, updatedAt: now, reviewStatus: .reviewRequired,
                unresolvedReviewThreadCount: 0, checkRollupState: .pending,
                workflowRuns: (1...3).map { r in
                    WorkflowRunItem(id: n * 100 + r, name: "Workflow \(r)", status: "completed", conclusion: "failure", jobs: (1...5).map { j in
                        ActionJobItem(id: n * 10_000 + r * 100 + j, name: "Job \(j)", status: "completed", conclusion: "success", createdAt: now, startedAt: now, completedAt: now,
                                      steps: (1...9).map { ActionStepItem(number: $0, name: "Step \($0)", status: "completed", conclusion: "success", startedAt: now, completedAt: now) })
                    })
                }
            )
        }
        model.state = .loaded([RepositorySection(repository: repository, pullRequests: pulls)])
        model.expandedChecksPullRequestIDs = [pulls[0].id]

        var heights: [CGFloat] = []
        let view = MenuBarPlaceholderView(
            model: model, softwareUpdateModel: updates, maximumHeight: 620,
            onPreferredHeightChange: { heights.append($0) },
            openSettingsAction: {}, openURLAction: { _ in }, onMenuVisibilityChange: { _ in }
        ).frame(width: 440, height: 620)
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 620), styleMask: .titled, backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(500))

        var toggleDurations: [Duration] = []
        for i in 0..<6 {
            let t = ContinuousClock.now
            model.toggleRepositoryCollapsed(repositoryID: repository.normalizedLookupKey)
            host.layoutSubtreeIfNeeded()
            window.display()
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            toggleDurations.append(ContinuousClock.now - t - .milliseconds(50))
        }
        let slowest = toggleDurations.max() ?? .zero
        XCTAssertLessThan(slowest, .milliseconds(250), "Collapsing or expanding a repository must stay interactive")
    }
}
