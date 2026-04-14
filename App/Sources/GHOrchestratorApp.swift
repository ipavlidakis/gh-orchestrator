import AppKit
import GHOrchestratorCore
import SwiftUI

@main
struct GHOrchestratorApp: App {
    var body: some Scene {
        MenuBarExtra(AppMetadata.menuBarTitle, systemImage: "arrow.triangle.branch") {
            MenuBarPlaceholderView()
        }

        Settings {
            SettingsPlaceholderView()
        }
    }
}
