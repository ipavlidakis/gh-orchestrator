import Foundation
import GHOrchestratorCore
import Observation

@Observable
final class SettingsModel {
    private var isUpdatingPollingIntervalText = false

    let store: SettingsStore
    private let manualRefreshAction: (() -> Void)?
    private let signInAction: (() -> Void)?
    private let signOutAction: (() -> Void)?

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

    var authenticationState: GitHubAuthenticationState
    var hideDockIcon: Bool {
        didSet {
            syncHideDockIcon()
        }
    }

    init(
        store: SettingsStore = SettingsStore(),
        authenticationState: GitHubAuthenticationState = .signedOut,
        manualRefreshAction: (() -> Void)? = nil,
        signInAction: (() -> Void)? = nil,
        signOutAction: (() -> Void)? = nil
    ) {
        self.store = store
        self.authenticationState = authenticationState
        self.manualRefreshAction = manualRefreshAction
        self.signInAction = signInAction
        self.signOutAction = signOutAction
        self.repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        self.repositoryValidationMessages = []
        self.pollingIntervalText = String(store.settings.pollingIntervalSeconds)
        self.pollingIntervalValidationMessage = nil
        self.hideDockIcon = store.settings.hideDockIcon
    }

    var settings: AppSettings {
        store.settings
    }

    var authenticationDescription: String {
        switch authenticationState {
        case .notConfigured:
            return "OAuth is not configured for this build"
        case .signedOut:
            return "Not signed in"
        case .authorizing:
            return "Waiting for GitHub sign-in to finish"
        case .authenticated(let username):
            return "Signed in as \(username)"
        case .authFailure(let message):
            return "Authentication failed: \(message)"
        }
    }

    var hasManualRefreshAction: Bool {
        manualRefreshAction != nil
    }

    var canStartSignIn: Bool {
        signInAction != nil && authenticationState != .authorizing && authenticationState != .notConfigured
    }

    var canSignOut: Bool {
        if case .authenticated = authenticationState {
            return signOutAction != nil
        }

        return false
    }

    var observedRepositories: [ObservedRepository] {
        store.settings.observedRepositories
    }

    var pollingIntervalStepperValue: Int {
        Int(pollingIntervalText) ?? store.settings.pollingIntervalSeconds
    }

    func reloadFromStore() {
        repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        repositoryValidationMessages = []
        pollingIntervalText = String(store.settings.pollingIntervalSeconds)
        pollingIntervalValidationMessage = nil
        hideDockIcon = store.settings.hideDockIcon
    }

    func requestManualRefresh() {
        manualRefreshAction?()
    }

    func requestSignIn() {
        signInAction?()
    }

    func requestSignOut() {
        signOutAction?()
    }

    @discardableResult
    func addObservedRepository(from rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            repositoryValidationMessages = ["Enter a repository in owner/name format."]
            return false
        }

        guard let repository = ObservedRepository(rawValue: trimmed) else {
            repositoryValidationMessages = ["Invalid repository entry: \(trimmed)"]
            return false
        }

        if store.settings.observedRepositories.contains(where: { $0.normalizedLookupKey == repository.normalizedLookupKey }) {
            repositoryValidationMessages = ["Repository already added: \(repository.fullName)"]
            return false
        }

        repositoryValidationMessages = []
        store.settings.observedRepositories.append(repository)
        repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        return true
    }

    func removeObservedRepositories(withIDs ids: Set<String>) {
        guard !ids.isEmpty else {
            return
        }

        let updatedRepositories = store.settings.observedRepositories.filter { repository in
            !ids.contains(repository.id)
        }

        guard updatedRepositories != store.settings.observedRepositories else {
            return
        }

        repositoryValidationMessages = []
        store.settings.observedRepositories = updatedRepositories
        repositoryText = Self.repositoryText(from: updatedRepositories)
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

    private func syncHideDockIcon() {
        if store.settings.hideDockIcon != hideDockIcon {
            store.settings.hideDockIcon = hideDockIcon
        }
    }

    private static func repositoryText(from repositories: [ObservedRepository]) -> String {
        repositories.map(\.fullName).joined(separator: "\n")
    }
}
