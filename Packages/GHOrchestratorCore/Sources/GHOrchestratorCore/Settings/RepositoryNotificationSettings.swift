import Foundation

public enum RepositoryNotificationTrigger: String, Codable, CaseIterable, Sendable {
    case pullRequestCreated
    case approval
    case changesRequested
    case newUnresolvedReviewComment
    case workflowRunCompleted
    case workflowJobCompleted
}

public struct RepositoryNotificationSettings: Codable, Equatable, Identifiable, Sendable {
    public static let defaultEnabledTriggers = Set(RepositoryNotificationTrigger.allCases)

    public let repositoryID: String
    public var enabled: Bool
    public var enabledTriggers: Set<RepositoryNotificationTrigger>
    public var workflowNameFilters: [String]
    public var workflowJobNameFiltersByWorkflowName: [String: [String]]

    public var id: String {
        repositoryID
    }

    public init(
        repositoryID: String,
        enabled: Bool = false,
        enabledTriggers: Set<RepositoryNotificationTrigger> = RepositoryNotificationSettings.defaultEnabledTriggers,
        workflowNameFilters: [String] = [],
        workflowJobNameFiltersByWorkflowName: [String: [String]] = [:]
    ) {
        self.repositoryID = Self.normalizedRepositoryID(repositoryID)
        self.enabled = enabled
        self.enabledTriggers = enabledTriggers
        self.workflowNameFilters = Self.normalizedWorkflowNameFilters(workflowNameFilters)
        self.workflowJobNameFiltersByWorkflowName = Self.normalizedWorkflowJobNameFilters(workflowJobNameFiltersByWorkflowName)
    }

    public init(
        repository: ObservedRepository,
        enabled: Bool = false,
        enabledTriggers: Set<RepositoryNotificationTrigger> = RepositoryNotificationSettings.defaultEnabledTriggers,
        workflowNameFilters: [String] = [],
        workflowJobNameFiltersByWorkflowName: [String: [String]] = [:]
    ) {
        self.init(
            repositoryID: repository.normalizedLookupKey,
            enabled: enabled,
            enabledTriggers: enabledTriggers,
            workflowNameFilters: workflowNameFilters,
            workflowJobNameFiltersByWorkflowName: workflowJobNameFiltersByWorkflowName
        )
    }

    enum CodingKeys: String, CodingKey {
        case repositoryID
        case enabled
        case enabledTriggers
        case workflowNameFilters
        case workflowJobNameFiltersByWorkflowName
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            repositoryID: try container.decode(String.self, forKey: .repositoryID),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            enabledTriggers: try container.decodeIfPresent(Set<RepositoryNotificationTrigger>.self, forKey: .enabledTriggers) ?? Self.defaultEnabledTriggers,
            workflowNameFilters: try container.decodeIfPresent([String].self, forKey: .workflowNameFilters) ?? [],
            workflowJobNameFiltersByWorkflowName: try container.decodeIfPresent([String: [String]].self, forKey: .workflowJobNameFiltersByWorkflowName) ?? [:]
        )
    }

    public func isTriggerEnabled(_ trigger: RepositoryNotificationTrigger) -> Bool {
        enabled && enabledTriggers.contains(trigger)
    }

    public func matchesWorkflowName(_ workflowName: String) -> Bool {
        let normalizedName = Self.normalizedWorkflowName(workflowName)
        guard !normalizedName.isEmpty else {
            return false
        }

        return workflowNameFilters.isEmpty || workflowNameFilters.contains(normalizedName)
    }

    public func matchesWorkflowJobName(
        _ jobName: String,
        workflowName: String
    ) -> Bool {
        let normalizedWorkflowName = Self.normalizedWorkflowName(workflowName)
        let normalizedJobName = Self.normalizedWorkflowJobName(jobName)
        guard !normalizedWorkflowName.isEmpty, !normalizedJobName.isEmpty else {
            return false
        }

        guard let jobFilters = workflowJobNameFiltersByWorkflowName[normalizedWorkflowName],
              !jobFilters.isEmpty
        else {
            return true
        }

        return jobFilters.contains(normalizedJobName)
    }

    public static func normalizedRepositoryID(_ repositoryID: String) -> String {
        repositoryID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedWorkflowName(_ workflowName: String) -> String {
        workflowName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedWorkflowJobName(_ jobName: String) -> String {
        jobName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedWorkflowNameFilters(_ filters: [String]) -> [String] {
        var normalizedFilters: [String] = []
        var seenFilters = Set<String>()

        for filter in filters {
            let normalizedFilter = normalizedWorkflowName(filter)
            guard !normalizedFilter.isEmpty else {
                continue
            }

            if seenFilters.insert(normalizedFilter).inserted {
                normalizedFilters.append(normalizedFilter)
            }
        }

        return normalizedFilters
    }

    public static func parseWorkflowNameFilters(from rawValue: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n")
        let filters = rawValue
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        return normalizedWorkflowNameFilters(filters)
    }

    public static func normalizedWorkflowJobNameFilters(_ filtersByWorkflowName: [String: [String]]) -> [String: [String]] {
        var normalizedFiltersByWorkflowName: [String: [String]] = [:]

        for (workflowName, jobNames) in filtersByWorkflowName {
            let normalizedWorkflowName = normalizedWorkflowName(workflowName)
            let normalizedJobNames = normalizedWorkflowJobNameFilters(jobNames)

            guard !normalizedWorkflowName.isEmpty, !normalizedJobNames.isEmpty else {
                continue
            }

            normalizedFiltersByWorkflowName[normalizedWorkflowName] = normalizedJobNames
        }

        return normalizedFiltersByWorkflowName
    }

    public static func normalizedWorkflowJobNameFilters(_ filters: [String]) -> [String] {
        var normalizedFilters: [String] = []
        var seenFilters = Set<String>()

        for filter in filters {
            let normalizedFilter = normalizedWorkflowJobName(filter)
            guard !normalizedFilter.isEmpty else {
                continue
            }

            if seenFilters.insert(normalizedFilter).inserted {
                normalizedFilters.append(normalizedFilter)
            }
        }

        return normalizedFilters
    }
}
