#if DEBUG
import Foundation
import GHOrchestratorCore
import Observation
import SwiftUI

@Observable
final class NotificationDebugPreviewModel {
    var selectedTrigger: RepositoryNotificationTrigger = .pullRequestCreated
    var repositoryOwner = "ipavlidakis"
    var repositoryName = "gh-orchestrator"
    var pullRequestNumberText = "1"
    var pullRequestTitle = "Add notifications"
    var authorLogin = "ipavlidakis"
    var commentAuthorLogin = "reviewer"
    var commentBodyText = "Please update the tests before merging."
    var workflowName = "CI"
    var workflowConclusion = "success"
    var workflowJobName = "unit-tests"
    var workflowJobConclusion = "success"
    var targetURLText = ""
    var deliveryState: NotificationDebugPreviewDeliveryState = .idle

    var isSending: Bool {
        if case .sending = deliveryState {
            return true
        }

        return false
    }

    var deliveryMessage: String? {
        switch deliveryState {
        case .idle:
            return nil
        case .sending:
            return "Sending preview..."
        case .delivered(let message), .failed(let message):
            return message
        }
    }

    func makeEvent() throws -> RepositoryNotificationEvent {
        let repository = try makeRepository()
        let pullRequestNumber = try makePullRequestNumber()
        let resolvedPullRequestTitle = try nonEmptyValue(
            pullRequestTitle,
            error: .missingPullRequestTitle
        )
        let pullRequestURL = URL(string: "https://github.com/\(repository.fullName)/pull/\(pullRequestNumber)")!
        let targetURL = try makeTargetURL(
            repository: repository,
            pullRequestNumber: pullRequestNumber,
            pullRequestURL: pullRequestURL
        )

        switch selectedTrigger {
        case .pullRequestCreated:
            return RepositoryNotificationEvent(
                trigger: .pullRequestCreated,
                repository: repository,
                pullRequestNumber: pullRequestNumber,
                pullRequestTitle: resolvedPullRequestTitle,
                pullRequestURL: pullRequestURL,
                targetURL: targetURL,
                authorLogin: trimmedValue(authorLogin)
            )
        case .approval:
            return RepositoryNotificationEvent(
                trigger: .approval,
                repository: repository,
                pullRequestNumber: pullRequestNumber,
                pullRequestTitle: resolvedPullRequestTitle,
                pullRequestURL: pullRequestURL,
                targetURL: targetURL
            )
        case .changesRequested:
            return RepositoryNotificationEvent(
                trigger: .changesRequested,
                repository: repository,
                pullRequestNumber: pullRequestNumber,
                pullRequestTitle: resolvedPullRequestTitle,
                pullRequestURL: pullRequestURL,
                targetURL: targetURL
            )
        case .newUnresolvedReviewComment:
            return RepositoryNotificationEvent(
                trigger: .newUnresolvedReviewComment,
                repository: repository,
                pullRequestNumber: pullRequestNumber,
                pullRequestTitle: resolvedPullRequestTitle,
                pullRequestURL: pullRequestURL,
                targetURL: targetURL,
                commentBodyText: try nonEmptyValue(
                    commentBodyText,
                    error: .missingCommentBody
                ),
                commentAuthorLogin: trimmedValue(commentAuthorLogin)
            )
        case .workflowRunCompleted:
            return RepositoryNotificationEvent(
                trigger: .workflowRunCompleted,
                repository: repository,
                pullRequestNumber: pullRequestNumber,
                pullRequestTitle: resolvedPullRequestTitle,
                pullRequestURL: pullRequestURL,
                targetURL: targetURL,
                workflowRunID: 1,
                workflowName: try nonEmptyValue(
                    workflowName,
                    error: .missingWorkflowName
                ),
                workflowConclusion: trimmedValue(workflowConclusion)
            )
        case .workflowJobCompleted:
            let resolvedWorkflowName = try nonEmptyValue(
                workflowName,
                error: .missingWorkflowName
            )
            let resolvedWorkflowJobConclusion = trimmedValue(workflowJobConclusion)

            return RepositoryNotificationEvent(
                trigger: .workflowJobCompleted,
                repository: repository,
                pullRequestNumber: pullRequestNumber,
                pullRequestTitle: resolvedPullRequestTitle,
                pullRequestURL: pullRequestURL,
                targetURL: targetURL,
                workflowRunID: 1,
                workflowName: resolvedWorkflowName,
                workflowConclusion: resolvedWorkflowJobConclusion,
                workflowJobID: 1,
                workflowJobName: try nonEmptyValue(
                    workflowJobName,
                    error: .missingWorkflowJobName
                ),
                workflowJobConclusion: resolvedWorkflowJobConclusion
            )
        }
    }

    private func makeRepository() throws -> ObservedRepository {
        let rawValue = "\(repositoryOwner)/\(repositoryName)"
        guard let repository = ObservedRepository(rawValue: rawValue) else {
            throw NotificationDebugPreviewError.invalidRepository
        }

        return repository
    }

    private func makePullRequestNumber() throws -> Int {
        guard let pullRequestNumber = Int(trimmedValue(pullRequestNumberText) ?? ""),
              pullRequestNumber > 0
        else {
            throw NotificationDebugPreviewError.invalidPullRequestNumber
        }

        return pullRequestNumber
    }

    private func makeTargetURL(
        repository: ObservedRepository,
        pullRequestNumber: Int,
        pullRequestURL: URL
    ) throws -> URL {
        if let targetURLText = trimmedValue(targetURLText) {
            guard let targetURL = URL(string: targetURLText) else {
                throw NotificationDebugPreviewError.invalidTargetURL
            }

            return targetURL
        }

        switch selectedTrigger {
        case .pullRequestCreated, .approval, .changesRequested, .newUnresolvedReviewComment:
            return pullRequestURL
        case .workflowRunCompleted:
            return URL(string: "https://github.com/\(repository.fullName)/actions/runs/\(pullRequestNumber)")!
        case .workflowJobCompleted:
            return URL(string: "https://github.com/\(repository.fullName)/actions/runs/\(pullRequestNumber)/job/1")!
        }
    }

    private func nonEmptyValue(
        _ rawValue: String,
        error: NotificationDebugPreviewError
    ) throws -> String {
        guard let value = trimmedValue(rawValue) else {
            throw error
        }

        return value
    }

    private func trimmedValue(_ rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

enum NotificationDebugPreviewDeliveryState: Equatable {
    case idle
    case sending
    case delivered(String)
    case failed(String)

    var isFailure: Bool {
        if case .failed = self {
            return true
        }

        return false
    }
}

enum NotificationDebugPreviewError: LocalizedError {
    case invalidRepository
    case invalidPullRequestNumber
    case missingPullRequestTitle
    case invalidTargetURL
    case missingCommentBody
    case missingWorkflowName
    case missingWorkflowJobName

    var errorDescription: String? {
        switch self {
        case .invalidRepository:
            return "Enter a valid repository owner and name."
        case .invalidPullRequestNumber:
            return "Pull request number must be a positive whole number."
        case .missingPullRequestTitle:
            return "Pull request title is required."
        case .invalidTargetURL:
            return "Target URL must be a valid URL."
        case .missingCommentBody:
            return "Comment previews need comment text."
        case .missingWorkflowName:
            return "Workflow previews need a workflow name."
        case .missingWorkflowJobName:
            return "Workflow job previews need a job name."
        }
    }
}

struct NotificationDebugPreviewGroup: View {
    @Bindable var model: SettingsModel
    @Bindable var preview: NotificationDebugPreviewModel

    var body: some View {
        SettingsGroup(title: "Debug previews") {
            SettingsRow(
                title: "Notification type",
                subtitle: "Deliver a synthetic notification through the real formatter and local notification adapter."
            ) {
                Picker("", selection: $preview.selectedTrigger) {
                    ForEach(RepositoryNotificationTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.debugPreviewTitle)
                            .tag(trigger)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }

            Divider()

            SettingsRow(
                title: "Repository",
                subtitle: "Owner and repository name used to build the synthetic event."
            ) {
                HStack(spacing: 8) {
                    TextField("owner", text: $preview.repositoryOwner)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    Text("/")
                        .foregroundStyle(.secondary)

                    TextField("repository", text: $preview.repositoryName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                }
            }

            Divider()

            SettingsRow(
                title: "Pull request",
                subtitle: "Shared PR fields used by every notification type."
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("Number", text: $preview.pullRequestNumberText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)

                    TextField("Pull request title", text: $preview.pullRequestTitle, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...3)
                        .frame(width: 320)
                }
            }

            Divider()

            triggerSpecificFields

            Divider()

            SettingsRow(
                title: "Link target",
                subtitle: "Optional click target override. Leave empty to use a trigger-specific default URL."
            ) {
                TextField("https://github.com/owner/repository/...", text: $preview.targetURLText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 320)
            }

            Divider()

            SettingsRow(
                title: "Preview copy",
                subtitle: "Uses the same formatter as production notifications."
            ) {
                NotificationDebugPreviewCard(preview: preview)
            }

            Divider()

            SettingsRow(
                title: "Send preview",
                subtitle: "The notification is delivered locally and does not affect monitored repository state."
            ) {
                VStack(alignment: .trailing, spacing: 8) {
                    Button("Send Test Notification") {
                        model.requestNotificationDebugPreview()
                    }
                    .disabled(preview.isSending || !model.canSendNotificationDebugPreview)

                    if let deliveryMessage = preview.deliveryMessage {
                        Text(deliveryMessage)
                            .font(.caption)
                            .foregroundStyle(preview.deliveryState.isFailure ? .red : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 320, alignment: .trailing)
                    }
                }
            }
        } footer: {
            Text("Debug previews are available in Debug builds only.")
        }
    }

    @ViewBuilder
    private var triggerSpecificFields: some View {
        switch preview.selectedTrigger {
        case .pullRequestCreated:
            SettingsRow(
                title: "PR author",
                subtitle: "Shown in the created-PR notification body."
            ) {
                TextField("octocat", text: $preview.authorLogin)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
            }
        case .approval, .changesRequested:
            SettingsTextBlock(
                title: "No extra fields",
                bodyText: "This notification uses the shared repository and pull request fields only."
            )
        case .newUnresolvedReviewComment:
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "Comment author",
                    subtitle: "Optional reviewer login shown before the comment body."
                ) {
                    TextField("reviewer", text: $preview.commentAuthorLogin)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Divider()

                SettingsRow(
                    title: "Comment body",
                    subtitle: "The notification body falls back to the PR title only when no comment body is present in production."
                ) {
                    TextField("Comment body", text: $preview.commentBodyText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                        .frame(width: 320)
                }
            }
        case .workflowRunCompleted:
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "Workflow name",
                    subtitle: "Used in the notification title."
                ) {
                    TextField("CI", text: $preview.workflowName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Divider()

                SettingsRow(
                    title: "Conclusion",
                    subtitle: "Optional workflow result shown in the body."
                ) {
                    TextField("success", text: $preview.workflowConclusion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }
        case .workflowJobCompleted:
            VStack(alignment: .leading, spacing: 0) {
                SettingsRow(
                    title: "Workflow name",
                    subtitle: "Available for the synthetic event even though the current formatter shows the repository name in the title."
                ) {
                    TextField("CI", text: $preview.workflowName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Divider()

                SettingsRow(
                    title: "Job name",
                    subtitle: "Shown in the workflow job notification body."
                ) {
                    TextField("unit-tests", text: $preview.workflowJobName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }

                Divider()

                SettingsRow(
                    title: "Job result",
                    subtitle: "Use `success` for the success icon. Other values preview the failure path."
                ) {
                    TextField("success", text: $preview.workflowJobConclusion)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
            }
        }
    }
}

private struct NotificationDebugPreviewCard: View {
    let preview: NotificationDebugPreviewModel

    var body: some View {
        let previewContent = makePreviewContent()

        VStack(alignment: .leading, spacing: 6) {
            Text(previewContent.title)
                .font(.headline)

            Text(previewContent.body)
                .font(.caption)
                .foregroundStyle(previewContent.isFailure ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func makePreviewContent() -> (title: String, body: String, isFailure: Bool) {
        do {
            let event = try preview.makeEvent()
            return (
                title: LocalNotificationContentFormatter.title(for: event),
                body: LocalNotificationContentFormatter.body(for: event),
                isFailure: false
            )
        } catch {
            return (
                title: "Invalid preview input",
                body: error.localizedDescription,
                isFailure: true
            )
        }
    }
}

private extension RepositoryNotificationTrigger {
    var debugPreviewTitle: String {
        switch self {
        case .pullRequestCreated:
            return "PR created"
        case .approval:
            return "PR approved"
        case .changesRequested:
            return "Changes requested"
        case .newUnresolvedReviewComment:
            return "New review comment"
        case .workflowRunCompleted:
            return "Workflow run completed"
        case .workflowJobCompleted:
            return "Workflow job completed"
        }
    }
}
#endif
