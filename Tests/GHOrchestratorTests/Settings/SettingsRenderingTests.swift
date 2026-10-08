import AppKit
import GHOrchestratorCore
import SwiftUI
import Vision
import XCTest
@testable import GHOrchestrator

@MainActor
final class SettingsRenderingTests: XCTestCase {
    func testSettingsCardClipsChildBackgroundAtRoundedCorners() async throws {
        let view = Color.green.frame(width: 200, height: 60)
            .settingsCardSurface().padding(20).background(.white)
            .environment(\.settingsGlassDisabled, true)
        _ = try await render(view, size: CGSize(width: 240, height: 100), scheme: .light, name: "card-clipping")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("gh-settings-card-clipping-light.png")
        let image = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: output)))
        let center = try XCTUnwrap(image.colorAt(x: image.pixelsWide / 2, y: image.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        let corner = try XCTUnwrap(image.colorAt(x: image.pixelsWide * 21 / 240, y: image.pixelsHigh * 21 / 100)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(center.greenComponent - center.redComponent, 0.3, "The child background must remain visible inside the card")
        XCTAssertLessThan(abs(corner.greenComponent - corner.redComponent), 0.05, "The child tint must not escape the rounded corner")
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let model = SettingsModel(store: SettingsStore(storageURL: storageURL), authenticationState: .authenticated(username: "example"), notificationAuthorizationStatus: .authorized, repositoryListService: RenderingRepositoryListing())
        let notifications = ScrollView {
            VStack(alignment: .leading, spacing: 20) { NotificationSettingsPane(model: model) }.padding(28)
        }
        for scheme in [ColorScheme.light, .dark] {
            let rendered = try await render(notifications, size: CGSize(width: 624, height: 420), scheme: scheme, name: "notifications-glass", foreground: true)
            XCTAssertTrue(rendered.text.contains("notifications allowed"))
        }
    }

    func testNestedFormFieldsDoNotShowDuplicateLabels() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let model = SettingsModel(store: store)
        for scheme in [ColorScheme.light, .dark] {
            let view = Form {
                NotificationDebugPreviewGroup(model: model, preview: model.notificationDebugPreview)
            }
            .formStyle(.grouped)
            let result = try await render(view, size: CGSize(width: 570, height: 900), scheme: scheme, name: "preview")
            let visibleText = result.text
            XCTAssertTrue(visibleText.contains("pull request"), "The actual preview form must be rendered")
            for duplicate in ["pull request title", "octocat"] {
                XCTAssertFalse(visibleText.contains(duplicate), "Internal field label must be visually hidden: \(duplicate)")
            }
            let previewTitle = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased().contains("ipavlidakis/gh-orchestrator") == true })
            let sendLabel = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased() == "send preview" })
            XCTAssertEqual(previewTitle.boundingBox.minX, sendLabel.boundingBox.minX, accuracy: 0.025, "Preview content must align with the section's leading text, rather than sitting in the trailing value column")
        }
    }

    func testPollingUnitAndLongInsightsSelectionsRemainReadable() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        let repository = ObservedRepository(owner: "GetStream", name: "stream-video-swift")
        store.settings.observedRepositories = [repository]
        store.settings.actionsInsightsSelection = ActionsInsightsSelection(repositoryID: repository.id, workflowID: 1, workflowName: "CodeQL")
        let model = SettingsModel(store: store, authenticationState: .authenticated(username: "example"), repositoryListService: RenderingRepositoryListing())
        model.workflowListStatesByRepositoryID[repository.id] = .loaded(["CodeQL"])
        model.workflowItemsByRepositoryID[repository.id] = [ActionsWorkflowItem(id: 1, name: "CodeQL", path: ".github/workflows/codeql.yml", state: "active")]
        let jobListKey = "\(RepositoryNotificationSettings.normalizedRepositoryID(repository.id))::\(RepositoryNotificationSettings.normalizedWorkflowName("CodeQL"))"
        model.workflowJobListStatesByKey[jobListKey] = .loaded(["Analyze (swift)"])
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        let general = SettingsWindowView(model: model, softwareUpdateModel: updates, requestLogModel: GitHubRequestLogModel(), menuVisibilityController: SettingsWindowMenuVisibilityController(mainMenuProvider: { nil }), onSettingsWindowVisibilityChange: { _ in })
        for scheme in [ColorScheme.light, .dark] {
            let generalText = try await render(general.environment(\.settingsGlassDisabled, true), size: CGSize(width: 820, height: 1000), scheme: scheme, name: "general", foreground: true).text
            XCTAssertTrue(generalText.contains("refresh every"))
            XCTAssertTrue(generalText.contains("pull request order"))
            XCTAssertEqual(generalText.components(separatedBy: "seconds").count - 1, 1, "Polling units must appear once, without duplicate field/stepper labels")
            let insights = ScrollView { VStack(alignment: .leading, spacing: 20) { ActionsInsightsSettingsPane(model: model) }.padding(28) }
            let result = try await render(insights, size: CGSize(width: 570, height: 600), scheme: scheme, name: "insights", foreground: true)
            let insightsText = result.text
            XCTAssertTrue(insightsText.contains("getstream/stream-video-swift"), "The selected repository must fit without clipping")
            XCTAssertTrue(insightsText.contains("codeql"), "The selected workflow must remain visible")
            let selectedWorkflow = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased() == "codeql" })
            let selectedPeriod = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased().hasPrefix("last month") == true && $0.topCandidates(1).first!.string.count < 16 })
            XCTAssertEqual(selectedWorkflow.boundingBox.maxX, selectedPeriod.boundingBox.maxX, accuracy: 0.06, "Picker values must align at the trailing edge regardless of title length")
        }
    }

    func testConfiguredRepositoriesRemainVisibleWithoutSearching() async throws {
        let storageURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storageURL) }
        let store = SettingsStore(storageURL: storageURL)
        store.settings.observedRepositories = [ObservedRepository(owner: "orbit", name: "native-app"), ObservedRepository(owner: "orbit", name: "web-client")]
        let model = SettingsModel(store: store, authenticationState: .authenticated(username: "example"), notificationAuthorizationStatus: .authorized, repositoryListService: RenderingRepositoryListing())
        for scheme in [ColorScheme.light, .dark] {
            for (name, pane) in [("configured-notifications", AnyView(NotificationSettingsPane(model: model))), ("configured-insights", AnyView(ActionsInsightsSettingsPane(model: model)))] {
                let page = ScrollView { VStack(alignment: .leading, spacing: 20) { pane }.padding(28) }
                let window = NavigationSplitView {
                    List {
                        Label("Insights", systemImage: "chart.xyaxis.line")
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    .navigationSplitViewColumnWidth(196)
                    .toolbar(removing: .sidebarToggle)
                } detail: {
                    page
                }
                .toolbar(removing: .title)
                .toolbar {
                    if #available(macOS 26, *) {
                        ToolbarSpacer(.flexible)
                    }
                }
                let result = try await render(window, size: CGSize(width: 820, height: 840), scheme: scheme, name: name, foreground: true)
                XCTAssertTrue(result.text.contains("search repositories"))
                let search = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased().contains("search repositories") == true })
                XCTAssertGreaterThan(search.boundingBox.minX, 0.25, "Repository search belongs above the detail column in the trailing toolbar")
                XCTAssertTrue(result.text.contains("orbit/native-app"))
                XCTAssertTrue(result.text.contains("orbit/web-client"))
                XCTAssertFalse(result.text.contains("add repositories before"))
            }
        }
    }

    private func render<Content: View>(_ content: Content, size: CGSize, scheme: ColorScheme, name: String, foreground: Bool = false) async throws -> (text: String, observations: [VNRecognizedTextObservation]) {
        let hostingView = NSHostingView(rootView: content.frame(width: size.width, height: size.height).environment(\.colorScheme, scheme))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .titled, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(100))
        hostingView.layoutSubtreeIfNeeded()
        window.display()
        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("gh-settings-\(name)-\(scheme).png")
        if foreground {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            try await Task.sleep(for: .milliseconds(300))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), output.path]
            try capture.run(); capture.waitUntilExit()
            XCTAssertEqual(capture.terminationStatus, 0)
        } else {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        }
        print("Settings rendering evidence: \(output.path)")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(url: output).perform([request])
        let observations = request.results ?? []
        return (observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased(), observations)
    }
}

struct RenderingRepositoryListing: RepositoryListing {
    func listRepositories() async throws -> [ObservedRepository] {
        [ObservedRepository(owner: "GetStream", name: "stream-video-swift"), ObservedRepository(owner: "orbit", name: "native-app"), ObservedRepository(owner: "orbit", name: "web-client")]
    }
}
