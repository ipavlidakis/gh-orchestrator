import Foundation
import GHOrchestratorCore
import Observation

enum SoftwareUpdateState: Equatable {
    case idle
    case checking
    case upToDate(version: String)
    case updateAvailable(SoftwareUpdate)
    case installing(SoftwareUpdate)
    case failed(String)
}

@MainActor
@Observable
final class SoftwareUpdateModel {
    static let automaticCheckInterval: Duration = .seconds(24 * 60 * 60)

    private let store: SettingsStore
    private let checker: any SoftwareUpdateChecking
    private let installer: any SoftwareUpdateInstalling
    private let sleeper: any DashboardSleepProviding
    private let currentVersionProvider: () -> String

    @ObservationIgnored
    private var automaticCheckTask: Task<Void, Never>?

    @ObservationIgnored
    private var checkTask: Task<Void, Never>?

    @ObservationIgnored
    private var installTask: Task<Void, Never>?

    var state: SoftwareUpdateState = .idle
    var lastCheckedAt: Date?

    var automaticallyCheckForUpdates: Bool {
        didSet {
            syncAutomaticallyCheckForUpdates()
        }
    }

    init(
        store: SettingsStore,
        checker: any SoftwareUpdateChecking,
        installer: any SoftwareUpdateInstalling,
        sleeper: any DashboardSleepProviding = TaskSleepProvider(),
        currentVersionProvider: @escaping () -> String = { AppMetadata.currentVersion }
    ) {
        self.store = store
        self.checker = checker
        self.installer = installer
        self.sleeper = sleeper
        self.currentVersionProvider = currentVersionProvider
        self.automaticallyCheckForUpdates = store.settings.automaticallyCheckForUpdates
    }

    deinit {
        automaticCheckTask?.cancel()
        checkTask?.cancel()
        installTask?.cancel()
    }

    var currentVersion: String {
        currentVersionProvider()
    }

    var canCheckForUpdates: Bool {
        switch state {
        case .checking, .installing:
            return false
        case .idle, .upToDate, .updateAvailable, .failed:
            return true
        }
    }

    var canInstallUpdate: Bool {
        guard installTask == nil else {
            return false
        }

        if case .updateAvailable = state {
            return true
        }

        return false
    }

    var availableUpdate: SoftwareUpdate? {
        if case .updateAvailable(let update) = state {
            return update
        }

        if case .installing(let update) = state {
            return update
        }

        return nil
    }

    var statusDescription: String {
        switch state {
        case .idle:
            return "Current version \(currentVersion)"
        case .checking:
            return "Checking for updates"
        case .upToDate(let version):
            return "Version \(version) is current"
        case .updateAvailable(let update):
            return "Version \(update.version) is available"
        case .installing(let update):
            return "Installing version \(update.version)"
        case .failed(let message):
            return "Update check failed: \(message)"
        }
    }

    var checkButtonTitle: String {
        if case .checking = state {
            return "Checking..."
        }

        return "Check Now"
    }

    var installButtonTitle: String {
        if case .installing = state {
            return "Installing..."
        }

        return "Install Update"
    }

    func startAutomaticChecks() {
        guard automaticCheckTask == nil else {
            return
        }

        automaticCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                if self.automaticallyCheckForUpdates {
                    await self.checkForUpdatesNow()
                }

                do {
                    try await self.sleeper.sleep(for: Self.automaticCheckInterval)
                } catch {
                    return
                }
            }
        }
    }

    func stopAutomaticChecks() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    func requestCheckForUpdates() {
        guard canCheckForUpdates, checkTask == nil else {
            return
        }

        checkTask = Task { @MainActor [weak self] in
            await self?.checkForUpdatesNow()
        }
    }

    func checkForUpdatesNow() async {
        guard canCheckForUpdates else {
            return
        }

        state = .checking

        do {
            let result = try await checker.checkForUpdates(currentVersion: currentVersion)
            lastCheckedAt = Date()

            switch result {
            case .upToDate(let version):
                state = .upToDate(version: version)
            case .updateAvailable(let update):
                state = .updateAvailable(update)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }

        checkTask = nil
    }

    func requestInstallUpdate() {
        guard canInstallUpdate, installTask == nil else {
            return
        }

        installTask = Task { @MainActor [weak self] in
            await self?.installAvailableUpdateNow()
        }
    }

    func installAvailableUpdateNow() async {
        guard case .updateAvailable(let update) = state else {
            return
        }

        state = .installing(update)

        do {
            try await installer.install(update)
            state = .upToDate(version: update.version)
        } catch {
            state = .failed(error.localizedDescription)
        }

        installTask = nil
    }

    private func syncAutomaticallyCheckForUpdates() {
        guard store.settings.automaticallyCheckForUpdates != automaticallyCheckForUpdates else {
            return
        }

        store.settings.automaticallyCheckForUpdates = automaticallyCheckForUpdates
    }
}
