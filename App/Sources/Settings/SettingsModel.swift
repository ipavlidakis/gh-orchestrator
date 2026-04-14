import Foundation
import Observation
import GHOrchestratorCore

@Observable
final class SettingsModel {
    private var isUpdatingPollingIntervalText = false

    let store: SettingsStore
    private let manualRefreshAction: (() -> Void)?

    var repositoryText: String {
        didSet {
            syncRepositories()
        }
    }

    private(set) var repositoryValidationMessages: [String]

    var pollingIntervalText: String {
        didSet {
            syncPollingInterval()
        }
    }

    private(set) var pollingIntervalValidationMessage: String?

    var cliHealth: GitHubCLIHealth

    init(
        store: SettingsStore = SettingsStore(),
        cliHealth: GitHubCLIHealth = .missing,
        manualRefreshAction: (() -> Void)? = nil
    ) {
        self.store = store
        self.cliHealth = cliHealth
        self.manualRefreshAction = manualRefreshAction
        self.repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        self.repositoryValidationMessages = []
        self.pollingIntervalText = String(store.settings.pollingIntervalSeconds)
        self.pollingIntervalValidationMessage = nil
    }

    var settings: AppSettings {
        store.settings
    }

    var cliHealthDescription: String {
        switch cliHealth {
        case .missing:
            return "gh CLI is not installed"
        case .loggedOut:
            return "gh CLI is installed, but not logged in"
        case .authenticated(let username):
            return "Signed in as \(username)"
        case .commandFailure(let message):
            return "gh CLI health check failed: \(message)"
        }
    }

    var hasManualRefreshAction: Bool {
        manualRefreshAction != nil
    }

    var pollingIntervalStepperValue: Int {
        Int(pollingIntervalText) ?? store.settings.pollingIntervalSeconds
    }

    func reloadFromStore() {
        repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        repositoryValidationMessages = []
        pollingIntervalText = String(store.settings.pollingIntervalSeconds)
        pollingIntervalValidationMessage = nil
    }

    func requestManualRefresh() {
        manualRefreshAction?()
    }

    private func syncRepositories() {
        let parseResult = ObservedRepository.parseList(from: repositoryText)

        repositoryValidationMessages = parseResult.invalidEntries.map {
            "Invalid repository entry: \($0)"
        }

        if store.settings.observedRepositories != parseResult.repositories {
            store.settings.observedRepositories = parseResult.repositories
        }
    }

    private func syncPollingInterval() {
        guard !isUpdatingPollingIntervalText else {
            return
        }

        let trimmed = pollingIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else {
            pollingIntervalValidationMessage = "Polling interval must be a whole number."
            return
        }

        let clamped = AppSettings.clampPollingInterval(parsed)
        pollingIntervalValidationMessage = parsed == clamped ? nil : "Polling interval must be between 15 and 900 seconds."

        if pollingIntervalText != String(clamped) {
            isUpdatingPollingIntervalText = true
            pollingIntervalText = String(clamped)
            isUpdatingPollingIntervalText = false
        }

        if store.settings.pollingIntervalSeconds != clamped {
            store.settings.pollingIntervalSeconds = clamped
        }
    }

    private static func repositoryText(from repositories: [ObservedRepository]) -> String {
        repositories.map(\.fullName).joined(separator: "\n")
    }
}
