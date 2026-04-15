import AppKit
import GHOrchestratorCore
import SwiftUI

@main
struct GHOrchestratorApp: App {
    @State private var controller = AppController()
    private let settingsWindowMenuVisibilityController = SettingsWindowMenuVisibilityController()

    var body: some Scene {
        MenuBarExtra(AppMetadata.menuBarTitle, systemImage: "arrow.triangle.branch") {
            MenuBarPlaceholderView(
                model: controller.dashboardModel,
                onMenuVisibilityChange: { isVisible in
                    controller.setMenuVisible(isVisible)
                }
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowView(
                model: controller.settingsModel,
                requestLogModel: controller.requestLogModel,
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
