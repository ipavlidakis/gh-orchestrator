import Foundation

enum SettingsWorkflowListState: Equatable {
    case idle
    case loading
    case loaded([String])
    case failed(String)

    var workflowNames: [String] {
        if case .loaded(let workflowNames) = self {
            return workflowNames
        }

        return []
    }
}
