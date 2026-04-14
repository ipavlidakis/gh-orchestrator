import AppKit
import SwiftUI

@MainActor
struct SettingsWindowCommandHandler {
    let showAboutPanelAction: () -> Void
    let refreshAction: () -> Void
    let openSettingsAction: () -> Void
    let openHelpAction: () -> Void
    let quitAction: () -> Void

    func showAboutPanel() {
        showAboutPanelAction()
    }

    func refresh() {
        refreshAction()
    }

    func openSettings() {
        openSettingsAction()
    }

    func openHelp() {
        openHelpAction()
    }

    func quit() {
        quitAction()
    }
}

extension SettingsWindowCommandHandler {
    static func live(
        dashboardModel: MenuBarDashboardModel,
        openSettings: @escaping @MainActor () -> Void,
        application: NSApplication = .shared,
        workspace: NSWorkspace = .shared
    ) -> Self {
        Self(
            showAboutPanelAction: {
                application.activate(ignoringOtherApps: true)
                application.orderFrontStandardAboutPanel(nil)
            },
            refreshAction: {
                dashboardModel.refresh()
            },
            openSettingsAction: {
                application.activate(ignoringOtherApps: true)
                openSettings()

                Task { @MainActor in
                    application.activate(ignoringOtherApps: true)
                }
            },
            openHelpAction: {
                workspace.open(AppMetadata.helpURL)
            },
            quitAction: {
                application.terminate(nil)
            }
        )
    }
}

struct SettingsWindowCommands: Commands {
    let dashboardModel: MenuBarDashboardModel

    @Environment(\.openSettings) private var openSettings

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppMetadata.menuBarTitle)") {
                commandHandler.showAboutPanel()
            }

            Button("Refresh") {
                commandHandler.refresh()
            }
            .keyboardShortcut("r")
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                commandHandler.openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .appTermination) {
            Button("Quit \(AppMetadata.menuBarTitle)") {
                commandHandler.quit()
            }
            .keyboardShortcut("q")
        }

        CommandGroup(replacing: .help) {
            Button("\(AppMetadata.menuBarTitle) Help") {
                commandHandler.openHelp()
            }
        }
    }

    private var commandHandler: SettingsWindowCommandHandler {
        SettingsWindowCommandHandler.live(
            dashboardModel: dashboardModel,
            openSettings: openSettings.callAsFunction
        )
    }
}
