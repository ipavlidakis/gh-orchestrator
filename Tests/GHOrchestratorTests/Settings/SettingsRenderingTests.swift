import AppKit
import GHOrchestratorCore
import SwiftUI
import Vision
import XCTest
@testable import GHOrchestrator

@MainActor
final class SettingsRenderingTests: XCTestCase {
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
        let model = SettingsModel(store: store, authenticationState: .authenticated(username: "example"))
        model.workflowListStatesByRepositoryID[repository.id] = .loaded(["CodeQL"])
        model.workflowItemsByRepositoryID[repository.id] = [ActionsWorkflowItem(id: 1, name: "CodeQL", path: ".github/workflows/codeql.yml", state: "active")]
        let updates = SoftwareUpdateModel(store: store, checker: GitHubReleaseUpdateChecker(), installer: DMGSoftwareUpdateInstaller())
        let general = SettingsWindowView(model: model, softwareUpdateModel: updates, requestLogModel: GitHubRequestLogModel(), menuVisibilityController: SettingsWindowMenuVisibilityController(mainMenuProvider: { nil }), onSettingsWindowVisibilityChange: { _ in })
        for scheme in [ColorScheme.light, .dark] {
            let generalText = try await render(general, size: CGSize(width: 780, height: 1000), scheme: scheme, name: "general").text
            XCTAssertTrue(generalText.contains("polling interval"))
            XCTAssertTrue(generalText.contains("pull request order"))
            XCTAssertEqual(generalText.components(separatedBy: "seconds").count - 1, 1, "Polling units must appear once, without duplicate field/stepper labels")
            let insights = Form { ActionsInsightsSettingsPane(model: model) }.formStyle(.grouped)
            let result = try await render(insights, size: CGSize(width: 570, height: 600), scheme: scheme, name: "insights")
            let insightsText = result.text
            XCTAssertTrue(insightsText.contains("getstream/stream-video-swift"), "The selected repository must fit without clipping")
            XCTAssertTrue(insightsText.contains("codeql"), "The selected workflow must remain visible")
            let selectedRepository = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased().contains("getstream/stream-video-swift") == true })
            let selectedWorkflow = try XCTUnwrap(result.observations.first { $0.topCandidates(1).first?.string.lowercased() == "codeql" })
            XCTAssertEqual(selectedWorkflow.boundingBox.maxX, selectedRepository.boundingBox.maxX, accuracy: 0.025, "Picker values must align at the trailing edge regardless of title length")
        }
    }

    private func render<Content: View>(_ content: Content, size: CGSize, scheme: ColorScheme, name: String) async throws -> (text: String, observations: [VNRecognizedTextObservation]) {
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
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: output)
        print("Settings rendering evidence: \(output.path)")
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let observations = request.results ?? []
        return (observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased(), observations)
    }
}
