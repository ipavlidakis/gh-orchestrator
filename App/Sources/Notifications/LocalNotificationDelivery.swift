import Foundation
import GHOrchestratorCore
import UserNotifications

enum LocalNotificationAuthorizationStatus: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown

    var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied, .unknown:
            return false
        }
    }

    var description: String {
        switch self {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied in System Settings"
        case .authorized:
            return "Allowed"
        case .provisional:
            return "Allowed quietly"
        case .ephemeral:
            return "Allowed for this session"
        case .unknown:
            return "Unknown"
        }
    }

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .provisional:
            self = .provisional
        case .ephemeral:
            self = .ephemeral
        @unknown default:
            self = .unknown
        }
    }
}

@MainActor
protocol LocalNotificationDelivering: AnyObject {
    func authorizationStatus() async -> LocalNotificationAuthorizationStatus
    func requestAuthorization() async throws -> LocalNotificationAuthorizationStatus
    func deliver(_ event: RepositoryNotificationEvent) async throws
    func deliverPreview(_ event: RepositoryNotificationEvent) async throws
}

enum LocalNotificationUserInfo {
    static let targetURLKey = "targetURL"

    static func targetURL(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let rawURL = userInfo[targetURLKey] as? String else {
            return nil
        }

        return URL(string: rawURL)
    }
}

final class NotificationResponseRouter: @unchecked Sendable {
    private let openURL: @MainActor (URL) -> Void

    init(openURL: @escaping @MainActor (URL) -> Void) {
        self.openURL = openURL
    }

    func route(userInfo: [AnyHashable: Any]) {
        guard let targetURL = LocalNotificationUserInfo.targetURL(from: userInfo) else {
            return
        }

        Task { @MainActor in
            openURL(targetURL)
        }
    }
}

final class UserNotificationCenterDelivery: NSObject, LocalNotificationDelivering, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let responseRouter: NotificationResponseRouter

    init(
        center: UNUserNotificationCenter = .current(),
        responseRouter: NotificationResponseRouter
    ) {
        self.center = center
        self.responseRouter = responseRouter

        super.init()

        center.delegate = self
    }

    func authorizationStatus() async -> LocalNotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        return LocalNotificationAuthorizationStatus(settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> LocalNotificationAuthorizationStatus {
        _ = try await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func deliver(_ event: RepositoryNotificationEvent) async throws {
        try await addNotificationRequest(
            for: event,
            identifier: "gh-orchestrator.\(event.id)"
        )
    }

    func deliverPreview(_ event: RepositoryNotificationEvent) async throws {
        try await addNotificationRequest(
            for: event,
            identifier: "gh-orchestrator.preview.\(UUID().uuidString)"
        )
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        responseRouter.route(userInfo: response.notification.request.content.userInfo)
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func addNotificationRequest(
        for event: RepositoryNotificationEvent,
        identifier: String
    ) async throws {
        let content = UNMutableNotificationContent()
        content.title = LocalNotificationContentFormatter.title(for: event)
        content.body = LocalNotificationContentFormatter.body(for: event)
        content.sound = .default
        content.userInfo = [
            LocalNotificationUserInfo.targetURLKey: event.targetURL.absoluteString
        ]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        try await center.add(request)
    }
}

enum LocalNotificationContentFormatter {
    static func title(for event: RepositoryNotificationEvent) -> String {
        switch event.trigger {
        case .pullRequestCreated:
            return event.repository.fullName
        case .approval:
            return event.repository.fullName
        case .changesRequested:
            return event.repository.fullName
        case .newUnresolvedReviewComment:
            return event.repository.fullName
        case .workflowRunCompleted:
            return event.repository.fullName
        case .workflowJobCompleted:
            return event.repository.name
        }
    }

    static func body(for event: RepositoryNotificationEvent) -> String {
        switch event.trigger {
        case .pullRequestCreated:
            let lineA = "New PR #\(event.pullRequestNumber): \(event.pullRequestTitle)"
            if let author = event.authorLogin?.trimmingCharacters(in: .whitespacesAndNewlines),
               !author.isEmpty {
                return "\(lineA)\nOpened by \(author)"
            }
            return lineA

        case .approval:
            let lineA = "PR #\(event.pullRequestNumber) approved 👍"
            let lineB = event.pullRequestTitle
            return "\(lineA)\n\(lineB)"

        case .changesRequested:
            let lineA = "PR #\(event.pullRequestNumber) changes requested 🔄"
            let lineB = event.pullRequestTitle
            return "\(lineA)\n\(lineB)"

        case .newUnresolvedReviewComment:
            var lineA = "PR #\(event.pullRequestNumber) new comment"
            if let author = event.commentAuthorLogin {
                lineA += " by \(author)"
            }
            let lineB = event.pullRequestTitle
            if let commentBodyText = event.commentBodyText, !commentBodyText.isEmpty {
                return "\(lineA)\n\(lineB)\n→ \(commentBodyText)"
            } else {
                return "\(lineA)\n\(lineB)"
            }
        case .workflowRunCompleted:
            let conclusion = event.workflowConclusion?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let conclusion, !conclusion.isEmpty {
                return "\(event.repository.fullName) #\(event.pullRequestNumber): \(conclusion)"
            }

            return "\(event.repository.fullName) #\(event.pullRequestNumber): \(event.pullRequestTitle)"
        case .workflowJobCompleted:
            return workflowJobBody(for: event)
        }
    }

    private static func workflowJobBody(for event: RepositoryNotificationEvent) -> String {
        let rawJobName = event.workflowJobName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let jobName = rawJobName.flatMap { $0.isEmpty ? nil : $0 } ?? "Workflow job"
        let conclusion = event.workflowJobConclusion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSuccess = conclusion?.caseInsensitiveCompare("success") == .orderedSame
        let rawPullRequestTitle = event.pullRequestTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let pullRequestSuffix = rawPullRequestTitle.isEmpty ? "" : " - \(rawPullRequestTitle)"

        return "\(isSuccess ? "✅" : "❌") \(jobName) \(isSuccess ? "succeed" : "fail")\(pullRequestSuffix)"
    }
}
