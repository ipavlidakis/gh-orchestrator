import AppKit
import GHOrchestratorCore
import SwiftUI
import Vision
import XCTest
@testable import GHOrchestrator

@MainActor
final class DashboardRenderingTests: XCTestCase {
    func testSkippedJobRendersWithoutFailureColorInBothAppearances() async throws {
        for scheme in [ColorScheme.light, .dark] {
            let skipped = try await renderDashboard(conclusion: "skipped", scheme: scheme)
            let failed = try await renderDashboard(conclusion: "failure", scheme: scheme)
            XCTAssertEqual(redPixelCount(in: skipped), 0, "Skipped jobs must be neutral in \(scheme) mode")
            XCTAssertGreaterThan(redPixelCount(in: failed), 10, "Failed jobs must retain their failure icon")
            XCTAssertTrue(lastRenderedAccessibilityLabels.contains("Sort"), "The sorting control must be present in \(scheme) mode")
        }
    }

    private var lastRenderedAccessibilityLabels: Set<String> = []

    private func collectAccessibilityLabels(from element: Any, into labels: inout Set<String>, depth: Int = 0) {
        guard depth < 40 else { return }
        if let object = element as? NSAccessibilityProtocol {
            if let label = object.accessibilityLabel(), !label.isEmpty { labels.insert(label) }
            for child in (object.accessibilityChildren() ?? []) {
                collectAccessibilityLabels(from: child, into: &labels, depth: depth + 1)
            }
        }
    }

    private func renderDashboard(conclusion: String, scheme: ColorScheme) async throws -> NSBitmapImageRep {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = SettingsStore(storageURL: storageURL)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let repository = ObservedRepository(owner: "example", name: "repo")
        store.settings.observedRepositories = [repository]
        let model = MenuBarDashboardModel(settingsStore: store)
        model.authenticationState = .authenticated(username: "example")
        let url = URL(string: "https://github.com/example/repo/pull/1")!
        let pullRequest = PullRequestItem(
            repository: repository,
            number: 1,
            title: "Improve dashboard readability",
            url: url,
            isDraft: false,
            updatedAt: .now,
            reviewStatus: .approved,
            unresolvedReviewThreadCount: 0,
            checkRollupState: .passing,
            workflowRuns: [WorkflowRunItem(
                id: 1,
                name: "CI",
                status: "completed",
                jobs: [ActionJobItem(id: 1, name: "CI / Optional job", status: "completed", conclusion: conclusion, detailsURL: url)]
            )]
        )
        model.state = .loaded([RepositorySection(repository: repository, pullRequests: [pullRequest])])
        model.expandedChecksPullRequestIDs = [pullRequest.id]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        let view = MenuBarPlaceholderView(
            model: model,
            softwareUpdateModel: updates,
            openSettingsAction: {},
            openURLAction: { _ in },
            onMenuVisibilityChange: { _ in }
        )
        .frame(width: 440, height: 620, alignment: .topLeading)
        .environment(\.colorScheme, scheme)
        .background(Color(nsColor: .windowBackgroundColor))

        let hostingView = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 620), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        hostingView.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        var labels: Set<String> = []
        collectAccessibilityLabels(from: hostingView, into: &labels)
        lastRenderedAccessibilityLabels = labels
        if conclusion == "skipped" {
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("gh-orchestrator-dashboard-\(scheme).png")
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: outputURL)
            print("Dashboard visual evidence: \(outputURL.path)")
        }
        return bitmap
    }

    private func redPixelCount(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7 && color.greenComponent < 0.55 && color.blueComponent < 0.55 {
                    count += 1
                }
            }
        }
        return count
    }
}
