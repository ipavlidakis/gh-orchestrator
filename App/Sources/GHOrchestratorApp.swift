import AppKit
import GHOrchestratorCore
import SwiftUI

@main
struct GHOrchestratorApp: App {
    @State private var controller: AppController
    private let settingsWindowMenuVisibilityController: SettingsWindowMenuVisibilityController
    private let applicationIconController: ApplicationIconController

    init() {
        let applicationIconController = ApplicationIconController()

        _controller = State(initialValue: AppController())
        self.settingsWindowMenuVisibilityController = SettingsWindowMenuVisibilityController()
        self.applicationIconController = applicationIconController
        applicationIconController.applyCurrentSystemAppearance()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPlaceholderView(
                model: controller.dashboardModel,
                softwareUpdateModel: controller.softwareUpdateModel,
                onMenuVisibilityChange: { isVisible in
                    controller.setMenuVisible(isVisible)
                }
            )
        } label: {
            MenuBarStatusIconLabel(applicationIconController: applicationIconController)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowView(
                model: controller.settingsModel,
                softwareUpdateModel: controller.softwareUpdateModel,
                requestLogModel: controller.requestLogModel,
                menuVisibilityController: settingsWindowMenuVisibilityController,
                onSettingsWindowVisibilityChange: { isVisible in
                    controller.setSettingsWindowVisible(isVisible)
                }
            )
        }
        .defaultSize(width: 780, height: 600)
        .windowResizability(.contentSize)
        .commands {
            SettingsWindowCommands(
                dashboardModel: controller.dashboardModel,
                softwareUpdateModel: controller.softwareUpdateModel
            )
        }
    }
}
