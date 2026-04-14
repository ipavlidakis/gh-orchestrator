import AppKit
import GHOrchestratorCore
import SwiftUI

struct MenuBarPlaceholderView: View {
    let model: MenuBarDashboardModel

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

    private func openSettings() {
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
                    text: checksLabel(for: pullRequest.checkRollupState, isExpanded: isChecksExpanded),
                    tone: checksTone(for: pullRequest.checkRollupState)
                )
            }
            .buttonStyle(.plain)
        } else {
            MetadataBadge(
                text: checksLabel(for: pullRequest.checkRollupState, isExpanded: false),
                tone: checksTone(for: pullRequest.checkRollupState)
            )
        }
    }

    @ViewBuilder
    private var commentsBadge: some View {
        if hasExpandableComments {
            Button(action: onToggleComments) {
                MetadataBadge(
                    text: commentsLabel(isExpanded: isCommentsExpanded),
                    tone: pullRequest.unresolvedReviewThreadCount == 0 ? .secondary : .warning
                )
            }
            .buttonStyle(.plain)
        } else {
            MetadataBadge(
                text: commentsLabel(isExpanded: false),
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

    private func checksLabel(for state: CheckRollupState, isExpanded: Bool) -> String {
        let label = switch state {
        case .none:
            "No checks"
        case .pending:
            "Checks pending"
        case .passing:
            "Checks passing"
        case .failing:
            "Checks failing"
        }

        return label + (hasExpandableChecks ? (isExpanded ? "  ^" : "  v") : "")
    }

    private func commentsLabel(isExpanded: Bool) -> String {
        let label = "\(pullRequest.unresolvedReviewThreadCount) unresolved"
        return label + (hasExpandableComments ? (isExpanded ? "  ^" : "  v") : "")
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
                                Button {
                                    if let url = job.detailsURL {
                                        onOpenURL(url)
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: jobStatusIcon(for: job))
                                            .foregroundStyle(jobStatusColor(for: job))

                                        Text(jobSummary(for: job))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.plain)
                                .padding(.leading, 14)
                                .disabled(job.detailsURL == nil)
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

    var body: some View {
        Text(text)
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
