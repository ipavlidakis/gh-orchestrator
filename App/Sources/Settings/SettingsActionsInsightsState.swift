import GHOrchestratorCore

enum SettingsActionsInsightsState: Equatable {
    case idle
    case loading
    case loaded(ActionsInsightsDashboard)
    case failed(String)

    var dashboard: ActionsInsightsDashboard? {
        guard case .loaded(let dashboard) = self else {
            return nil
        }

        return dashboard
    }
}
