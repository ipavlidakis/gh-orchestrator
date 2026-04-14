import AppKit
import GHOrchestratorCore
import SwiftUI

struct MenuBarPlaceholderView: View {
    let model: MenuBarDashboardModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerActions
            Divider()
            content
        }
        .padding(14)
        .frame(width: 440, alignment: .leading)
        .task {
            model.setMenuVisible(true)
        }
        .onDisappear {
            model.setMenuVisible(false)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 10) {
            Text(AppMetadata.menuBarTitle)
                .font(.headline)

            Spacer()

            Group {
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Refresh") {
                        model.refresh()
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button("Settings") {
                openSettings()
            }
            .buttonStyle(.borderless)

            Button("Quit", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.contentState {
        case .idle, .loading:
            EmptyView()

        case .empty:
            StateMessageView(
                title: "No open pull requests",
                message: "No matching pull requests were found in the configured repositories."
            )

        case .ghMissing:
            StateMessageView(
                title: "Install GitHub CLI",
                message: "Open Settings to see the exact setup commands before loading the dashboard."
            )

        case .loggedOut:
            StateMessageView(
                title: "Sign in with gh",
                message: "Open Settings and run `gh auth login` to let the app fetch GitHub data."
            )

        case .noRepositoriesConfigured:
            StateMessageView(
                title: "Configure repositories",
                message: "Add one or more `owner/repo` entries in Settings to populate the dashboard."
            )

        case .commandFailure(let message):
            StateMessageView(
                title: "Refresh failed",
                message: message
            )

        case .loaded(let sections):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        RepositorySectionView(
                            section: section,
                            expandedChecksIDs: model.expandedChecksPullRequestIDs,
                            expandedCommentIDs: model.expandedCommentPullRequestIDs,
                            onToggleChecks: { pullRequestID in
                                model.toggleChecksExpansion(for: pullRequestID)
                            },
                            onToggleComments: { pullRequestID in
                                model.toggleCommentsExpansion(for: pullRequestID)
                            },
                            onOpenURL: openURL
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 520)
        }
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

private struct RepositorySectionView: View {
    let section: RepositorySection
    let expandedChecksIDs: Set<String>
    let expandedCommentIDs: Set<String>
    let onToggleChecks: (String) -> Void
    let onToggleComments: (String) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(section.repository.fullName)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(section.pullRequests.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(section.pullRequests) { pullRequest in
                PullRequestRowView(
                    pullRequest: pullRequest,
                    isChecksExpanded: expandedChecksIDs.contains(pullRequest.id),
                    isCommentsExpanded: expandedCommentIDs.contains(pullRequest.id),
                    onToggleChecks: {
                        onToggleChecks(pullRequest.id)
                    },
                    onToggleComments: {
                        onToggleComments(pullRequest.id)
                    },
                    onOpenURL: onOpenURL
                )
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PullRequestRowView: View {
    let pullRequest: PullRequestItem
    let isChecksExpanded: Bool
    let isCommentsExpanded: Bool
    let onToggleChecks: () -> Void
    let onToggleComments: () -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    onOpenURL(pullRequest.url)
                } label: {
                    Text(pullRequest.title)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Text("#\(pullRequest.number) · \(relativeUpdatedText(for: pullRequest.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        MetadataBadge(text: pullRequest.isDraft ? "Draft" : "Ready", tone: pullRequest.isDraft ? .secondary : .accent)
                        MetadataBadge(text: reviewLabel(for: pullRequest.reviewStatus), tone: reviewTone(for: pullRequest.reviewStatus))
                        checksBadge
                        commentsBadge
                    }
                }
                .scrollDisabled(true)

                if isCommentsExpanded {
                    ExpandedUnresolvedCommentsView(
                        comments: pullRequest.unresolvedReviewComments,
                        onOpenURL: onOpenURL
                    )
                }

                if isChecksExpanded {
                    ExpandedPullRequestDetailsView(
                        pullRequest: pullRequest,
                        onOpenURL: onOpenURL
                    )
                }
            }
        }
        .padding(.leading, 2)
    }

    @ViewBuilder
    private var checksBadge: some View {
        if hasExpandableChecks {
            Button(action: onToggleChecks) {
                MetadataBadge(
                    text: checksLabel(for: pullRequest.checkRollupState),
                    tone: checksTone(for: pullRequest.checkRollupState),
                    systemImage: disclosureChevronName(isExpanded: isChecksExpanded)
                )
            }
            .buttonStyle(.plain)
        } else {
            MetadataBadge(
                text: checksLabel(for: pullRequest.checkRollupState),
                tone: checksTone(for: pullRequest.checkRollupState)
            )
        }
    }

    @ViewBuilder
    private var commentsBadge: some View {
        if hasExpandableComments {
            Button(action: onToggleComments) {
                MetadataBadge(
                    text: commentsLabel(),
                    tone: pullRequest.unresolvedReviewThreadCount == 0 ? .secondary : .warning,
                    systemImage: disclosureChevronName(isExpanded: isCommentsExpanded)
                )
            }
            .buttonStyle(.plain)
        } else {
            MetadataBadge(
                text: commentsLabel(),
                tone: pullRequest.unresolvedReviewThreadCount == 0 ? .secondary : .warning
            )
        }
    }

    private var hasExpandableChecks: Bool {
        !pullRequest.workflowRuns.isEmpty || !pullRequest.externalChecks.isEmpty
    }

    private var hasExpandableComments: Bool {
        !pullRequest.unresolvedReviewComments.isEmpty
    }

    private func relativeUpdatedText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: date, relativeTo: .now))"
    }

    private func reviewLabel(for status: ReviewStatus) -> String {
        switch status {
        case .none:
            return "No reviews"
        case .reviewRequired:
            return "Review required"
        case .approved:
            return "Approved"
        case .changesRequested:
            return "Changes requested"
        }
    }

    private func reviewTone(for status: ReviewStatus) -> MetadataBadge.Tone {
        switch status {
        case .approved:
            return .success
        case .changesRequested:
            return .danger
        case .reviewRequired:
            return .warning
        case .none:
            return .secondary
        }
    }

    private func checksLabel(for state: CheckRollupState) -> String {
        switch state {
        case .none:
            "No checks"
        case .pending:
            "Checks pending"
        case .passing:
            "Checks passing"
        case .failing:
            "Checks failing"
        }
    }

    private func commentsLabel() -> String {
        "\(pullRequest.unresolvedReviewThreadCount) unresolved"
    }

    private func checksTone(for state: CheckRollupState) -> MetadataBadge.Tone {
        switch state {
        case .passing:
            return .success
        case .failing:
            return .danger
        case .pending:
            return .warning
        case .none:
            return .secondary
        }
    }

    private func disclosureChevronName(isExpanded: Bool) -> String {
        isExpanded ? "chevron.down" : "chevron.right"
    }
}

private struct ExpandedPullRequestDetailsView: View {
    let pullRequest: PullRequestItem
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pullRequest.workflowRuns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(pullRequest.workflowRuns, id: \.id) { workflowRun in
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                if let url = workflowRun.detailsURL {
                                    onOpenURL(url)
                                }
                            } label: {
                                Label(workflowRun.name, systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(workflowRun.detailsURL == nil)

                            Text("\(workflowRun.status.lowercased())\(workflowRun.conclusion.map { " · \($0.lowercased())" } ?? "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(workflowRun.jobs, id: \.id) { job in
                                WorkflowJobView(
                                    job: job,
                                    onOpenURL: onOpenURL
                                )
                            }
                        }
                    }
                }
            }

            if !pullRequest.externalChecks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Other checks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(pullRequest.externalChecks.enumerated()), id: \.offset) { _, check in
                        Button {
                            if let url = check.detailsURL {
                                onOpenURL(url)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text("\(check.status.lowercased())\(check.conclusion.map { " · \($0.lowercased())" } ?? "")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)

                                if let summary = check.summary, !summary.isEmpty {
                                    Text(summary)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(check.detailsURL == nil)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private func jobSummary(for job: ActionJobItem) -> String {
        if let failedStep = firstFailedStep(in: job) {
            return "\(job.name) · Failed on \(failedStep.name)"
        }

        if let conclusion = job.conclusion?.lowercased(), conclusion != "success" {
            return "\(job.name) · \(conclusion)"
        }

        if job.status.lowercased() != "completed" {
            return "\(job.name) · \(job.status.lowercased())"
        }

        return job.name
    }

    private func firstFailedStep(in job: ActionJobItem) -> ActionStepItem? {
        job.steps.first { step in
            guard let conclusion = step.conclusion?.lowercased() else {
                return false
            }

            return conclusion != "success" && conclusion != "skipped"
        }
    }

    private func jobStatusIcon(for job: ActionJobItem) -> String {
        if firstFailedStep(in: job) != nil || (job.conclusion?.lowercased() != nil && job.conclusion?.lowercased() != "success") {
            return "xmark.circle.fill"
        }

        if job.status.lowercased() != "completed" {
            return "clock.fill"
        }

        return "checkmark.circle.fill"
    }

    private func jobStatusColor(for job: ActionJobItem) -> Color {
        if firstFailedStep(in: job) != nil || (job.conclusion?.lowercased() != nil && job.conclusion?.lowercased() != "success") {
            return .red
        }

        if job.status.lowercased() != "completed" {
            return .orange
        }

        return .green
    }
}

private struct WorkflowJobView: View {
    let job: ActionJobItem
    let onOpenURL: (URL) -> Void

    @State private var isStepsExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    if let url = job.detailsURL {
                        onOpenURL(url)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: jobStatusIcon)
                            .foregroundStyle(jobStatusColor)

                        Text(jobSummary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(job.detailsURL == nil)

                if hasExpandableSteps {
                    Button {
                        isStepsExpanded.toggle()
                    } label: {
                        MetadataBadge(
                            text: stepsToggleLabel,
                            tone: .secondary,
                            systemImage: disclosureChevronName
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if isStepsExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(job.steps, id: \.number) { step in
                        Button {
                            if let url = step.detailsURL {
                                onOpenURL(url)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: stepStatusIcon(for: step))
                                    .foregroundStyle(stepStatusColor(for: step))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Step \(step.number): \(step.name)")
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(stepSummary(for: step))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .disabled(step.detailsURL == nil)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.leading, 14)
    }

    private var hasExpandableSteps: Bool {
        !job.steps.isEmpty
    }

    private var stepsToggleLabel: String {
        "\(job.steps.count) steps"
    }

    private var jobSummary: String {
        if let failedStep = firstFailedStep {
            return "\(job.name) · Failed on \(failedStep.name)"
        }

        if let conclusion = job.conclusion?.lowercased(), conclusion != "success" {
            return "\(job.name) · \(conclusion)"
        }

        if job.status.lowercased() != "completed" {
            return "\(job.name) · \(job.status.lowercased())"
        }

        return job.name
    }

    private var firstFailedStep: ActionStepItem? {
        job.steps.first { step in
            guard let conclusion = step.conclusion?.lowercased() else {
                return false
            }

            return conclusion != "success" && conclusion != "skipped"
        }
    }

    private var jobStatusIcon: String {
        if firstFailedStep != nil || (job.conclusion?.lowercased() != nil && job.conclusion?.lowercased() != "success") {
            return "xmark.circle.fill"
        }

        if job.status.lowercased() != "completed" {
            return "clock.fill"
        }

        return "checkmark.circle.fill"
    }

    private var jobStatusColor: Color {
        if firstFailedStep != nil || (job.conclusion?.lowercased() != nil && job.conclusion?.lowercased() != "success") {
            return .red
        }

        if job.status.lowercased() != "completed" {
            return .orange
        }

        return .green
    }

    private var disclosureChevronName: String {
        isStepsExpanded ? "chevron.down" : "chevron.right"
    }

    private func stepSummary(for step: ActionStepItem) -> String {
        if let conclusion = step.conclusion?.lowercased() {
            return "\(step.status.lowercased()) · \(conclusion)"
        }

        return step.status.lowercased()
    }

    private func stepStatusIcon(for step: ActionStepItem) -> String {
        if stepConclusionIsFailure(step) {
            return "xmark.circle.fill"
        }

        if stepStatusIsPending(step) {
            return "clock.fill"
        }

        return "checkmark.circle.fill"
    }

    private func stepStatusColor(for step: ActionStepItem) -> Color {
        if stepConclusionIsFailure(step) {
            return .red
        }

        if stepStatusIsPending(step) {
            return .orange
        }

        return .green
    }

    private func stepConclusionIsFailure(_ step: ActionStepItem) -> Bool {
        guard let conclusion = step.conclusion?.lowercased() else {
            return false
        }

        return conclusion != "success" && conclusion != "skipped"
    }

    private func stepStatusIsPending(_ step: ActionStepItem) -> Bool {
        let status = step.status.lowercased()
        return status != "completed"
    }
}

private struct ExpandedUnresolvedCommentsView: View {
    let comments: [UnresolvedReviewCommentItem]
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unresolved comments")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(comments) { comment in
                Button {
                    onOpenURL(comment.url)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(comment.authorLogin)
                                    .font(.caption.weight(.semibold))

                                Text(comment.filePath)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Text(comment.bodyText)
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(4)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 14)
            }
        }
    }
}

private struct StateMessageView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

private struct MetadataBadge: View {
    enum Tone {
        case accent
        case success
        case warning
        case danger
        case secondary
    }

    let text: String
    let tone: Tone
    let systemImage: String?

    init(text: String, tone: Tone, systemImage: String? = nil) {
        self.text = text
        self.tone = tone
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(text)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
        }
        .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor.opacity(0.12), in: Capsule())
            .foregroundStyle(backgroundColor)
    }

    private var backgroundColor: Color {
        switch tone {
        case .accent:
            return .accentColor
        case .success:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        case .secondary:
            return .secondary
        }
    }
}
