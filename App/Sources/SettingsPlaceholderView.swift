import AppKit
import GHOrchestratorCore
import Observation
import SwiftUI

private enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general
    case github
    case repositories
    case insights
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
        case .insights:
            return "Insights"
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
        case .insights:
            return "chart.xyaxis.line"
        case .notifications:
            return "bell.badge"
        case .requests:
            return "chart.bar.xaxis"
        }
    }
}

struct SettingsWindowView: View {
    @Bindable var model: SettingsModel
    @Bindable var softwareUpdateModel: SoftwareUpdateModel
    let requestLogModel: GitHubRequestLogModel
    let menuVisibilityController: any SettingsWindowMenuVisibilityControlling
    let onSettingsWindowVisibilityChange: @MainActor (Bool) -> Void

    @SceneStorage("settings.selected-pane") private var selectedPaneID = SettingsPane.general.rawValue
    @Environment(\.appearsActive) private var appearsActive

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: selectedPaneBinding)

            SettingsDetailPage(title: selectedPane.title) {
                switch selectedPane {
                case .general:
                    GeneralSettingsPane(
                        model: model,
                        softwareUpdateModel: softwareUpdateModel
                    )
                case .github:
                    GitHubSettingsPane(model: model)
                case .repositories:
                    RepositorySettingsPane(model: model)
                case .insights:
                    ActionsInsightsSettingsPane(model: model)
                case .notifications:
                    NotificationSettingsPane(model: model)
                case .requests:
                    GitHubRequestUsagePane(requestLogModel: requestLogModel)
                }
            }
        }
        .frame(width: 820)
        .frame(minHeight: 620, idealHeight: 620, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .background(SettingsWindowChromeConfigurator())
        .ignoresSafeArea()
        .windowMinimizeBehavior(.disabled)
        .windowResizeBehavior(.disabled)
        .onAppear {
            onSettingsWindowVisibilityChange(true)
            menuVisibilityController.setSettingsWindowActive(appearsActive)
        }
        .onChange(of: appearsActive) { _, newValue in
            menuVisibilityController.setSettingsWindowActive(newValue)
        }
        .onDisappear {
            menuVisibilityController.setSettingsWindowActive(false)
            onSettingsWindowVisibilityChange(false)
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

/// Left rail: window controls sit on top of it, then the panes, then the app mark.
private struct SettingsSidebar: View {
    @Binding var selection: SettingsPane?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                SettingsSidebarRow(pane: pane, isSelected: selection == pane) {
                    selection = pane
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                AppMarkView(size: 22)
                Text(AppMetadata.menuBarTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 52)
        .padding(.bottom, 14)
        .frame(width: 196)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.primary.opacity(0.05))
        .overlay(alignment: .trailing) {
            Rectangle().fill(.separator).frame(width: 0.5)
        }
    }
}

private struct SettingsSidebarRow: View {
    let pane: SettingsPane
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: pane.systemImage)
                    .frame(width: 16)
                Text(pane.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Centered title above a scrolling stack of grouped cards.
private struct SettingsDetailPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            page.buttonStyle(.glass)
        } else {
            page
        }
    }

    private var page: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    content
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Moves the traffic lights onto the sidebar by letting content run under a transparent title bar.
private struct SettingsWindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ChromeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            observers.forEach(NotificationCenter.default.removeObserver)
            // SwiftUI reapplies its own title bar settings after the window appears, so reassert ours.
            observers = [
                NSWindow.didBecomeKeyNotification,
                NSWindow.didUpdateNotification,
                NSWindow.didResizeNotification
            ].map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.applyChrome() }
                }
            }
            applyChrome()
            // With the title bar folded into the content, the window is exactly the design size.
            DispatchQueue.main.async { [weak window] in
                window?.setContentSize(NSSize(width: 820, height: 620))
            }
        }

        private func applyChrome() {
            guard let window else { return }
            if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
            if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
            if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
            if window.titlebarSeparatorStyle != .none { window.titlebarSeparatorStyle = .none }
            if !window.isMovableByWindowBackground { window.isMovableByWindowBackground = true }
            if window.backgroundColor != .textBackgroundColor { window.backgroundColor = .textBackgroundColor }
        }

        deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }
    }
}

struct GitHubRequestUsagePane: View {
    let requestLogModel: GitHubRequestLogModel

    var body: some View {
        Group {
            SettingsGroup(title: "Quota by resource") {
                if requestLogModel.latestRateLimitsByResource.isEmpty {
                    SettingsTextBlock(
                        title: "No quota headers yet",
                        bodyText: "Run a dashboard refresh after signing in to collect GitHub quota headers."
                    )
                } else {
                    ForEach(requestLogModel.latestRateLimitsByResource, id: \.resource) { rateLimit in
                        GitHubRateLimitResourceRow(rateLimit: rateLimit)
                    }
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
                    Group {
                        ForEach(Array(requestLogModel.records.prefix(30))) { record in
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

struct GeneralSettingsPane: View {
    @Bindable var model: SettingsModel
    @Bindable var softwareUpdateModel: SoftwareUpdateModel

    var body: some View {
        Group {
            SettingsGroup(title: "App behavior") {
                SettingsRow(title: "Pull request order") {
                    Picker("Pull request order", selection: $model.pullRequestSortOrder) {
                        ForEach(PullRequestSortOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }

                SettingsRow(
                    title: "Repository order",
                    subtitle: "How repositories are arranged in the popover."
                ) {
                    Picker("Repository order", selection: $model.repositorySortOrder) {
                        ForEach(RepositorySortOrder.allCases, id: \.self) { order in
                            Text(order.title).tag(order)
                        }
                    }
                }

                SettingsRow(
                    title: "Show Dock icon",
                    subtitle: "Off keeps GHOrchestrator in the menu bar only. It reappears while Settings is open."
                ) {
                    Toggle(
                        "Show Dock icon",
                        isOn: Binding(
                            get: { !model.hideDockIcon },
                            set: { model.hideDockIcon = !$0 }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                }

                SettingsRow(
                    title: "Start at login",
                    subtitle: model.startAtLoginSubtitle
                ) {
                    HStack(spacing: 10) {
                        if model.canOpenLoginItemsSettings {
                            Button("Open Login Items") {
                                model.requestOpenLoginItemsSettings()
                            }
                        }

                        Toggle("Start at login", isOn: $model.startAtLogin)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SettingsRow(
                    title: "Refresh every",
                    subtitle: "Runs whether the popover is open or not."
                ) {
                    HStack(spacing: 10) {
                        TextField("Seconds", text: $model.pollingIntervalText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 56)

                        Text("seconds")
                            .fixedSize()
                            .foregroundStyle(.secondary)

                        Stepper(
                            value: Binding(
                                get: { model.pollingIntervalStepperValue },
                                set: { model.pollingIntervalText = String($0) }
                            ),
                            in: AppSettings.allowedPollingIntervalRange,
                            step: 15
                        ) {
                            EmptyView()
                        }
                        .accessibilityLabel("Adjust polling interval in seconds")
                        .labelsHidden()
                        .fixedSize()
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
                    Text("When the Dock icon is hidden, it reappears while Settings is open so the window stays reachable.")
                }
            }

            SettingsGroup(title: "Software updates") {
                SettingsRow(
                    title: "Version \(softwareUpdateModel.currentVersion) (\(AppMetadata.currentBuild))",
                    subtitle: updateStatusLine,
                    subtitleColor: updateStatusColor
                ) {
                    HStack(spacing: 10) {
                        if case .checking = softwareUpdateModel.state {
                            ProgressView()
                                .controlSize(.small)
                        }

                        if softwareUpdateModel.canInstallUpdate {
                            Button(softwareUpdateModel.installButtonTitle) {
                                softwareUpdateModel.requestInstallUpdate()
                            }
                        }

                        Button(softwareUpdateModel.checkButtonTitle) {
                            softwareUpdateModel.requestCheckForUpdates()
                        }
                        .disabled(!softwareUpdateModel.canCheckForUpdates)
                    }
                }

                SettingsRow(
                    title: "Check automatically",
                    subtitle: "Uses the signed, notarized DMG from the latest GitHub Release."
                ) {
                    Toggle("Check automatically", isOn: $softwareUpdateModel.automaticallyCheckForUpdates)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }

                if let releaseNotes = softwareUpdateModel.availableUpdate?.releaseNotes {

                    SettingsTextBlock(
                        title: "Release notes",
                        bodyText: releaseNotes
                    )
                }
            }

            SettingsGroup(title: "Dashboard query limits") {
                SettingsRow(
                    title: "Pull requests",
                    subtitle: "Maximum PRs loaded per configured repository."
                ) {
                    HStack(spacing: 8) {
                        Text("\(model.graphQLSearchResultLimit)")
                            .monospacedDigit()
                        Stepper(
                            "Pull requests",
                            value: Binding(
                                get: { model.graphQLSearchResultLimit },
                                set: { model.graphQLSearchResultLimit = $0 }
                            ),
                            in: AppSettings.allowedGraphQLConnectionLimitRange
                        )
                        .fixedSize()
                    }
                }

                SettingsRow(
                    title: "Review threads",
                    subtitle: "Maximum review threads loaded per PR."
                ) {
                    HStack(spacing: 8) {
                        Text("\(model.graphQLReviewThreadLimit)")
                            .monospacedDigit()
                        Stepper(
                            "Review threads",
                            value: Binding(
                                get: { model.graphQLReviewThreadLimit },
                                set: { model.graphQLReviewThreadLimit = $0 }
                            ),
                            in: AppSettings.allowedGraphQLConnectionLimitRange
                        )
                        .fixedSize()
                    }
                }

                SettingsRow(
                    title: "Comments per thread",
                    subtitle: "Latest comments loaded for each review thread."
                ) {
                    HStack(spacing: 8) {
                        Text("\(model.graphQLReviewThreadCommentLimit)")
                            .monospacedDigit()
                        Stepper(
                            "Comments per thread",
                            value: Binding(
                                get: { model.graphQLReviewThreadCommentLimit },
                                set: { model.graphQLReviewThreadCommentLimit = $0 }
                            ),
                            in: AppSettings.allowedGraphQLReviewThreadCommentLimitRange
                        )
                        .fixedSize()
                    }
                }

                SettingsRow(
                    title: "Check contexts",
                    subtitle: "Maximum check runs/status contexts loaded per PR."
                ) {
                    HStack(spacing: 8) {
                        Text("\(model.graphQLCheckContextLimit)")
                            .monospacedDigit()
                        Stepper(
                            "Check contexts",
                            value: Binding(
                                get: { model.graphQLCheckContextLimit },
                                set: { model.graphQLCheckContextLimit = $0 }
                            ),
                            in: AppSettings.allowedGraphQLConnectionLimitRange
                        )
                        .fixedSize()
                    }
                }
            } footer: {
                Label(model.graphQLDashboardLimitAdvisoryMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var updateStatusColor: Color {
        switch softwareUpdateModel.state {
        case .upToDate: .green
        case .failed: .red
        case .idle, .checking, .updateAvailable, .installing: .secondary
        }
    }

    private var updateStatusLine: String {
        switch softwareUpdateModel.state {
        case .idle:
            return "Check the project’s latest GitHub Release."
        case .checking:
            return "Contacting GitHub Releases."
        case .upToDate:
            return softwareUpdateModel.lastCheckedAt.map {
                "You’re up to date · checked \($0.formatted(date: .omitted, time: .shortened))"
            } ?? "You’re up to date."
        case .updateAvailable(let update):
            return "Download, verify, and install GHOrchestrator \(update.version)."
        case .installing:
            return "GHOrchestrator will relaunch after the update is copied."
        case .failed:
            return "The latest check did not complete."
        }
    }
}

struct GitHubSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Group {
            SettingsGroup(title: "Connection") {
                SettingsRow(title: "Status") {
                    Text(model.authenticationDescription)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                }

                switch model.authenticationState {
                case .authenticated(let username):

                    SettingsTextBlock(
                        title: "Account",
                        bodyText: "Signed in as \(username).\nThe dashboard can fetch GitHub data with this account."
                    )

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

                    SettingsTextBlock(
                        title: "OAuth not configured",
                        bodyText: "This build does not include a GitHub OAuth client ID. Add `clientID` to `Config/GitHubOAuth.local.json` before generating/building the app, or use the build-time env var fallback. The GitHub OAuth app must also have device flow enabled."
                    )

                    SettingsRow(
                        title: "Create OAuth App",
                        subtitle: "Open GitHub’s OAuth app registration page in your browser."
                    ) {
                        Link("Open Registration Page", destination: AppMetadata.gitHubOAuthAppRegistrationURL)
                    }

                    SettingsRow(
                        title: "Setup Guide",
                        subtitle: "Open the GitHub docs for the exact OAuth app creation steps."
                    ) {
                        Link("Open GitHub Docs", destination: AppMetadata.gitHubOAuthAppDocsURL)
                    }
                case .signedOut:

                    SettingsTextBlock(
                        title: "Sign in",
                        bodyText: "Start GitHub sign-in to get a one-time device code, then approve that code in your browser."
                    )

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

                    if let userCode = model.deviceAuthorizationUserCode {
                        SettingsTextBlock(
                            title: "Approve device code",
                            bodyText: "Enter this one-time code on GitHub to finish sign-in."
                        )

                        SettingsRow(
                            title: "Verification code",
                            subtitle: "GitHub expires this code after a short window."
                        ) {
                            Text(userCode)
                                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                                .textSelection(.enabled)
                        }

                        if let verificationURI = model.deviceAuthorizationVerificationURI {

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

                        SettingsRow(
                            title: "Progress",
                            subtitle: "Waiting for GitHub to issue the device code."
                        ) {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                case .authFailure(let message):

                    SettingsTextBlock(
                        title: "Authentication failed",
                        bodyText: message
                    )

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

struct RepositorySettingsPane: View {
    @Bindable var model: SettingsModel
    @State private var selectedRepositoryIDs = Set<String>()

    var body: some View {
        Group {
            SettingsGroup(title: "Observed repositories") {
                VStack(spacing: 0) {
                    Group {
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
                        }
                    }
                    .frame(minHeight: 240)

                    HStack(spacing: 8) {
                        Button {
                            presentAddRepositoryAlert()
                        } label: {
                            Label("Add Repository", systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .frame(width: 22, height: 16)
                        }

                        Button {
                            model.removeObservedRepositories(withIDs: selectedRepositoryIDs)
                            selectedRepositoryIDs.removeAll()
                        } label: {
                            Label("Remove Repositories", systemImage: "minus")
                                .labelStyle(.iconOnly)
                                .frame(width: 22, height: 16)
                        }
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

struct NotificationSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Group {
            SettingsGroup(title: "Permission") {
                NotificationPermissionBanner(
                    title: notificationPermissionTitle,
                    message: notificationPermissionSubtitle,
                    systemImage: notificationPermissionSymbol,
                    tint: notificationPermissionColor
                )

                if model.canRequestNotificationAuthorization {
                    SettingsRow(
                        title: "Enable Notifications",
                        subtitle: "Allow GHOrchestrator to deliver local macOS alerts for matching repository events."
                    ) {
                        Button("Enable") {
                            model.requestNotificationAuthorization()
                        }
                    }
                }
            }

            if model.observedRepositories.isEmpty {
                SettingsGroup(title: "Repository triggers") {
                    SettingsTextBlock(
                        title: "No repositories configured",
                        bodyText: "Add repositories before enabling notification triggers."
                    )
                }
            } else {
                ForEach(model.observedRepositories) { repository in
                    SettingsGroup(title: repository.fullName) {
                        RepositoryNotificationSettingsRows(
                            repository: repository,
                            model: model
                        )
                    }
                }

                Text("Notification polling checks all open PRs in enabled repositories, independent of the dashboard filter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

#if DEBUG
            NotificationDebugPreviewGroup(
                model: model,
                preview: model.notificationDebugPreview
            )
#endif
        }
    }

    private var notificationPermissionTitle: String {
        switch model.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral: "Notifications allowed"
        case .denied: "Notifications blocked"
        case .notDetermined: "Permission needed"
        case .unknown: "Permission unknown"
        }
    }

    private var notificationPermissionSymbol: String {
        switch model.notificationAuthorizationStatus {
        case .authorized, .provisional, .ephemeral: "checkmark.circle.fill"
        case .denied: "xmark.octagon.fill"
        case .notDetermined, .unknown: "bell.badge"
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
        let isEnabled = model.isRepositoryNotificationsEnabled(repositoryID: repository.id)

        SettingsRow(
            title: "Watch this repository",
            subtitle: "Evaluate all open pull requests in this repository."
        ) {
            Toggle(
                "Repository notifications",
                isOn: Binding(
                    get: { isEnabled },
                    set: { newValue in
                        model.setRepositoryNotificationsEnabled(
                            newValue,
                            repositoryID: repository.id
                        )
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .task {
            model.loadWorkflowNamesIfNeeded(repositoryID: repository.id)
        }

        ForEach(RepositoryNotificationTrigger.allCases, id: \.self) { trigger in
            NotificationTriggerToggleRow(
                trigger: trigger,
                repositoryID: repository.id,
                model: model
            )
            .padding(.leading, 14)
            .disabled(!isEnabled)
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
        .padding(.leading, 14)
        .disabled(!isEnabled)

        SettingsRow(
            title: "Job filters",
            subtitle: "Optional job names for job-completion alerts. Empty selection matches every job in a workflow."
        ) {
            WorkflowJobFilterPicker(
                repositoryID: repository.id,
                model: model
            )
        }
        .padding(.leading, 14)
        .disabled(!isEnabled)
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
                trigger.settingsTitle,
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

private struct NotificationPermissionBanner: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .imageScale(.large)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .accessibilityElement(children: .combine)
    }
}

struct SettingsGroup<Content: View, Footer: View>: View {
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)
                .accessibilityAddTraits(.isHeader)

            Group(subviews: content) { subviews in
                VStack(spacing: 0) {
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        if index > 0 {
                            Divider()
                        }
                        subview
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }

            footer
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let subtitleColor: Color
    @ViewBuilder let accessory: Accessory

    init(
        title: String,
        subtitle: String? = nil,
        subtitleColor: Color = .secondary,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            accessory
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsTextBlock: View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
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
            }
        }
        .padding(.vertical, 10)
    }
}
