import Foundation
import Observation
import GHOrchestratorCore

@Observable
final class SettingsStore {
    private static let directoryName = "GHOrchestrator"
    private static let fileName = "settings.json"

    @ObservationIgnored
    private let fileManager: FileManager

    @ObservationIgnored
    private let storageURL: URL

    @ObservationIgnored
    var onSettingsChange: ((AppSettings, AppSettings) -> Void)?

    @ObservationIgnored
    private var settingsChangeHandlers: [UUID: (AppSettings, AppSettings) -> Void] = [:]

    var settings: AppSettings {
        didSet {
            persist(settings)
            onSettingsChange?(oldValue, settings)
            settingsChangeHandlers.values.forEach { handler in
                handler(oldValue, settings)
            }
        }
    }

    init(
        fileManager: FileManager = .default,
        storageURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.storageURL = storageURL ?? Self.defaultStorageURL(fileManager: fileManager)
        self.settings = Self.loadSettings(from: self.storageURL)
    }

    func reload() {
        settings = Self.loadSettings(from: storageURL)
    }

    @discardableResult
    func addSettingsChangeHandler(_ handler: @escaping (AppSettings, AppSettings) -> Void) -> UUID {
        let id = UUID()
        settingsChangeHandlers[id] = handler
        return id
    }

    func removeSettingsChangeHandler(id: UUID) {
        settingsChangeHandlers[id] = nil
    }

    private static func defaultStorageURL(fileManager: FileManager) -> URL {
        let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory

        return applicationSupportURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    private static func loadSettings(from storageURL: URL) -> AppSettings {
        guard let data = try? Data(contentsOf: storageURL) else {
            return AppSettings()
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return AppSettings()
        }
    }

    private func persist(_ settings: AppSettings) {
        do {
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(settings)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return
        }
    }
}
