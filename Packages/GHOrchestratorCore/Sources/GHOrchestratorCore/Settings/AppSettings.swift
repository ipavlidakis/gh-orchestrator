public struct AppSettings: Codable, Equatable, Sendable {
    public static let defaultPollingIntervalSeconds = 60
    public static let allowedPollingIntervalRange = 15...900
    public static let defaultHideDockIcon = false
    public static let defaultStartAtLogin = false
    public static let defaultAutomaticallyCheckForUpdates = true
    public static let defaultGraphQLSearchResultLimit = 10
    public static let defaultGraphQLReviewThreadLimit = 10
    public static let defaultGraphQLReviewThreadCommentLimit = 5
    public static let defaultGraphQLCheckContextLimit = 15
    public static let allowedGraphQLConnectionLimitRange = 1...100
    public static let allowedGraphQLReviewThreadCommentLimitRange = 1...20

    public var observedRepositories: [ObservedRepository]
    public var pollingIntervalSeconds: Int
    public var hideDockIcon: Bool
    public var startAtLogin: Bool
    public var automaticallyCheckForUpdates: Bool
    public var graphQLSearchResultLimit: Int
    public var graphQLReviewThreadLimit: Int
    public var graphQLReviewThreadCommentLimit: Int
    public var graphQLCheckContextLimit: Int
    public var repositoryNotificationSettings: [RepositoryNotificationSettings]

    public init(
        observedRepositories: [ObservedRepository] = [],
        pollingIntervalSeconds: Int = AppSettings.defaultPollingIntervalSeconds,
        hideDockIcon: Bool = AppSettings.defaultHideDockIcon,
        startAtLogin: Bool = AppSettings.defaultStartAtLogin,
        automaticallyCheckForUpdates: Bool = AppSettings.defaultAutomaticallyCheckForUpdates,
        graphQLSearchResultLimit: Int = AppSettings.defaultGraphQLSearchResultLimit,
        graphQLReviewThreadLimit: Int = AppSettings.defaultGraphQLReviewThreadLimit,
        graphQLReviewThreadCommentLimit: Int = AppSettings.defaultGraphQLReviewThreadCommentLimit,
        graphQLCheckContextLimit: Int = AppSettings.defaultGraphQLCheckContextLimit,
        repositoryNotificationSettings: [RepositoryNotificationSettings] = []
    ) {
        let deduplicatedRepositories = Self.deduplicatedRepositories(observedRepositories)

        self.observedRepositories = deduplicatedRepositories
        self.pollingIntervalSeconds = Self.clampPollingInterval(pollingIntervalSeconds)
        self.hideDockIcon = hideDockIcon
        self.startAtLogin = startAtLogin
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.graphQLSearchResultLimit = Self.clampGraphQLConnectionLimit(graphQLSearchResultLimit)
        self.graphQLReviewThreadLimit = Self.clampGraphQLConnectionLimit(graphQLReviewThreadLimit)
        self.graphQLReviewThreadCommentLimit = Self.clampGraphQLReviewThreadCommentLimit(graphQLReviewThreadCommentLimit)
        self.graphQLCheckContextLimit = Self.clampGraphQLConnectionLimit(graphQLCheckContextLimit)
        self.repositoryNotificationSettings = Self.normalizedNotificationSettings(
            repositoryNotificationSettings,
            observedRepositories: deduplicatedRepositories
        )
    }

    enum CodingKeys: String, CodingKey {
        case observedRepositories
        case pollingIntervalSeconds
        case hideDockIcon
        case startAtLogin
        case automaticallyCheckForUpdates
        case graphQLSearchResultLimit
        case graphQLReviewThreadLimit
        case graphQLReviewThreadCommentLimit
        case graphQLCheckContextLimit
        case repositoryNotificationSettings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            observedRepositories: try container.decodeIfPresent([ObservedRepository].self, forKey: .observedRepositories) ?? [],
            pollingIntervalSeconds: try container.decodeIfPresent(Int.self, forKey: .pollingIntervalSeconds) ?? Self.defaultPollingIntervalSeconds,
            hideDockIcon: try container.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? Self.defaultHideDockIcon,
            startAtLogin: try container.decodeIfPresent(Bool.self, forKey: .startAtLogin) ?? Self.defaultStartAtLogin,
            automaticallyCheckForUpdates: try container.decodeIfPresent(Bool.self, forKey: .automaticallyCheckForUpdates) ?? Self.defaultAutomaticallyCheckForUpdates,
            graphQLSearchResultLimit: try container.decodeIfPresent(Int.self, forKey: .graphQLSearchResultLimit) ?? Self.defaultGraphQLSearchResultLimit,
            graphQLReviewThreadLimit: try container.decodeIfPresent(Int.self, forKey: .graphQLReviewThreadLimit) ?? Self.defaultGraphQLReviewThreadLimit,
            graphQLReviewThreadCommentLimit: try container.decodeIfPresent(Int.self, forKey: .graphQLReviewThreadCommentLimit) ?? Self.defaultGraphQLReviewThreadCommentLimit,
            graphQLCheckContextLimit: try container.decodeIfPresent(Int.self, forKey: .graphQLCheckContextLimit) ?? Self.defaultGraphQLCheckContextLimit,
            repositoryNotificationSettings: try container.decodeIfPresent([RepositoryNotificationSettings].self, forKey: .repositoryNotificationSettings) ?? []
        )
    }

    public static func clampPollingInterval(_ value: Int) -> Int {
        min(max(value, allowedPollingIntervalRange.lowerBound), allowedPollingIntervalRange.upperBound)
    }

    public static func clampGraphQLConnectionLimit(_ value: Int) -> Int {
        min(max(value, allowedGraphQLConnectionLimitRange.lowerBound), allowedGraphQLConnectionLimitRange.upperBound)
    }

    public static func clampGraphQLReviewThreadCommentLimit(_ value: Int) -> Int {
        min(max(value, allowedGraphQLReviewThreadCommentLimitRange.lowerBound), allowedGraphQLReviewThreadCommentLimitRange.upperBound)
    }

    public func notificationSettings(for repository: ObservedRepository) -> RepositoryNotificationSettings? {
        let repositoryID = repository.normalizedLookupKey
        return repositoryNotificationSettings.first { $0.repositoryID == repositoryID }
    }

    public func notificationSettings(forRepositoryID repositoryID: String) -> RepositoryNotificationSettings? {
        let normalizedRepositoryID = RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        return repositoryNotificationSettings.first { $0.repositoryID == normalizedRepositoryID }
    }

    public func effectiveNotificationSettings(for repository: ObservedRepository) -> RepositoryNotificationSettings {
        notificationSettings(for: repository) ?? RepositoryNotificationSettings(repository: repository)
    }

    public var hasEnabledRepositoryNotifications: Bool {
        repositoryNotificationSettings.contains { $0.enabled }
    }

    public mutating func updateNotificationSettings(_ settings: RepositoryNotificationSettings) {
        let observedRepositoryIDs = Set(observedRepositories.map(\.normalizedLookupKey))
        guard observedRepositoryIDs.contains(settings.repositoryID) else {
            return
        }

        if let index = repositoryNotificationSettings.firstIndex(where: { $0.repositoryID == settings.repositoryID }) {
            repositoryNotificationSettings[index] = settings
        } else {
            repositoryNotificationSettings.append(settings)
        }

        reconcileNotificationSettingsWithObservedRepositories()
    }

    public mutating func reconcileNotificationSettingsWithObservedRepositories() {
        repositoryNotificationSettings = Self.normalizedNotificationSettings(
            repositoryNotificationSettings,
            observedRepositories: observedRepositories
        )
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

    private static func normalizedNotificationSettings(
        _ settings: [RepositoryNotificationSettings],
        observedRepositories: [ObservedRepository]
    ) -> [RepositoryNotificationSettings] {
        let observedRepositoryIDs = Set(observedRepositories.map(\.normalizedLookupKey))
        var normalizedSettings: [RepositoryNotificationSettings] = []
        var seenRepositoryIDs = Set<String>()

        for setting in settings {
            let normalizedSetting = RepositoryNotificationSettings(
                repositoryID: setting.repositoryID,
                enabled: setting.enabled,
                enabledTriggers: setting.enabledTriggers,
                workflowNameFilters: setting.workflowNameFilters,
                workflowJobNameFiltersByWorkflowName: setting.workflowJobNameFiltersByWorkflowName
            )

            guard observedRepositoryIDs.contains(normalizedSetting.repositoryID) else {
                continue
            }

            if seenRepositoryIDs.insert(normalizedSetting.repositoryID).inserted {
                normalizedSettings.append(normalizedSetting)
            }
        }

        return normalizedSettings
    }
}
