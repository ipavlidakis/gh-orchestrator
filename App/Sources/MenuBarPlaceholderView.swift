import AppKit
import GHOrchestratorCore
import SwiftUI

struct MenuBarPlaceholderView: View {
    let model: MenuBarDashboardModel
    let onMenuVisibilityChange: (Bool) -> Void
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
            onMenuVisibilityChange(true)
        }
        .onDisappear {
            onMenuVisibilityChange(false)
        }
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Text(AppMetadata.menuBarTitle)
                .font(.headline)

            Spacer(minLength: 0)

            if showsDashboardFilters {
                filterControls
                    .disabled(model.areDashboardFiltersDisabled)
                    .help(model.areDashboardFiltersDisabled ? "Filters are disabled while the current refresh error is visible." : "")
            }

            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }

            Menu {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

                Button {
                    openSettingsWindow()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }

                Divider()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .help("More")
        }
    }

    private var filterControls: some View {
        HStack(spacing: 4) {
            Picker(
                "Pull requests",
                selection: Binding(
                    get: { model.pullRequestScope },
                    set: { model.setPullRequestScope($0) }
                )
            ) {
                Text("My PRs").tag(PullRequestScope.mine)
                Text("All PRs").tag(PullRequestScope.all)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 112)

            Menu {
                repositoryFocusButton(
                    title: "All repositories",
                    repositoryID: nil
                )

                Divider()

                ForEach(model.settingsStore.settings.observedRepositories) { repository in
                    repositoryFocusButton(
                        title: repository.fullName,
                        repositoryID: repository.normalizedLookupKey
                    )
                }
            } label: {
                Label(repositoryFocusTitle, systemImage: "line.3.horizontal.decrease.circle")
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 118, alignment: .leading)
        }
        .controlSize(.small)
    }

    private var showsDashboardFilters: Bool {
        guard case .authenticated = model.authenticationState else {
            return false
        }

        return !model.settingsStore.settings.observedRepositories.isEmpty
    }

    private var repositoryFocusTitle: String {
        guard let focusedRepositoryID = model.focusedRepositoryID,
              let repository = model.settingsStore.settings.observedRepositories.first(where: {
                  $0.normalizedLookupKey == focusedRepositoryID
              })
        else {
            return "All repositories"
        }

        return repository.fullName
    }

    @ViewBuilder
    private func repositoryFocusButton(
        title: String,
        repositoryID: String?
    ) -> some View {
        let isSelected = model.focusedRepositoryID == repositoryID

        Button {
            model.setFocusedRepositoryID(repositoryID)
        } label: {
            if isSelected {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsStaleContentWarning, let message = model.refreshWarningMessage {
                RefreshWarningBanner(message: message)
            }

            contentBody
        }
    }

    private var showsStaleContentWarning: Bool {
        switch model.contentState {
        case .loaded, .empty:
            return true
        case .idle,
             .loading,
             .notConfigured,
             .signedOut,
             .authorizing,
             .noRepositoriesConfigured,
             .authFailure(_),
             .commandFailure(_):
            return false
        }
    }

    @ViewBuilder
    private var contentBody: some View {
        switch model.contentState {
        case .idle, .loading:
            EmptyView()

        case .notConfigured:
            StateMessageView(
                title: "GitHub not configured",
                message: "This build is missing a GitHub OAuth client ID. Open Settings for configuration details."
            )

        case .signedOut:
            StateMessageView(
                title: "Sign in with GitHub",
                message: "Open Settings and start the GitHub sign-in flow to load your pull requests."
            )

        case .authorizing:
            StateMessageView(
                title: "Finishing sign-in",
                message: "Open Settings to view the GitHub device code, then approve it in your browser. The dashboard will refresh automatically when GitHub authorizes this Mac."
            )

        case .empty:
            StateMessageView(
                title: "No open pull requests",
                message: "No matching pull requests were found in the configured repositories."
            )

        case .noRepositoriesConfigured:
            StateMessageView(
                title: "Configure repositories",
                message: "Add one or more `owner/repo` entries in Settings to populate the dashboard."
            )

        case .authFailure(let message):
            StateMessageView(
                title: "Authentication failed",
                message: message
            )

        case .commandFailure(let message):
            RefreshFailureStateView(message: message)

        case .loaded(let sections):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        RepositorySectionView(
                            section: section,
                            showsAuthor: model.pullRequestScope == .all,
                            isCollapsed: model.collapsedRepositoryIDs.contains(section.repository.normalizedLookupKey),
                            expandedChecksIDs: model.expandedChecksPullRequestIDs,
                            expandedCommentIDs: model.expandedCommentPullRequestIDs,
                            onToggleCollapsed: {
                                model.toggleRepositoryCollapsed(
                                    repositoryID: section.repository.normalizedLookupKey
                                )
                            },
                            onToggleChecks: { pullRequestID in
                                model.toggleChecksExpansion(for: pullRequestID)
                            },
                            onToggleComments: { pullRequestID in
                                model.toggleCommentsExpansion(for: pullRequestID)
                            },
                            isRetryingJob: { jobID in
                                model.isRetryingJob(jobID)
                            },
                            retryErrorMessage: { jobID in
                                model.retryErrorMessage(for: jobID)
                            },
                            onRetryWorkflowJob: { repository, jobID in
                                model.retryWorkflowJob(
                                    repository: repository,
                                    jobID: jobID
                                )
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

    private func openSettingsWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openSettings()

        Task { @MainActor in
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

private struct RefreshWarningBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text("Refresh failed")
                    .font(.caption.weight(.semibold))

                Text("Showing the last loaded dashboard state. \(message)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct RefreshFailureStateView: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .imageScale(.small)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Refresh failed")
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("No previously loaded results are available yet. Try again after GitHub allows requests for this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
}

private struct RepositorySectionView: View {
    let section: RepositorySection
    let showsAuthor: Bool
    let isCollapsed: Bool
    let expandedChecksIDs: Set<String>
    let expandedCommentIDs: Set<String>
    let onToggleCollapsed: () -> Void
    let onToggleChecks: (String) -> Void
    let onToggleComments: (String) -> Void
    let isRetryingJob: (Int) -> Bool
    let retryErrorMessage: (Int) -> String?
    let onRetryWorkflowJob: (ObservedRepository, Int) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggleCollapsed) {
                HStack(spacing: 6) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(section.repository.fullName)
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Text("\(section.pullRequests.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                ForEach(section.pullRequests) { pullRequest in
                    PullRequestRowView(
                        pullRequest: pullRequest,
                        showsAuthor: showsAuthor,
                        isChecksExpanded: expandedChecksIDs.contains(pullRequest.id),
                        isCommentsExpanded: expandedCommentIDs.contains(pullRequest.id),
                        onToggleChecks: {
                            onToggleChecks(pullRequest.id)
                        },
                        onToggleComments: {
                            onToggleComments(pullRequest.id)
                        },
                        isRetryingJob: isRetryingJob,
                        retryErrorMessage: retryErrorMessage,
                        onRetryWorkflowJob: onRetryWorkflowJob,
                        onOpenURL: onOpenURL
                    )
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct PullRequestRowView: View {
    let pullRequest: PullRequestItem
    let showsAuthor: Bool
    let isChecksExpanded: Bool
    let isCommentsExpanded: Bool
    let onToggleChecks: () -> Void
    let onToggleComments: () -> Void
    let isRetryingJob: (Int) -> Bool
    let retryErrorMessage: (Int) -> String?
    let onRetryWorkflowJob: (ObservedRepository, Int) -> Void
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

                Text(pullRequestMetadataText)
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
                        isRetryingJob: isRetryingJob,
                        retryErrorMessage: retryErrorMessage,
                        onRetryWorkflowJob: onRetryWorkflowJob,
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

    private var pullRequestMetadataText: String {
        var components = ["#\(pullRequest.number)"]

        if showsAuthor,
           let authorLogin = pullRequest.authorLogin?.trimmingCharacters(in: .whitespacesAndNewlines),
           !authorLogin.isEmpty {
            components.append("by @\(authorLogin)")
        }

        components.append(relativeUpdatedText(for: pullRequest.updatedAt))
        return components.joined(separator: " · ")
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
    let isRetryingJob: (Int) -> Bool
    let retryErrorMessage: (Int) -> String?
    let onRetryWorkflowJob: (ObservedRepository, Int) -> Void
    let onOpenURL: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !pullRequest.workflowRuns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    TimelineView(.periodic(from: .now, by: 60)) { context in
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

                                Text(workflowRunMetadataText(for: workflowRun, now: context.date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                ForEach(workflowRun.jobs, id: \.id) { job in
                                    WorkflowJobView(
                                        job: job,
                                        now: context.date,
                                        isRetrying: isRetryingJob(job.id),
                                        retryErrorMessage: retryErrorMessage(job.id),
                                        onRetryWorkflowJob: {
                                            onRetryWorkflowJob(
                                                pullRequest.repository,
                                                job.id
                                            )
                                        },
                                        onOpenURL: onOpenURL
                                    )
                                }
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

    private func workflowRunMetadataText(for workflowRun: WorkflowRunItem, now: Date) -> String {
        var components = [
            workflowRun.status.lowercased()
        ]

        if let conclusion = workflowRun.conclusion?.lowercased() {
            components.append(conclusion)
        }

        if let durationText = ActionsDurationLabelFormatter().workflowDurationText(for: workflowRun, now: now) {
            components.append(durationText)
        }

        return components.joined(separator: " · ")
    }
}

private struct WorkflowJobView: View {
    let job: ActionJobItem
    let now: Date
    let isRetrying: Bool
    let retryErrorMessage: String?
    let onRetryWorkflowJob: () -> Void
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

                        VStack(alignment: .leading, spacing: 2) {
                            Text(jobSummary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            if let jobMetadataText {
                                Text(jobMetadataText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
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
                        HStack(alignment: .top, spacing: 8) {
                            stepContent(for: step)

                            if stepConclusionIsFailure(step) {
                                if isRetrying {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button("Retry job", action: onRetryWorkflowJob)
                                        .buttonStyle(.borderless)
                                        .font(.caption2.weight(.medium))
                                        .help("Re-run this job in GitHub Actions")
                                }
                            }
                        }
                    }
                }
                .padding(.leading, 18)
            }

            if let retryErrorMessage, !retryErrorMessage.isEmpty {
                Text(retryErrorMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
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

    private var jobMetadataText: String? {
        ActionsDurationLabelFormatter().jobDurationText(for: job, now: now)
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
        var components: [String] = []
        let durationText = ActionsDurationLabelFormatter().stepDurationText(for: step, now: now)

        if let conclusion = step.conclusion?.lowercased() {
            if durationText == nil {
                components.append(step.status.lowercased())
            }

            components.append(conclusion)
        }

        if let durationText {
            components.append(durationText)
        }

        if components.isEmpty {
            components.append(step.status.lowercased())
        }

        return components.joined(separator: " · ")
    }

    @ViewBuilder
    private func stepContent(for step: ActionStepItem) -> some View {
        if let url = step.detailsURL {
            Button {
                onOpenURL(url)
            } label: {
                stepLabel(for: step)
            }
            .buttonStyle(.plain)
        } else {
            stepLabel(for: step)
        }
    }

    private func stepLabel(for step: ActionStepItem) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
