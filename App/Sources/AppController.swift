import Observation

@MainActor
@Observable
final class AppController {
    let settingsStore: SettingsStore
    let dashboardModel: MenuBarDashboardModel
    let settingsModel: SettingsModel
    private let dockIconVisibilityController: any DockIconVisibilityControlling

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: any DashboardDataSource = LiveDashboardDataSource(),
        sleeper: any DashboardSleepProviding = TaskSleepProvider(),
        dockIconVisibilityController: any DockIconVisibilityControlling = DockIconVisibilityController()
    ) {
        self.settingsStore = settingsStore
        self.dockIconVisibilityController = dockIconVisibilityController
        self.dashboardModel = MenuBarDashboardModel(
            settingsStore: settingsStore,
            dataSource: dataSource,
            sleeper: sleeper
        )
        self.settingsModel = SettingsModel(
            store: settingsStore,
            cliHealth: dashboardModel.cliHealth,
            manualRefreshAction: { [dashboardModel] in
                dashboardModel.refresh()
            }
        )

        observeDashboardHealth()
        observeDockIconPreference()
        Task { @MainActor [weak self] in
            self?.applyDockIconPreference()
        }
    }

    private func observeDashboardHealth() {
        withObservationTracking {
            _ = dashboardModel.cliHealth
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.settingsModel.cliHealth = self.dashboardModel.cliHealth
                self.observeDashboardHealth()
            }
        }
    }

    private func observeDockIconPreference() {
        withObservationTracking {
            _ = settingsStore.settings.hideDockIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.applyDockIconPreference()
                self.observeDockIconPreference()
            }
        }
    }

    private func applyDockIconPreference() {
        dockIconVisibilityController.apply(hideDockIcon: settingsStore.settings.hideDockIcon)
    }
}
