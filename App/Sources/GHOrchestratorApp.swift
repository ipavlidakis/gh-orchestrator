import AppKit
import GHOrchestratorCore
import SwiftUI

@main
struct GHOrchestratorApp: App {
    @State private var controller: AppController
    private let settingsWindowMenuVisibilityController: SettingsWindowMenuVisibilityController
    private let menuBarPopoverPresenter: MenuBarPopoverPresenter

    init() {
        let applicationIconController = ApplicationIconController()
        let controller = AppController(applicationIconController: applicationIconController)

        _controller = State(initialValue: controller)
        self.settingsWindowMenuVisibilityController = SettingsWindowMenuVisibilityController()
        self.menuBarPopoverPresenter = MenuBarPopoverPresenter(
            controller: controller,
            softwareUpdateModel: controller.softwareUpdateModel,
            applicationIconController: applicationIconController
        )
    }

    var body: some Scene {
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
