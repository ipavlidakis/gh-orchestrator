import AppKit
import GHOrchestratorCore
import Observation
import SwiftUI

private enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general
    case github
    case repositories
    case notifications
    case requests

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .github:
            return "GitHub"
        case .repositories:
            return "Repositories"
        case .notifications:
            return "Notifications"
        case .requests:
            return "Requests"
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            return "gearshape"
        case .github:
            return "person.crop.circle.badge.checkmark"
        case .repositories:
            return "tray.full"
        case .notifications:
            return "bell.badge"
        case .requests:
            return "chart.bar.xaxis"
        }
    }
}

struct SettingsWindowView: View {
    @Bindable var model: SettingsModel
    let requestLogModel: GitHubRequestLogModel
    let menuVisibilityController: any SettingsWindowMenuVisibilityControlling

    @SceneStorage("settings.selected-pane") private var selectedPaneID = SettingsPane.general.rawValue
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: selectedPaneBinding) { pane in
                Label(pane.title, systemImage: pane.systemImage)
                    .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 230)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailScrollView(title: selectedPane.title) {
                switch selectedPane {
                case .general:
                    GeneralSettingsPane(model: model)
                case .github:
                    GitHubSettingsPane(model: model)
                case .repositories:
                    RepositorySettingsPane(model: model)
                case .notifications:
                    NotificationSettingsPane(model: model)
                case .requests:
                    GitHubRequestUsagePane(requestLogModel: requestLogModel)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 780, minHeight: 560, idealHeight: 600)
        .windowMinimizeBehavior(.disabled)
        .windowResizeBehavior(.disabled)
        .onAppear {
            menuVisibilityController.setSettingsWindowActive(appearsActive)
        }
        .onChange(of: appearsActive) { _, newValue in
            menuVisibilityController.setSettingsWindowActive(newValue)
        }
        .onDisappear {
            menuVisibilityController.setSettingsWindowActive(false)
        }
    }

    private var selectedPane: SettingsPane {
        SettingsPane(rawValue: selectedPaneID) ?? .general
    }

    private var selectedPaneBinding: Binding<SettingsPane?> {
        Binding(
            get: { selectedPane },
            set: { selectedPaneID = ($0 ?? .general).rawValue }
        )
    }
}

private struct SettingsDetailScrollView<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                content
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
    }
}

private struct GitHubRequestUsagePane: View {
    let requestLogModel: GitHubRequestLogModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Quota by resource") {
                if requestLogModel.latestRateLimitsByResource.isEmpty {
                    SettingsTextBlock(
                        title: "No quota headers yet",
                        bodyText: "Run a dashboard refresh after signing in to collect GitHub quota headers."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(requestLogModel.latestRateLimitsByResource.enumerated()), id: \.element.resource) { index, rateLimit in
                            if index > 0 {
                                Divider()
                            }

                            GitHubRateLimitResourceRow(rateLimit: rateLimit)
                        }
                    }
                    .padding(.vertical, 10)
                }
            } footer: {
                Text("GitHub reports separate resources such as REST core and GraphQL. \(requestLogModel.records.count) requests recorded in this app run; \(requestLogModel.requestsWithRateLimitHeaderCount) included quota headers.")
            }

            SettingsGroup(title: "Recent requests") {
                if requestLogModel.records.isEmpty {
                    SettingsTextBlock(
                        title: "No requests recorded",
                        bodyText: "GitHub requests will appear here after sign-in or dashboard refreshes."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(requestLogModel.records.prefix(30).enumerated()), id: \.element.id) { index, record in
                            if index > 0 {
                                Divider()
                            }

                            GitHubRequestRecordRow(record: record)
                        }
                    }
                }
            } footer: {
                HStack {
                    Text("Current run only. Request bodies and tokens are not recorded.")

                    Spacer()

                    Button("Clear") {
                        requestLogModel.clear()
                    }
                    .disabled(requestLogModel.records.isEmpty)
                }
            }
        }
    }
}

private struct GitHubRateLimitResourceRow: View {
    let rateLimit: GitHubRateLimitStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(rateLimit.resource)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)

                Spacer()

                Text("\(rateLimit.remaining) remaining")
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(rateLimit.remaining),
                total: Double(max(rateLimit.limit, 1))
            )

            HStack(spacing: 12) {
                Text("Limit \(rateLimit.limit)")
                Text("Used \(rateLimit.used)")
                Text("Reset \(rateLimit.resetDate, style: .time)")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 8)
    }
}

private struct GitHubRequestRecordRow: View {
    let record: GitHubRequestRecord

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.method)
                        .font(.caption.weight(.semibold))
                        .monospaced()

                    Text(record.endpoint)
                        .font(.caption)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text(record.timestamp, style: .time)

                    if let rateLimit = record.rateLimit {
                        Text("\(rateLimit.remaining)/\(rateLimit.limit) remaining")
                        Text(rateLimit.resource)
                    } else if let errorMessage = record.errorMessage {
                        Text(errorMessage)
                            .lineLimit(1)
                    } else {
                        Text("No quota headers")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Spacer(minLength: 16)

            Text(statusText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }

    private var statusText: String {
        guard let statusCode = record.statusCode else {
            return "Failed"
        }

        return "\(statusCode)"
    }

    private var statusColor: Color {
        guard let statusCode = record.statusCode else {
            return .red
        }

        if statusCode >= 400 {
            return .red
        }

        if statusCode >= 300 {
            return .orange
        }

        return .secondary
    }
}

private struct GeneralSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "App behavior") {
                SettingsRow(
                    title: "Hide Dock icon",
                    subtitle: "Keep GHOrchestrator in the menu bar while removing it from the Dock."
                ) {
                    Toggle("", isOn: $model.hideDockIcon)
                        .labelsHidden()
                }

                Divider()

                SettingsRow(
                    title: "Polling interval",
                    subtitle: "Refresh only while the menu is hidden."
                ) {
                    HStack(spacing: 10) {
                        Text("Seconds")
                            .foregroundStyle(.secondary)

                        TextField("Seconds", text: $model.pollingIntervalText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)

                        Stepper(
                            value: Binding(
                                get: { model.pollingIntervalStepperValue },
                                set: { model.pollingIntervalText = String($0) }
                            ),
                            in: AppSettings.allowedPollingIntervalRange,
                            step: 15
                        ) {
                            Text("\(model.pollingIntervalStepperValue) seconds")
                                .monospacedDigit()
                        }
                        .labelsHidden()
                    }
                }
            } footer: {
                if let message = model.pollingIntervalValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let message = model.pollingIntervalAdvisoryMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("When the Dock icon is hidden, reopen Settings from the menu bar extra.")
                }
            }

            SettingsGroup(title: "Dashboard query limits") {
                SettingsRow(
                    title: "Pull requests",
                    subtitle: "Maximum PRs loaded per configured repository."
                ) {
                    Stepper(
                        value: Binding(
                            get: { model.graphQLSearchResultLimit },
                            set: { model.graphQLSearchResultLimit = $0 }
                        ),
                        in: AppSettings.allowedGraphQLConnectionLimitRange
                    ) {
                        Text("\(model.graphQLSearchResultLimit)")
                            .monospacedDigit()
                    }
                }

                Divider()

                SettingsRow(
                    title: "Review threads",
                    subtitle: "Maximum review threads loaded per PR."
                ) {
                    Stepper(
                        value: Binding(
                            get: { model.graphQLReviewThreadLimit },
                            set: { model.graphQLReviewThreadLimit = $0 }
                        ),
                        in: AppSettings.allowedGraphQLConnectionLimitRange
                    ) {
                        Text("\(model.graphQLReviewThreadLimit)")
                            .monospacedDigit()
                    }
                }

                Divider()

                SettingsRow(
                    title: "Comments per thread",
                    subtitle: "Latest comments loaded for each review thread."
                ) {
                    Stepper(
                        value: Binding(
                            get: { model.graphQLReviewThreadCommentLimit },
                            set: { model.graphQLReviewThreadCommentLimit = $0 }
                        ),
                        in: AppSettings.allowedGraphQLReviewThreadCommentLimitRange
                    ) {
                        Text("\(model.graphQLReviewThreadCommentLimit)")
                            .monospacedDigit()
                    }
                }

                Divider()

                SettingsRow(
                    title: "Check contexts",
                    subtitle: "Maximum check runs/status contexts loaded per PR."
                ) {
                    Stepper(
                        value: Binding(
                            get: { model.graphQLCheckContextLimit },
                            set: { model.graphQLCheckContextLimit = $0 }
                        ),
                        in: AppSettings.allowedGraphQLConnectionLimitRange
                    ) {
                        Text("\(model.graphQLCheckContextLimit)")
                            .monospacedDigit()
                    }
                }
            } footer: {
                Label(model.graphQLDashboardLimitAdvisoryMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup(title: "Actions") {
                SettingsRow(
                    title: "Refresh dashboard",
                    subtitle: "Run the existing dashboard refresh path now."
                ) {
                    Button("Refresh Now") {
                        model.requestManualRefresh()
                    }
                    .disabled(!model.hasManualRefreshAction)
                }

                Divider()

                SettingsRow(
                    title: "Quit \(AppMetadata.menuBarTitle)",
                    subtitle: "Close the menu bar extra and exit the app."
                ) {
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
        }
    }
}

private struct GitHubSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Connection") {
                SettingsRow(title: "Status") {
                    Text(model.authenticationDescription)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                }

                switch model.authenticationState {
                case .authenticated(let username):
                    Divider()

                    SettingsTextBlock(
                        title: "Account",
                        bodyText: "Signed in as \(username).\nThe dashboard can fetch GitHub data with this account."
                    )

                    Divider()

                    SettingsRow(
                        title: "Actions",
                        subtitle: "Remove the stored GitHub session from this Mac."
                    ) {
                        Button("Sign Out") {
                            model.requestSignOut()
                        }
                        .disabled(!model.canSignOut)
                    }
                case .notConfigured:
                    Divider()

                    SettingsTextBlock(
                        title: "OAuth not configured",
                        bodyText: "This build does not include a GitHub OAuth client ID. Add `clientID` to `Config/GitHubOAuth.local.json` before generating/building the app, or use the build-time env var fallback. The GitHub OAuth app must also have device flow enabled."
                    )

                    Divider()

                    SettingsRow(
                        title: "Create OAuth App",
                        subtitle: "Open GitHub’s OAuth app registration page in your browser."
                    ) {
                        Link("Open Registration Page", destination: AppMetadata.gitHubOAuthAppRegistrationURL)
                    }

                    Divider()

                    SettingsRow(
                        title: "Setup Guide",
                        subtitle: "Open the GitHub docs for the exact OAuth app creation steps."
                    ) {
                        Link("Open GitHub Docs", destination: AppMetadata.gitHubOAuthAppDocsURL)
                    }
                case .signedOut:
                    Divider()

                    SettingsTextBlock(
                        title: "Sign in",
                        bodyText: "Start GitHub sign-in to get a one-time device code, then approve that code in your browser."
                    )

                    Divider()

                    SettingsRow(
                        title: "Actions",
                        subtitle: "Request a GitHub device code and open the verification page in the default browser."
                    ) {
                        Button("Sign in with GitHub") {
                            model.requestSignIn()
                        }
                        .disabled(!model.canStartSignIn)
                    }
                case .authorizing:
                    Divider()

                    if let userCode = model.deviceAuthorizationUserCode {
                        SettingsTextBlock(
                            title: "Approve device code",
                            bodyText: "Enter this one-time code on GitHub to finish sign-in."
                        )

                        Divider()

                        SettingsRow(
                            title: "Verification code",
                            subtitle: "GitHub expires this code after a short window."
                        ) {
                            Text(userCode)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        if let verificationURI = model.deviceAuthorizationVerificationURI {
                            Divider()

                            SettingsRow(
                                title: "Verification page",
                                subtitle: "Open GitHub’s device verification page if the browser did not open automatically."
                            ) {
                                Link("Open Verification Page", destination: verificationURI)
                            }
                        }
                    } else {
                        SettingsTextBlock(
                            title: "Preparing sign-in",
                            bodyText: "Requesting a GitHub device code for this Mac."
                        )

                        Divider()

                        SettingsRow(
                            title: "Progress",
                            subtitle: "Waiting for GitHub to issue the device code."
                        ) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                case .authFailure(let message):
                    Divider()

                    SettingsTextBlock(
                        title: "Authentication failed",
                        bodyText: message
                    )

                    Divider()

                    SettingsRow(
                        title: "Actions",
                        subtitle: "Start a new GitHub sign-in attempt."
                    ) {
                        Button("Sign in with GitHub") {
                            model.requestSignIn()
                        }
                        .disabled(!model.canStartSignIn)
                    }
                }
            }
        }
    }

    private var statusColor: Color {
        switch model.authenticationState {
        case .authenticated:
            return .green
        case .authorizing:
            return .accentColor
        case .notConfigured, .signedOut, .authFailure:
            return .secondary
        }
    }
}

private struct RepositorySettingsPane: View {
    @Bindable var model: SettingsModel
    @State private var selectedRepositoryIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Observed repositories") {
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))

                        if model.observedRepositories.isEmpty {
                            Text("No Observed Repositories")
                                .foregroundStyle(.secondary)
                        } else {
                            List(selection: $selectedRepositoryIDs) {
                                ForEach(model.observedRepositories) { repository in
                                    Text(repository.fullName)
                                        .font(.system(.body, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .tag(repository.id)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                    .frame(minHeight: 240)

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            presentAddRepositoryAlert()
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.borderless)

                        Button {
                            model.removeObservedRepositories(withIDs: selectedRepositoryIDs)
                            selectedRepositoryIDs.removeAll()
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.borderless)
                        .disabled(selectedRepositoryIDs.isEmpty)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add repositories in owner/name format.")

                    if !model.repositoryValidationMessages.isEmpty {
                        ForEach(model.repositoryValidationMessages, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
        }
    }

    private func presentAddRepositoryAlert() {
        let alert = NSAlert()
        alert.messageText = "Add Repository"
        alert.informativeText = "Enter the repository in owner/name format."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        textField.placeholderString = "owner/name"
        alert.accessoryView = textField

        NSApplication.shared.activate(ignoringOtherApps: true)

        if alert.runModal() == .alertFirstButtonReturn {
            _ = model.addObservedRepository(from: textField.stringValue)
        }
    }
}

private struct NotificationSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Permission") {
                SettingsRow(
                    title: "Status",
                    subtitle: notificationPermissionSubtitle
                ) {
                    Text(model.notificationAuthorizationDescription)
                        .foregroundStyle(notificationPermissionColor)
                }

                Divider()

                SettingsRow(
                    title: "Enable Notifications",
                    subtitle: "Allow GHOrchestrator to deliver local macOS alerts for matching repository events."
                ) {
                    Button("Enable") {
                        model.requestNotificationAuthorization()
                    }
                    .disabled(!model.canRequestNotificationAuthorization)
                }
            }

            SettingsGroup(title: "Repository triggers") {
                if model.observedRepositories.isEmpty {
                    SettingsTextBlock(
                        title: "No repositories configured",
                        bodyText: "Add repositories before enabling notification triggers."
                    )
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.observedRepositories.enumerated()), id: \.offset) { index, repository in
                            if index > 0 {
                                Divider()
                            }

                            RepositoryNotificationSettingsRows(
                                repository: repository,
                                model: model
                            )
                        }
                    }
                }
            } footer: {
                Text("Notification polling checks all open PRs in enabled repositories, independent of the dashboard filter.")
            }
        }
    }

    private var notificationPermissionSubtitle: String {
        switch model.notificationAuthorizationStatus {
        case .notDetermined:
            return "macOS has not asked for notification permission yet."
        case .denied:
            return "Enable notifications for GHOrchestrator in System Settings to receive alerts."
        case .authorized, .provisional, .ephemeral:
            return "Matching repository events can be delivered as local notifications."
        case .unknown:
            return "macOS returned an unrecognized notification permission state."
        }
    }

    private var notificationPermissionColor: Color {
        switch model.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .green
        case .denied:
            return .red
        case .notDetermined, .unknown:
            return .secondary
        }
    }
}

private struct RepositoryNotificationSettingsRows: View {
    let repository: ObservedRepository
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsRow(
                title: repository.fullName,
                subtitle: "Evaluate all open pull requests in this repository."
            ) {
                Toggle(
                    "",
                    isOn: Binding(
                        get: {
                            model.isRepositoryNotificationsEnabled(repositoryID: repository.id)
                        },
                        set: { isEnabled in
                            model.setRepositoryNotificationsEnabled(
                                isEnabled,
                                repositoryID: repository.id
                            )
                        }
                    )
                )
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(RepositoryNotificationTrigger.allCases, id: \.self) { trigger in
                    NotificationTriggerToggleRow(
                        trigger: trigger,
                        repositoryID: repository.id,
                        model: model
                    )
                }

                SettingsRow(
                    title: "Workflow filters",
                    subtitle: "Empty selection matches every PR-attached workflow completion."
                ) {
                    WorkflowFilterPicker(
                        repositoryID: repository.id,
                        model: model
                    )
                }

                SettingsRow(
                    title: "Job filters",
                    subtitle: "Optional job names for job-completion alerts. Empty selection matches every job in a workflow."
                ) {
                    WorkflowJobFilterPicker(
                        repositoryID: repository.id,
                        model: model
                    )
                }
            }
            .padding(.leading, 18)
            .disabled(!model.isRepositoryNotificationsEnabled(repositoryID: repository.id))
        }
        .padding(.vertical, 8)
        .task {
            model.loadWorkflowNamesIfNeeded(repositoryID: repository.id)
        }
    }
}

private struct WorkflowJobFilterPicker: View {
    let repositoryID: String
    @Bindable var model: SettingsModel

    var body: some View {
        Menu {
            switch model.workflowListState(repositoryID: repositoryID) {
            case .idle:
                Button("Load Workflows") {
                    model.loadWorkflowNamesIfNeeded(repositoryID: repositoryID)
                }
            case .loading:
                Text("Loading workflows...")
            case .failed(let message):
                Text(message)
                Button("Retry") {
                    model.refreshWorkflowNames(repositoryID: repositoryID)
                }
            case .loaded:
                let workflows = model.availableWorkflows(repositoryID: repositoryID)
                if workflows.isEmpty {
                    Text("No Actions workflows found")
                } else {
                    ForEach(workflows) { workflow in
                        Menu(workflow.name) {
                            workflowJobContent(workflow: workflow)
                        }
                    }
                }
            }
        } label: {
            Label(jobFilterSummary, systemImage: "checklist")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 180, alignment: .trailing)
    }

    private var jobFilterSummary: String {
        let count = model.availableWorkflows(repositoryID: repositoryID).reduce(into: 0) { count, workflow in
            if model.workflowJobNameFilterSummary(repositoryID: repositoryID, workflowName: workflow.name) != "All jobs" {
                count += 1
            }
        }

        guard count > 0 else {
            return "All jobs"
        }

        return "\(count) workflow filters"
    }

    @ViewBuilder
    private func workflowJobContent(workflow: ActionsWorkflowItem) -> some View {
        Button {
            model.clearWorkflowJobNameFilters(
                repositoryID: repositoryID,
                workflowName: workflow.name
            )
        } label: {
            if model.workflowJobNameFilterSummary(repositoryID: repositoryID, workflowName: workflow.name) == "All jobs" {
                Label("All jobs", systemImage: "checkmark")
            } else {
                Text("All jobs")
            }
        }

        Divider()

        switch model.workflowJobListState(repositoryID: repositoryID, workflowName: workflow.name) {
        case .idle:
            Button("Load Jobs") {
                model.loadWorkflowJobNamesIfNeeded(
                    repositoryID: repositoryID,
                    workflow: workflow
                )
            }
        case .loading:
            Text("Loading jobs...")
        case .failed(let message):
            Text(message)
            Button("Retry") {
                model.refreshWorkflowJobNames(
                    repositoryID: repositoryID,
                    workflow: workflow
                )
            }
        case .loaded(let jobNames):
            if jobNames.isEmpty {
                Text("No recent jobs found")
            } else {
                ForEach(jobNames, id: \.self) { jobName in
                    Button {
                        model.setWorkflowJobNameFilter(
                            jobName,
                            isSelected: !model.isWorkflowJobNameFilterSelected(
                                jobName,
                                repositoryID: repositoryID,
                                workflowName: workflow.name
                            ),
                            repositoryID: repositoryID,
                            workflowName: workflow.name
                        )
                    } label: {
                        if model.isWorkflowJobNameFilterSelected(jobName, repositoryID: repositoryID, workflowName: workflow.name) {
                            Label(jobName, systemImage: "checkmark")
                        } else {
                            Text(jobName)
                        }
                    }
                }
            }
        }

        Divider()

        Button("Refresh Jobs") {
            model.refreshWorkflowJobNames(
                repositoryID: repositoryID,
                workflow: workflow
            )
        }
    }
}

private struct WorkflowFilterPicker: View {
    let repositoryID: String
    @Bindable var model: SettingsModel

    var body: some View {
        Menu {
            Button {
                model.clearWorkflowNameFilters(repositoryID: repositoryID)
            } label: {
                if model.workflowNameFilterSummary(repositoryID: repositoryID) == "All workflows" {
                    Label("All workflows", systemImage: "checkmark")
                } else {
                    Text("All workflows")
                }
            }

            Divider()

            workflowContent

            Divider()

            Button("Refresh Workflows") {
                model.refreshWorkflowNames(repositoryID: repositoryID)
            }
        } label: {
            Label(model.workflowNameFilterSummary(repositoryID: repositoryID), systemImage: "list.bullet.rectangle")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 180, alignment: .trailing)
    }

    @ViewBuilder
    private var workflowContent: some View {
        switch model.workflowListState(repositoryID: repositoryID) {
        case .idle:
            Button("Load Workflows") {
                model.loadWorkflowNamesIfNeeded(repositoryID: repositoryID)
            }
        case .loading:
            Text("Loading workflows...")
        case .failed(let message):
            Text(message)
            Button("Retry") {
                model.refreshWorkflowNames(repositoryID: repositoryID)
            }
        case .loaded(let workflowNames):
            if workflowNames.isEmpty {
                Text("No Actions workflows found")
            } else {
                ForEach(workflowNames, id: \.self) { workflowName in
                    Button {
                        model.setWorkflowNameFilter(
                            workflowName,
                            isSelected: !model.isWorkflowNameFilterSelected(
                                workflowName,
                                repositoryID: repositoryID
                            ),
                            repositoryID: repositoryID
                        )
                    } label: {
                        if model.isWorkflowNameFilterSelected(workflowName, repositoryID: repositoryID) {
                            Label(workflowName, systemImage: "checkmark")
                        } else {
                            Text(workflowName)
                        }
                    }
                }
            }
        }
    }
}

private struct NotificationTriggerToggleRow: View {
    let trigger: RepositoryNotificationTrigger
    let repositoryID: String
    @Bindable var model: SettingsModel

    var body: some View {
        SettingsRow(
            title: trigger.settingsTitle,
            subtitle: trigger.settingsSubtitle
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: {
                        model.isNotificationTriggerEnabled(
                            trigger,
                            repositoryID: repositoryID
                        )
                    },
                    set: { isEnabled in
                        model.setNotificationTrigger(
                            trigger,
                            isEnabled: isEnabled,
                            repositoryID: repositoryID
                        )
                    }
                )
            )
            .labelsHidden()
        }
    }
}

private extension RepositoryNotificationTrigger {
    var settingsTitle: String {
        switch self {
        case .pullRequestCreated:
            return "PR created"
        case .approval:
            return "PR approved"
        case .changesRequested:
            return "Changes requested"
        case .newUnresolvedReviewComment:
            return "New unresolved review comment"
        case .workflowRunCompleted:
            return "Workflow run completed"
        case .workflowJobCompleted:
            return "Workflow job completed"
        }
    }

    var settingsSubtitle: String {
        switch self {
        case .pullRequestCreated:
            return "Notify when a new open PR appears after notification monitoring starts."
        case .approval:
            return "Notify when a PR review state changes to approved."
        case .changesRequested:
            return "Notify when reviewers request changes on a PR."
        case .newUnresolvedReviewComment:
            return "Notify when a new unresolved review comment appears."
        case .workflowRunCompleted:
            return "Notify when a PR-attached GitHub Actions workflow run completes."
        case .workflowJobCompleted:
            return "Notify when a job inside a matching PR-attached workflow completes."
        }
    }
}

private struct SettingsGroup<Content: View, Footer: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            footer
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)

                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 24)

            accessory
        }
        .padding(.vertical, 10)
    }
}

private struct SettingsTextBlock: View {
    let title: String
    let bodyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(bodyText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
    }
}

private struct CommandListView: View {
    let commands: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(commands, id: \.self) { command in
                Text(command)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 10)
    }
}
