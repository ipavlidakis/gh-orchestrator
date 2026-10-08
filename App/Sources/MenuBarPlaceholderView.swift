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
    var requestLogModel: GitHubRequestLogModel?
    /// Tallest the popover may grow; the dashboard reports its natural height up to this limit.
    var maximumHeight: CGFloat = 620
    var onPreferredHeightChange: (CGFloat) -> Void = { _ in }
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

    @State private var headerHeight: CGFloat = 100
    @State private var scrollContentHeight: CGFloat = 0

    private static let footerHeight: CGFloat = 39
    private static let contentTopPadding: CGFloat = 12

    /// The list shrinks to its content, and scrolls only once the popover reaches its maximum height.
    private var scrollViewHeight: CGFloat {
        let available = maximumHeight - headerHeight - 1 - Self.contentTopPadding - Self.footerHeight
        return min(max(scrollContentHeight, 1), max(available, 120))
    }

    private var dashboardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerActions
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            Divider()
            content
                .padding(.horizontal, 12)
                .padding(.top, Self.contentTopPadding)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            if case .loaded(let sections) = model.contentState {
                DashboardFooterBar(
                    sections: sections,
                    status: { syncSubtitleText(now: $0) },
                    rateLimit: requestLogModel?.latestRateLimitsByResource.first {
                        $0.resource.lowercased() == "graphql"
                    } ?? requestLogModel?.latestRateLimit
                )
            }
        }
        .frame(width: 440, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { onPreferredHeightChange($0) }
        .frame(maxHeight: .infinity, alignment: .top)
        .task {
            onMenuVisibilityChange(true)
        }
        .onDisappear {
            onMenuVisibilityChange(false)
        }
    }

    private var headerActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AppMarkView(size: ScopeSegmentedControl.height)

                if showsDashboardFilters {
                    ScopeSegmentedControl(
                        scope: model.pullRequestScope,
                        selectedCount: loadedPullRequestCount,
                        onSelect: { model.setPullRequestScope($0) }
                    )
                    .disabled(model.areDashboardFiltersDisabled)
                }

                Spacer(minLength: 4)

                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }

                if showsDashboardFilters {
                    repositoryFilterMenu
                        .disabled(model.areDashboardFiltersDisabled)
                }
                sortMenu
                moreMenu
            }

            if showsDashboardFilters, let focused = focusedRepositoryName {
                HStack(spacing: 4) {
                    Text("Filtered to \(focused) ·")
                        .foregroundStyle(.secondary)
                    Button("Clear") { model.setFocusedRepositoryID(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 2)
            }
        }
        .focusEffectDisabled()
    }

    private var focusedRepositoryName: String? {
        guard model.focusedRepositoryID != nil else { return nil }
        return repositoryFocusTitle
    }

    /// Quiet 28 pt icon button shared by the header menus.
    private func headerIcon(_ systemImage: String, isActive: Bool = false) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15))
            .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            .frame(width: 28, height: 28)
            .background(isActive ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
    }

    private var repositoryFilterMenu: some View {
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
            headerIcon("line.3.horizontal.decrease", isActive: model.focusedRepositoryID != nil)
        }
        .headerMenuStyle()
        .accessibilityLabel("Filter repositories")
        .help("Filter repositories")
    }

    private var sortMenu: some View {
        Menu {
            Section("Pull requests") {
                Picker("Pull request order", selection: Binding(
                    get: { model.settingsStore.settings.pullRequestSortOrder },
                    set: { model.settingsStore.settings.pullRequestSortOrder = $0 }
                )) {
                    ForEach(PullRequestSortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }

            Section("Repositories") {
                Picker("Repository order", selection: Binding(
                    get: { model.settingsStore.settings.repositorySortOrder },
                    set: { model.settingsStore.settings.repositorySortOrder = $0 }
                )) {
                    ForEach(RepositorySortOrder.allCases, id: \.self) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            headerIcon("arrow.up.arrow.down")
        }
        .headerMenuStyle()
        .accessibilityLabel("Sort")
        .help("Sort pull requests and repositories")
    }

    private var moreMenu: some View {
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
            headerIcon("ellipsis.circle")
        }
        .headerMenuStyle()
        .accessibilityLabel("More actions")
        .help("More")
    }

    private func syncSubtitleText(now: Date) -> String {
        if model.isRefreshing {
            return "Updating…"
        }
        guard let last = model.lastRefreshedAt else {
            return "Waiting for first update"
        }
        let seconds = max(0, Int(now.timeIntervalSince(last)))
        let age: String
        switch seconds {
        case ..<5: age = "just now"
        case ..<60: age = "\(seconds)s ago"
        case ..<3600: age = "\(seconds / 60) min ago"
        default: age = "\(seconds / 3600) h ago"
        }
        return "Updated \(age)"
    }

    private var loadedPullRequestCount: Int? {
        guard case .loaded(let sections) = model.contentState else { return nil }
        return sections.reduce(0) { $0 + $1.pullRequests.count }
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
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollContentHeight = $0 }
            }
            .frame(height: scrollViewHeight)
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
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggleCollapsed) {
                HStack(spacing: 8) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                    Text(section.repository.fullName)
                        .font(.system(size: 12, weight: .semibold))
                    Text(section.pullRequests.count, format: .number)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.repository.fullName)
            .accessibilityValue(isCollapsed ? "Collapsed" : "Expanded")
            .accessibilityHint("Shows or hides this repository's pull requests")

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
        VStack(alignment: .leading, spacing: 6) {
            Button {
                onOpenURL(pullRequest.url)
            } label: {
                Text(pullRequest.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.link)

            // Everything above the details toggles the card; the details keep their own interactions.
            VStack(alignment: .leading, spacing: 6) {
                Text(pullRequestMetadataText)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    stateChips
                }
                .padding(.top, 2)

                checksSummary
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: toggleIfExpandable)

            if isChecksExpanded && hasExpandableChecks {
                ExpandedPullRequestDetailsView(
                    pullRequest: pullRequest,
                    isRetryingJob: isRetryingJob,
                    retryErrorMessage: retryErrorMessage,
                    onRetryWorkflowJob: onRetryWorkflowJob,
                    onOpenURL: onOpenURL
                )
            }

            commentsDisclosure
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            // A collapsed card expands from anywhere on it; once expanded, only the header area toggles.
            if !isChecksExpanded { toggleIfExpandable() }
        }
        .accessibilityAction(named: isChecksExpanded ? "Collapse checks" : "Expand checks", toggleIfExpandable)
    }

    private func toggleIfExpandable() {
        if hasExpandableChecks { onToggleChecks() }
    }

    @ViewBuilder
    private var stateChips: some View {
        StatusChip(
            title: pullRequest.isDraft ? "Draft" : "Ready",
            systemImage: pullRequest.isDraft ? "pencil" : "checkmark",
            tint: pullRequest.isDraft ? .neutral : .success
        )
        StatusChip(
            title: reviewLabel(for: pullRequest.reviewStatus),
            systemImage: reviewSymbol(for: pullRequest.reviewStatus),
            tint: reviewTint(for: pullRequest.reviewStatus)
        )
        switch pullRequest.mergeable ?? .unknown {
        case .conflicting:
            StatusChip(title: "Conflicts", systemImage: "exclamationmark.triangle.fill", tint: .danger)
                .help("This branch has conflicts with the target branch. Open the PR to resolve them on GitHub.")
        case .mergeable:
            StatusChip(title: "No conflicts", systemImage: "checkmark.circle", tint: .success)
                .help("No merge conflicts with the target branch. Reviews and checks may still be required.")
        case .unknown:
            StatusChip(title: "Checking conflicts", systemImage: "clock", tint: .neutral)
                .help("GitHub is calculating merge conflicts. Refresh to check again.")
        }
    }

    private func reviewTint(for status: ReviewStatus) -> StatusTint {
        switch status {
        case .approved: .success
        case .changesRequested: .danger
        case .reviewRequired: .warning
        case .none: .neutral
        }
    }

    private var checksTint: StatusTint {
        switch pullRequest.checkRollupState {
        case .passing: .success
        case .failing: .danger
        case .pending: .warning
        case .none: .neutral
        }
    }

    private var checksSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Label(checksLabel(for: pullRequest.checkRollupState), systemImage: checksSymbol(for: pullRequest.checkRollupState))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(checksTint.color)
                if let progress = checksProgress {
                    Text("· \(progress.passed + progress.failed) of \(progress.passed + progress.failed + progress.pending) done")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if hasExpandableChecks {
                    Image(systemName: isChecksExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let progress = checksProgress {
                ChecksProgressBar(passed: progress.passed, failed: progress.failed, pending: progress.pending)
            }
        }
    }

    private var checksProgress: (passed: Int, failed: Int, pending: Int)? {
        let jobs = pullRequest.workflowRuns.flatMap(\.jobs)
        guard !jobs.isEmpty else { return nil }
        var passed = 0, failed = 0, pending = 0
        for job in jobs {
            let conclusion = job.conclusion?.lowercased()
            if job.status.lowercased() != "completed" {
                pending += 1
            } else if conclusion == "success" || conclusion == "skipped" || conclusion == "neutral" {
                passed += 1
            } else {
                failed += 1
            }
        }
        return (passed, failed, pending)
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
        } else if pullRequest.unresolvedReviewThreadCount > 0 {
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
        } else if !showsAuthor {
            components.append("opened by you")
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
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(pullRequest.workflowRuns, id: \.id) { workflowRun in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Image(systemName: "bolt.fill")
                                        .foregroundStyle(Color(red: 0.43, green: 0.35, blue: 0.84))
                                        .imageScale(.small)

                                    Button {
                                        if let url = workflowRun.detailsURL {
                                            onOpenURL(url)
                                        }
                                    } label: {
                                        Text(workflowRun.name)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.link)
                                    .disabled(workflowRun.detailsURL == nil)

                                    Text(workflowRunMetadataText(for: workflowRun, now: context.date))
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(workflowRunTint(for: workflowRun))

                                    Circle()
                                        .fill(workflowRunTint(for: workflowRun))
                                        .frame(width: 8, height: 8)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(workflowRun.jobs, id: \.id) { job in
                                        WorkflowJobView(
                                            job: job,
                                            now: context.date,
                                            isRetrying: isRetryingJob(job.id),
                                            canRetry: workflowRun.status.lowercased() == "completed",
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
                                .padding(.leading, 10)
                                .overlay(alignment: .leading) {
                                    Rectangle().fill(.separator).frame(width: 1.5)
                                }
                                .padding(.leading, 22)
                            }
                            .padding(.vertical, 6)
                            .overlay(alignment: .top) { Divider() }
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
        let duration = ActionsDurationLabelFormatter().workflowDurationText(for: workflowRun, now: now)
        return ActionsStatusText.make(
            status: workflowRun.status,
            conclusion: workflowRun.conclusion,
            durationText: duration
        )
    }

    private func workflowRunTint(for workflowRun: WorkflowRunItem) -> Color {
        ActionsStatusText.tint(status: workflowRun.status, conclusion: workflowRun.conclusion)
    }
}

enum ActionsStatusText {
    /// Compact, human wording such as "passed in 32s" or "queued 28m".
    static func make(status: String, conclusion: String?, durationText: String?) -> String {
        let duration = durationText ?? ""
        if status.lowercased() == "completed" {
            let seconds = duration.replacingOccurrences(of: "completed in ", with: "")
            let verb: String
            switch conclusion?.lowercased() {
            case "success": verb = "passed"
            case "skipped": verb = "skipped"
            case "cancelled": verb = "cancelled"
            case .some(let other): verb = other == "failure" ? "failed" : other
            case .none: verb = "done"
            }
            return seconds.isEmpty || seconds == duration && duration.isEmpty ? verb : "\(verb) in \(seconds)"
        }
        let compact = duration
            .replacingOccurrences(of: "queued for ", with: "queued ")
            .replacingOccurrences(of: "running for ", with: "running ")
        return compact.isEmpty ? status.lowercased().replacingOccurrences(of: "_", with: " ") : compact
    }

    static func tint(status: String, conclusion: String?) -> Color {
        if status.lowercased() != "completed" { return .orange }
        switch conclusion?.lowercased() {
        case "success": return .green
        case nil, "skipped", "neutral": return .secondary
        default: return .red
        }
    }
}

private struct WorkflowJobView: View {
    let job: ActionJobItem
    let now: Date
    let isRetrying: Bool
    /// GitHub only re-runs a job once its whole workflow run has finished.
    let canRetry: Bool
    let retryErrorMessage: String?
    let onRetryWorkflowJob: () -> Void
    let onOpenURL: (URL) -> Void
    
    @State private var isStepsExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(jobStatusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)

                Button {
                    if let url = job.detailsURL {
                        onOpenURL(url)
                    }
                } label: {
                    Text(jobSummary)
                        .font(.system(size: 11.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.link)
                .disabled(job.detailsURL == nil)

                if let jobMetadataText {
                    Text(jobMetadataText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(jobStatusColor == .green ? Color.secondary : jobStatusColor)
                }
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
                                            .disabled(!canRetry)
                                            .help(canRetry
                                                ? "Re-run this job in GitHub Actions"
                                                : "GitHub can re-run a job only after the whole workflow run finishes.")
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
    }
    
    private var jobSummary: String {
        if let failedStep = firstFailedStep {
            return "\(job.name) · Failed on \(failedStep.name)"
        }
        
        if let conclusion = job.conclusion?.lowercased(), conclusion != "success" {
            return "\(job.name) · \(conclusion)"
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
        let duration = ActionsDurationLabelFormatter().jobDurationText(for: job, now: now)
        guard job.status.lowercased() != "completed" || duration != nil else { return nil }
        return ActionsStatusText.make(status: job.status, conclusion: nil, durationText: duration)
            .replacingOccurrences(of: "done in ", with: "")
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
                    HStack(alignment: .top, spacing: 8) {
                        AsyncImage(url: comment.authorAvatarURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Text(String(comment.authorLogin.prefix(1)).uppercased())
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.primary.opacity(0.08))
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top, spacing: 8) {
                                ViewThatFits(in: .horizontal) {
                                    HStack(spacing: 6) {
                                        commentAuthor(comment)
                                        commentTime(comment)
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        commentAuthor(comment)
                                        commentTime(comment)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05))

                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text(comment.filePath)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(comment.filePath)

                                Text(comment.bodyText)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Open review comment on GitHub")
                .accessibilityLabel("Comment by \(comment.authorLogin) in \(comment.filePath): \(comment.bodyText)")
                .accessibilityHint("Opens this review comment on GitHub")
            }
        }
    }

    private func commentAuthor(_ comment: UnresolvedReviewCommentItem) -> some View {
        Text(comment.authorLogin)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func commentTime(_ comment: UnresolvedReviewCommentItem) -> some View {
        if let date = comment.createdAt {
            Text(date, format: .relative(presentation: .named))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
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

/// Status colors with readable text on a tinted background in both appearances.
enum StatusTint {
    case success, warning, danger, neutral

    var color: Color {
        switch self {
        case .success: Color(light: 0x1A7F37, dark: 0x56D364)
        case .warning: Color(light: 0x8A4A00, dark: 0xF0A050)
        case .danger: Color(light: 0xB4202B, dark: 0xFF7B72)
        case .neutral: Color(light: 0x5C5C63, dark: 0xA0A0A8)
        }
    }
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        func component(_ value: UInt32, _ shift: UInt32) -> CGFloat { CGFloat((value >> shift) & 0xFF) / 255 }
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(srgbRed: component(value, 16), green: component(value, 8), blue: component(value, 0), alpha: 1)
        })
    }
}

private struct StatusChip: View {
    let title: String
    let systemImage: String
    let tint: StatusTint

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(tint.color)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(tint.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct ChecksProgressBar: View {
    let passed: Int
    let failed: Int
    let pending: Int

    var body: some View {
        let total = max(passed + failed + pending, 1)
        GeometryReader { proxy in
            HStack(spacing: 2) {
                segment(.green, count: passed, total: total, width: proxy.size.width)
                segment(.red, count: failed, total: total, width: proxy.size.width)
                segment(.orange, count: pending, total: total, width: proxy.size.width)
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel("\(passed) of \(total) jobs passed, \(failed) failed, \(pending) pending")
    }

    @ViewBuilder
    private func segment(_ color: Color, count: Int, total: Int, width: CGFloat) -> some View {
        if count > 0 {
            Rectangle()
                .fill(color)
                .frame(width: max(width * CGFloat(count) / CGFloat(total) - 2, 2))
        }
    }
}

struct AppMarkView: View {
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(red: 0.40, green: 0.32, blue: 0.84), Color(red: 0.14, green: 0.09, blue: 0.38)],
                startPoint: .top,
                endPoint: .bottom
            ))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "arrow.triangle.branch")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.bold)
                    .frame(width: size * 0.52, height: size * 0.52)
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private struct DashboardFooterBar: View {
    let sections: [RepositorySection]
    let status: (Date) -> String
    let rateLimit: GitHubRateLimitStatus?

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text("\(status(context.date)) · \(summary)")
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let rateLimit {
                    Label {
                        Text("\(rateLimit.remaining.formatted()) calls left")
                    } icon: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .help("GitHub \(rateLimit.resource) quota")
                }
            }
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .frame(height: 38)
        }
        .background(.background.opacity(0.5))
    }

    private var summary: String {
        let pullRequests = sections.flatMap(\.pullRequests)
        let failing = pullRequests.filter { $0.checkRollupState == .failing }.count
        let ready = pullRequests.filter {
            !$0.isDraft && $0.reviewStatus == .approved && $0.checkRollupState == .passing && $0.mergeable == .mergeable
        }.count
        var parts = ["\(pullRequests.count) open"]
        if failing > 0 { parts.append("\(failing) failing") }
        if ready > 0 { parts.append("\(ready) ready") }
        return parts.joined(separator: " · ")
    }
}

private struct ScopeSegmentedControl: View {
    static let height: CGFloat = 28

    let scope: PullRequestScope
    let selectedCount: Int?
    let onSelect: (PullRequestScope) -> Void

    var body: some View {
        HStack(spacing: 2) {
            segment("My PRs", value: .mine)
            segment("All PRs", value: .all)
        }
        .padding(2)
        .frame(height: Self.height)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func segment(_ title: String, value: PullRequestScope) -> some View {
        let isSelected = scope == value
        return Button {
            onSelect(value)
        } label: {
            HStack(spacing: 5) {
                Text(title).fontWeight(isSelected ? .semibold : .regular)
                if isSelected, let selectedCount {
                    Text(selectedCount, format: .number)
                        .opacity(0.85)
                }
            }
            .font(.system(size: 12.5))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    func headerMenuStyle() -> some View {
        self
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .focusEffectDisabled()
            .fixedSize()
    }
}
