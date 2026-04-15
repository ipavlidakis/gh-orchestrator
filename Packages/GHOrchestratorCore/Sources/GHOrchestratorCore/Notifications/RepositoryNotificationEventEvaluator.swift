import Foundation

public struct RepositoryNotificationEvent: Equatable, Identifiable, Sendable {
    public let trigger: RepositoryNotificationTrigger
    public let repository: ObservedRepository
    public let pullRequestNumber: Int
    public let pullRequestTitle: String
    public let pullRequestURL: URL
    public let targetURL: URL
    public let authorLogin: String?
    public let commentBodyText: String?
    public let commentFilePath: String?
    public let commentAuthorLogin: String?
    public let workflowRunID: Int?
    public let workflowName: String?
    public let workflowConclusion: String?
    public let workflowJobID: Int?
    public let workflowJobName: String?
    public let workflowJobConclusion: String?

    public var id: String {
        switch trigger {
        case .pullRequestCreated:
            return "\(repository.normalizedLookupKey)#\(pullRequestNumber):created"
        case .approval:
            return "\(repository.normalizedLookupKey)#\(pullRequestNumber):approval"
        case .changesRequested:
            return "\(repository.normalizedLookupKey)#\(pullRequestNumber):changes-requested"
        case .newUnresolvedReviewComment:
            return "\(repository.normalizedLookupKey)#\(pullRequestNumber):comment:\(targetURL.absoluteString)"
        case .workflowRunCompleted:
            return "\(repository.normalizedLookupKey)#\(pullRequestNumber):workflow:\(workflowRunID ?? 0):completed:\(workflowConclusion ?? "none")"
        case .workflowJobCompleted:
            return "\(repository.normalizedLookupKey)#\(pullRequestNumber):workflow:\(workflowRunID ?? 0):job:\(workflowJobID ?? 0):completed:\(workflowJobConclusion ?? "none")"
        }
    }

    public init(
        trigger: RepositoryNotificationTrigger,
        repository: ObservedRepository,
        pullRequestNumber: Int,
        pullRequestTitle: String,
        pullRequestURL: URL,
        targetURL: URL,
        authorLogin: String? = nil,
        commentBodyText: String? = nil,
        commentFilePath: String? = nil,
        commentAuthorLogin: String? = nil,
        workflowRunID: Int? = nil,
        workflowName: String? = nil,
        workflowConclusion: String? = nil,
        workflowJobID: Int? = nil,
        workflowJobName: String? = nil,
        workflowJobConclusion: String? = nil
    ) {
        self.trigger = trigger
        self.repository = repository
        self.pullRequestNumber = pullRequestNumber
        self.pullRequestTitle = pullRequestTitle
        self.pullRequestURL = pullRequestURL
        self.targetURL = targetURL
        self.authorLogin = authorLogin
        self.commentBodyText = commentBodyText
        self.commentFilePath = commentFilePath
        self.commentAuthorLogin = commentAuthorLogin
        self.workflowRunID = workflowRunID
        self.workflowName = workflowName
        self.workflowConclusion = workflowConclusion
        self.workflowJobID = workflowJobID
        self.workflowJobName = workflowJobName
        self.workflowJobConclusion = workflowJobConclusion
    }
}

public struct RepositoryNotificationBaseline: Equatable, Sendable {
    public let pullRequestsByID: [String: RepositoryNotificationPullRequestState]

    public init(sections: [RepositorySection]) {
        var pullRequestsByID: [String: RepositoryNotificationPullRequestState] = [:]

        for section in sections {
            for pullRequest in section.pullRequests {
                pullRequestsByID[pullRequest.id] = RepositoryNotificationPullRequestState(pullRequest: pullRequest)
            }
        }

        self.pullRequestsByID = pullRequestsByID
    }

    public func state(for pullRequestID: String) -> RepositoryNotificationPullRequestState? {
        pullRequestsByID[pullRequestID]
    }
}

public struct RepositoryNotificationPullRequestState: Equatable, Sendable {
    public let reviewStatus: ReviewStatus
    public let unresolvedReviewCommentIDs: Set<String>
    public let workflowRunsByID: [Int: RepositoryNotificationWorkflowRunState]

    public init(pullRequest: PullRequestItem) {
        self.reviewStatus = pullRequest.reviewStatus
        self.unresolvedReviewCommentIDs = Set(pullRequest.unresolvedReviewComments.map(\.id))
        self.workflowRunsByID = Dictionary(
            uniqueKeysWithValues: pullRequest.workflowRuns.map { workflowRun in
                (
                    workflowRun.id,
                    RepositoryNotificationWorkflowRunState(workflowRun: workflowRun)
                )
            }
        )
    }
}

public struct RepositoryNotificationWorkflowRunState: Equatable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let detailsURL: URL?
    public let jobsByID: [Int: RepositoryNotificationWorkflowJobState]

    public var isCompleted: Bool {
        status.caseInsensitiveCompare("completed") == .orderedSame
    }

    public init(workflowRun: WorkflowRunItem) {
        self.name = workflowRun.name
        self.status = workflowRun.status
        self.conclusion = workflowRun.conclusion
        self.detailsURL = workflowRun.detailsURL
        self.jobsByID = Dictionary(
            uniqueKeysWithValues: workflowRun.jobs.map { job in
                (
                    job.id,
                    RepositoryNotificationWorkflowJobState(job: job)
                )
            }
        )
    }
}

public struct RepositoryNotificationWorkflowJobState: Equatable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let detailsURL: URL?

    public var isCompleted: Bool {
        status.caseInsensitiveCompare("completed") == .orderedSame
    }

    public init(job: ActionJobItem) {
        self.name = job.name
        self.status = job.status
        self.conclusion = job.conclusion
        self.detailsURL = job.detailsURL
    }
}

public struct RepositoryNotificationEvaluation: Equatable, Sendable {
    public let baseline: RepositoryNotificationBaseline
    public let events: [RepositoryNotificationEvent]

    public init(
        baseline: RepositoryNotificationBaseline,
        events: [RepositoryNotificationEvent]
    ) {
        self.baseline = baseline
        self.events = events
    }
}

public struct RepositoryNotificationEventEvaluator: Sendable {
    public init() {}

    public func evaluate(
        previousBaseline: RepositoryNotificationBaseline?,
        currentSections: [RepositorySection],
        settings: AppSettings
    ) -> RepositoryNotificationEvaluation {
        let nextBaseline = RepositoryNotificationBaseline(sections: currentSections)
        guard let previousBaseline else {
            return RepositoryNotificationEvaluation(baseline: nextBaseline, events: [])
        }

        let settingsByRepositoryID = Dictionary(
            uniqueKeysWithValues: settings.repositoryNotificationSettings
                .filter(\.enabled)
                .map { ($0.repositoryID, $0) }
        )

        guard !settingsByRepositoryID.isEmpty else {
            return RepositoryNotificationEvaluation(baseline: nextBaseline, events: [])
        }

        let events = currentSections.flatMap { section -> [RepositoryNotificationEvent] in
            guard let repositorySettings = settingsByRepositoryID[section.repository.normalizedLookupKey] else {
                return []
            }

            return section.pullRequests.flatMap { pullRequest in
                if previousBaseline.state(for: pullRequest.id) == nil,
                   repositorySettings.isTriggerEnabled(.pullRequestCreated) {
                    return [
                        makeEvent(
                            trigger: .pullRequestCreated,
                            pullRequest: pullRequest,
                            targetURL: pullRequest.url
                        )
                    ]
                }

                return notificationEvents(
                    for: pullRequest,
                    repositorySettings: repositorySettings,
                    previousBaseline: previousBaseline
                )
            }
        }

        return RepositoryNotificationEvaluation(baseline: nextBaseline, events: events)
    }

    private func notificationEvents(
        for pullRequest: PullRequestItem,
        repositorySettings: RepositoryNotificationSettings,
        previousBaseline: RepositoryNotificationBaseline
    ) -> [RepositoryNotificationEvent] {
        guard let previousState = previousBaseline.state(for: pullRequest.id) else {
            return []
        }

        var events: [RepositoryNotificationEvent] = []

        if repositorySettings.isTriggerEnabled(.approval),
           previousState.reviewStatus != .approved,
           pullRequest.reviewStatus == .approved {
            events.append(
                makeEvent(
                    trigger: .approval,
                    pullRequest: pullRequest,
                    targetURL: pullRequest.url
                )
            )
        }

        if repositorySettings.isTriggerEnabled(.changesRequested),
           previousState.reviewStatus != .changesRequested,
           pullRequest.reviewStatus == .changesRequested {
            events.append(
                makeEvent(
                    trigger: .changesRequested,
                    pullRequest: pullRequest,
                    targetURL: pullRequest.url
                )
            )
        }

        if repositorySettings.isTriggerEnabled(.newUnresolvedReviewComment) {
            for comment in pullRequest.unresolvedReviewComments where !previousState.unresolvedReviewCommentIDs.contains(comment.id) {
                events.append(
                    makeEvent(
                        trigger: .newUnresolvedReviewComment,
                        pullRequest: pullRequest,
                        targetURL: comment.url,
                        commentBodyText: comment.bodyText,
                        commentFilePath: comment.filePath,
                        commentAuthorLogin: comment.authorLogin
                    )
                )
            }
        }

        if repositorySettings.isTriggerEnabled(.workflowRunCompleted) {
            for workflowRun in pullRequest.workflowRuns {
                let currentWorkflowState = RepositoryNotificationWorkflowRunState(workflowRun: workflowRun)
                guard currentWorkflowState.isCompleted else {
                    continue
                }

                if previousState.workflowRunsByID[workflowRun.id]?.isCompleted == true {
                    continue
                }

                guard repositorySettings.matchesWorkflowName(workflowRun.name) else {
                    continue
                }

                events.append(
                    makeEvent(
                        trigger: .workflowRunCompleted,
                        pullRequest: pullRequest,
                        targetURL: workflowRun.detailsURL ?? pullRequest.url,
                        workflowRunID: workflowRun.id,
                        workflowName: workflowRun.name,
                        workflowConclusion: workflowRun.conclusion
                    )
                )
            }
        }

        if repositorySettings.isTriggerEnabled(.workflowJobCompleted) {
            for workflowRun in pullRequest.workflowRuns {
                guard repositorySettings.matchesWorkflowName(workflowRun.name) else {
                    continue
                }

                let previousWorkflowState = previousState.workflowRunsByID[workflowRun.id]

                for job in workflowRun.jobs {
                    let currentJobState = RepositoryNotificationWorkflowJobState(job: job)
                    guard currentJobState.isCompleted else {
                        continue
                    }

                    guard repositorySettings.matchesWorkflowJobName(job.name, workflowName: workflowRun.name) else {
                        continue
                    }

                    if previousWorkflowState?.jobsByID[job.id]?.isCompleted == true {
                        continue
                    }

                    events.append(
                        makeEvent(
                            trigger: .workflowJobCompleted,
                            pullRequest: pullRequest,
                            targetURL: job.detailsURL ?? workflowRun.detailsURL ?? pullRequest.url,
                            workflowRunID: workflowRun.id,
                            workflowName: workflowRun.name,
                            workflowConclusion: workflowRun.conclusion,
                            workflowJobID: job.id,
                            workflowJobName: job.name,
                            workflowJobConclusion: job.conclusion
                        )
                    )
                }
            }
        }

        return events
    }

    private func makeEvent(
        trigger: RepositoryNotificationTrigger,
        pullRequest: PullRequestItem,
        targetURL: URL,
        commentBodyText: String? = nil,
        commentFilePath: String? = nil,
        commentAuthorLogin: String? = nil,
        workflowRunID: Int? = nil,
        workflowName: String? = nil,
        workflowConclusion: String? = nil,
        workflowJobID: Int? = nil,
        workflowJobName: String? = nil,
        workflowJobConclusion: String? = nil
    ) -> RepositoryNotificationEvent {
        RepositoryNotificationEvent(
            trigger: trigger,
            repository: pullRequest.repository,
            pullRequestNumber: pullRequest.number,
            pullRequestTitle: pullRequest.title,
            pullRequestURL: pullRequest.url,
            targetURL: targetURL,
            authorLogin: pullRequest.authorLogin,
            commentBodyText: commentBodyText,
            commentFilePath: commentFilePath,
            commentAuthorLogin: commentAuthorLogin,
            workflowRunID: workflowRunID,
            workflowName: workflowName,
            workflowConclusion: workflowConclusion,
            workflowJobID: workflowJobID,
            workflowJobName: workflowJobName,
            workflowJobConclusion: workflowJobConclusion
        )
    }
}
