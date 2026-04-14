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

    var settings: AppSettings {
        didSet {
            persist(settings)
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
