import AppKit
import GHOrchestratorCore
import SwiftUI

@main
struct GHOrchestratorApp: App {
    @State private var controller = AppController()

    var body: some Scene {
        MenuBarExtra(AppMetadata.menuBarTitle, systemImage: "arrow.triangle.branch") {
            MenuBarPlaceholderView(model: controller.dashboardModel)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsWindowView(model: controller.settingsModel)
        }
        .defaultSize(width: 780, height: 600)
        .windowResizability(.contentSize)
    }
}
