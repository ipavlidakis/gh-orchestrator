public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultPollingIntervalSeconds = 60
    public static let allowedPollingIntervalRange = 15...900
    public static let defaultHideDockIcon = false

    public var observedRepositories: [ObservedRepository]
    public var pollingIntervalSeconds: Int
    public var hideDockIcon: Bool

    public init(
        observedRepositories: [ObservedRepository] = [],
        pollingIntervalSeconds: Int = AppSettings.defaultPollingIntervalSeconds,
        hideDockIcon: Bool = AppSettings.defaultHideDockIcon
    ) {
        self.observedRepositories = Self.deduplicatedRepositories(observedRepositories)
        self.pollingIntervalSeconds = Self.clampPollingInterval(pollingIntervalSeconds)
        self.hideDockIcon = hideDockIcon
    }

    public static func clampPollingInterval(_ value: Int) -> Int {
        min(max(value, allowedPollingIntervalRange.lowerBound), allowedPollingIntervalRange.upperBound)
    }

    private static func deduplicatedRepositories(_ repositories: [ObservedRepository]) -> [ObservedRepository] {
        var deduplicated: [ObservedRepository] = []
        var seenKeys = Set<String>()

        for repository in repositories {
            if seenKeys.insert(repository.normalizedLookupKey).inserted {
                deduplicated.append(repository)
            }
        }

        return deduplicated
    }
}
