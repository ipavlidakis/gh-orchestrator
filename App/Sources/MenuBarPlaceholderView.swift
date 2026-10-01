import AppKit
import GHOrchestratorCore
import SwiftUI

@MainActor
struct MenuBarMoreMenuActionHandler {
    let refreshAction: () -> Void
    let installUpdateAction: () -> Void
    let openSettingsAction: () -> Void
    let quitAction: () -> Void
    
    func refresh() {
        refreshAction()
    }
    
    func installUpdate() {
        installUpdateAction()
    }
    
    func openSettings() {
        openSettingsAction()
    }
    
    func quit() {
        quitAction()
    }
}

@MainActor
struct MenuBarMoreMenuUpdateAction: Equatable {
    let title: String
    let isEnabled: Bool

    init?(softwareUpdateModel: SoftwareUpdateModel) {
        switch softwareUpdateModel.state {
        case .updateAvailable:
            self.title = "Update"
            self.isEnabled = softwareUpdateModel.canInstallUpdate
        case .installing:
            self.title = "Updating..."
            self.isEnabled = false
        case .idle, .checking, .upToDate, .failed:
            return nil
        }
    }
}

struct MenuBarPlaceholderView: View {
    let model: MenuBarDashboardModel
    @Bindable var softwareUpdateModel: SoftwareUpdateModel
    let openSettingsAction: @MainActor () -> Void
    let openURLAction: @MainActor (URL) -> Void
    let onMenuVisibilityChange: (Bool) -> Void
    
    var body: some View {
        if #available(macOS 26, *) {
            dashboardContent.buttonStyle(.glass)
        } else {
            dashboardContent
        }
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerActions
            Divider()
            content
        }
        .padding(14)
        .frame(width: 440, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .task {
            onMenuVisibilityChange(true)
        }
        .onDisappear {
            onMenuVisibilityChange(false)
        }
    }
    
    private var headerActions: some View {
        VStack {
            HStack(spacing: 8) {
                Text(AppMetadata.menuBarTitle)
                    .font(.headline)
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.9)
                }
                Spacer()
                
                Menu {
                    Picker("Pull request order", selection: Binding(
                        get: { model.settingsStore.settings.pullRequestSortOrder },
                        set: { model.settingsStore.settings.pullRequestSortOrder = $0 }
                    )) {
                        ForEach(PullRequestSortOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort pull requests within each repository")

                Menu {
                    Button {
                        moreMenuActionHandler.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                    
                    if let updateAction {
                        Button {
                            moreMenuActionHandler.installUpdate()
                        } label: {
                            Label(updateAction.title, systemImage: "arrow.down.circle")
                        }
                        .disabled(!updateAction.isEnabled)
                    }
                    
                    Button {
                        moreMenuActionHandler.openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    
                    Divider()
                    
                    Button {
                        moreMenuActionHandler.quit()
                    } label: {
                        Label("Quit", systemImage: "power")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("More actions")
                .help("More")
            }
            
            if showsDashboardFilters {
                filterControls
                    .disabled(model.areDashboardFiltersDisabled)
                    .help(model.areDashboardFiltersDisabled ? "Filters are disabled while the current refresh error is visible." : "")
            }
            
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
            .frame(width: 144)
            
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
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .controlSize(.regular)
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
    
    private var updateAction: MenuBarMoreMenuUpdateAction? {
        MenuBarMoreMenuUpdateAction(softwareUpdateModel: softwareUpdateModel)
    }
    
    private var moreMenuActionHandler: MenuBarMoreMenuActionHandler {
        MenuBarMoreMenuActionHandler(
            refreshAction: {
                model.refresh()
            },
            installUpdateAction: {
                softwareUpdateModel.requestInstallUpdate()
            },
            openSettingsAction: openSettingsWindow,
            quitAction: {
                NSApplication.shared.terminate(nil)
            }
        )
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
                LazyVStack(alignment: .leading, spacing: 12) {
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
                            onOpenURL: openURLAction
                        )
                    }
                }
            }
            .frame(maxHeight: 520)
        }
    }
    
    private func openSettingsWindow() {
        openSettingsAction()
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
        DisclosureGroup(isExpanded: Binding(get: { !isCollapsed }, set: { expanded in
            if expanded != !isCollapsed { onToggleCollapsed() }
        })) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(section.pullRequests) { pullRequest in
                    if pullRequest.id != section.pullRequests.first?.id {
                        Divider()
                    }

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
        } label: {
            LabeledContent(section.repository.fullName) {
                Text(section.pullRequests.count, format: .number)
            }
            .font(.headline)
        }
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
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.link)
                
                Text(pullRequestMetadataText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack {
                    Label(pullRequest.isDraft ? "Draft" : "Ready", systemImage: pullRequest.isDraft ? "pencil" : "checkmark")
                    Label(reviewLabel(for: pullRequest.reviewStatus), systemImage: reviewSymbol(for: pullRequest.reviewStatus))
                }
                .font(.caption)

                checksDisclosure
                commentsDisclosure
            }
        }
        .padding(.leading, 2)
    }
    
    @ViewBuilder
    private var checksDisclosure: some View {
        if hasExpandableChecks {
            DisclosureGroup(isExpanded: Binding(get: { isChecksExpanded }, set: { expanded in
                if expanded != isChecksExpanded { onToggleChecks() }
            })) {
                ExpandedPullRequestDetailsView(
                    pullRequest: pullRequest,
                    isRetryingJob: isRetryingJob,
                    retryErrorMessage: retryErrorMessage,
                    onRetryWorkflowJob: onRetryWorkflowJob,
                    onOpenURL: onOpenURL
                )
            } label: {
                Label(checksLabel(for: pullRequest.checkRollupState), systemImage: checksSymbol(for: pullRequest.checkRollupState))
            }
        } else {
            Label(checksLabel(for: pullRequest.checkRollupState), systemImage: checksSymbol(for: pullRequest.checkRollupState))
        }
    }
    
    @ViewBuilder
    private var commentsDisclosure: some View {
        if hasExpandableComments {
            DisclosureGroup(isExpanded: Binding(get: { isCommentsExpanded }, set: { expanded in
                if expanded != isCommentsExpanded { onToggleComments() }
            })) {
                ExpandedUnresolvedCommentsView(
                    comments: pullRequest.unresolvedReviewComments,
                    onOpenURL: onOpenURL
                )
            } label: {
                Label(commentsLabel(), systemImage: "text.bubble")
            }
        } else {
            Label(commentsLabel(), systemImage: "text.bubble")
                .foregroundStyle(.secondary)
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
    
    private func reviewSymbol(for status: ReviewStatus) -> String {
        switch status {
        case .approved:
            return "checkmark.circle"
        case .changesRequested:
            return "exclamationmark.bubble"
        case .reviewRequired:
            return "person.crop.circle.badge.clock"
        case .none:
            return "person.crop.circle"
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
    
    private func checksSymbol(for state: CheckRollupState) -> String {
        switch state {
        case .passing:
            return "checkmark.circle"
        case .failing:
            return "xmark.circle"
        case .pending:
            return "clock"
        case .none:
            return "minus.circle"
        }
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
                                .buttonStyle(.link)
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
                        .buttonStyle(.link)
                        .disabled(check.detailsURL == nil)
                    }
                }
            }
        }
        .padding(.top, 4)
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
                Image(systemName: jobStatusIcon)
                    .foregroundStyle(jobStatusColor)

                Button {
                    if let url = job.detailsURL {
                        onOpenURL(url)
                    }
                } label: {
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
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.link)
                .disabled(job.detailsURL == nil)
            }
            
            if !job.steps.isEmpty {
                DisclosureGroup("\(job.steps.count) steps", isExpanded: $isStepsExpanded) {
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
                                            .controlSize(.small)
                                            .font(.caption2.weight(.medium))
                                            .help("Re-run this job in GitHub Actions")
                                    }
                                }
                            }
                        }
                    }
                }
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
        if job.conclusion?.lowercased() == "skipped" {
            return "minus.circle.fill"
        }

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
        if job.conclusion?.lowercased() == "skipped" {
            return .secondary
        }

        if firstFailedStep != nil || (job.conclusion?.lowercased() != nil && job.conclusion?.lowercased() != "success") {
            return .red
        }
        
        if job.status.lowercased() != "completed" {
            return .orange
        }
        
        return .green
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
            .buttonStyle(.link)
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
        if step.conclusion?.lowercased() == "skipped" {
            return "minus.circle.fill"
        }

        if stepConclusionIsFailure(step) {
            return "xmark.circle.fill"
        }
        
        if stepStatusIsPending(step) {
            return "clock.fill"
        }
        
        return "checkmark.circle.fill"
    }
    
    private func stepStatusColor(for step: ActionStepItem) -> Color {
        if step.conclusion?.lowercased() == "skipped" {
            return .secondary
        }

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
                        
                    }
                }
                .buttonStyle(.link)
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
