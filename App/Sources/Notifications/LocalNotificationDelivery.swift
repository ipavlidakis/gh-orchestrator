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
        let content = UNMutableNotificationContent()
        content.title = Self.title(for: event)
        content.body = Self.body(for: event)
        content.sound = .default
        content.userInfo = [
            LocalNotificationUserInfo.targetURLKey: event.targetURL.absoluteString
        ]

        let request = UNNotificationRequest(
            identifier: "gh-orchestrator.\(event.id)",
            content: content,
            trigger: nil
        )

        try await center.add(request)
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

    private static func title(for event: RepositoryNotificationEvent) -> String {
        switch event.trigger {
        case .pullRequestCreated:
            return "New PR in \(event.repository.fullName)"
        case .approval:
            return "\(event.repository.fullName) #\(event.pullRequestNumber) approved"
        case .changesRequested:
            return "Changes requested on \(event.repository.fullName) #\(event.pullRequestNumber)"
        case .newUnresolvedReviewComment:
            return "New review comment on \(event.repository.fullName) #\(event.pullRequestNumber)"
        case .workflowRunCompleted:
            return "\(event.workflowName ?? "Workflow") completed"
        case .workflowJobCompleted:
            return "\(event.workflowJobName ?? "Workflow job") completed"
        }
    }

    private static func body(for event: RepositoryNotificationEvent) -> String {
        switch event.trigger {
        case .pullRequestCreated:
            let author = event.authorLogin.map { "\($0) opened " } ?? ""
            return "\(author)#\(event.pullRequestNumber): \(event.pullRequestTitle)"
        case .approval:
            return event.pullRequestTitle
        case .changesRequested:
            return event.pullRequestTitle
        case .newUnresolvedReviewComment:
            let author = event.commentAuthorLogin.map { "\($0): " } ?? ""
            return "\(author)\(event.commentBodyText ?? event.pullRequestTitle)"
        case .workflowRunCompleted:
            let conclusion = event.workflowConclusion?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let conclusion, !conclusion.isEmpty {
                return "\(event.repository.fullName) #\(event.pullRequestNumber): \(conclusion)"
            }

            return "\(event.repository.fullName) #\(event.pullRequestNumber): \(event.pullRequestTitle)"
        case .workflowJobCompleted:
            let workflowName = event.workflowName ?? "Workflow"
            let conclusion = event.workflowJobConclusion?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let conclusion, !conclusion.isEmpty {
                return "\(workflowName) for \(event.repository.fullName) #\(event.pullRequestNumber): \(conclusion)"
            }

            return "\(workflowName) for \(event.repository.fullName) #\(event.pullRequestNumber)"
        }
    }
}
