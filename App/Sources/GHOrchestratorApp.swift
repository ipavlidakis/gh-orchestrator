import AppKit
import GHOrchestratorCore
import SwiftUI

@main
struct GHOrchestratorApp: App {
    @NSApplicationDelegateAdaptor(GitHubAuthAppDelegate.self) private var appDelegate
    @State private var controller = AppController()
    private let settingsWindowMenuVisibilityController = SettingsWindowMenuVisibilityController()

    var body: some Scene {
        MenuBarExtra(AppMetadata.menuBarTitle, systemImage: "arrow.triangle.branch") {
            MenuBarPlaceholderView(model: controller.dashboardModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowView(
                model: controller.settingsModel,
                menuVisibilityController: settingsWindowMenuVisibilityController
            )
        }
        .defaultSize(width: 780, height: 600)
        .windowResizability(.contentSize)
        .commands {
            SettingsWindowCommands(dashboardModel: controller.dashboardModel)
        }
    }
}
