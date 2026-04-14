import Observation

@MainActor
@Observable
final class AppController {
    let settingsStore: SettingsStore
    let dashboardModel: MenuBarDashboardModel
    let settingsModel: SettingsModel

    init(
        settingsStore: SettingsStore = SettingsStore(),
        dataSource: any DashboardDataSource = LiveDashboardDataSource(),
        sleeper: any DashboardSleepProviding = TaskSleepProvider()
    ) {
        self.settingsStore = settingsStore
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
}
