import Foundation
import GHOrchestratorCore
import Observation

@Observable
final class SettingsModel {
    private var isUpdatingPollingIntervalText = false

    let store: SettingsStore
    private let manualRefreshAction: (() -> Void)?
    private let signInAction: (() -> Void)?
    private let signOutAction: (() -> Void)?
    private let requestNotificationAuthorizationAction: (() -> Void)?
    private let openLoginItemsSettingsAction: (() -> Void)?
    private let workflowListService: (any ActionsWorkflowListing)?
    private let workflowJobListService: (any ActionsWorkflowJobListing)?
    private let actionsInsightsService: (any ActionsInsightsLoading)?

    @ObservationIgnored
    private var workflowListTasksByRepositoryID: [String: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var workflowJobListTasksByKey: [String: Task<Void, Never>] = [:]

    @ObservationIgnored
    private var actionsInsightsTask: Task<Void, Never>?

    var repositoryText: String {
        didSet {
            syncRepositories()
        }
    }

    private(set) var repositoryValidationMessages: [String]

    var pollingIntervalText: String {
        didSet {
            syncPollingInterval()
        }
    }

    private(set) var pollingIntervalValidationMessage: String?

    var authenticationState: GitHubAuthenticationState
    var notificationAuthorizationStatus: LocalNotificationAuthorizationStatus
    var workflowListStatesByRepositoryID: [String: SettingsWorkflowListState] = [:]
    var workflowJobListStatesByKey: [String: SettingsWorkflowListState] = [:]
    var workflowItemsByRepositoryID: [String: [ActionsWorkflowItem]] = [:]
    var actionsInsightsState: SettingsActionsInsightsState = .idle
    var hideDockIcon: Bool {
        didSet {
            syncHideDockIcon()
        }
    }
    var startAtLogin: Bool {
        didSet {
            syncStartAtLogin()
        }
    }
    var startAtLoginRegistrationStatus: StartAtLoginRegistrationStatus
    var startAtLoginErrorMessage: String?

    init(
        store: SettingsStore = SettingsStore(),
        authenticationState: GitHubAuthenticationState = .signedOut,
        notificationAuthorizationStatus: LocalNotificationAuthorizationStatus = .notDetermined,
        startAtLoginRegistrationStatus: StartAtLoginRegistrationStatus = .disabled,
        manualRefreshAction: (() -> Void)? = nil,
        signInAction: (() -> Void)? = nil,
        signOutAction: (() -> Void)? = nil,
        requestNotificationAuthorizationAction: (() -> Void)? = nil,
        openLoginItemsSettingsAction: (() -> Void)? = nil,
        workflowListService: (any ActionsWorkflowListing)? = nil,
        workflowJobListService: (any ActionsWorkflowJobListing)? = nil,
        actionsInsightsService: (any ActionsInsightsLoading)? = nil
    ) {
        self.store = store
        self.authenticationState = authenticationState
        self.notificationAuthorizationStatus = notificationAuthorizationStatus
        self.manualRefreshAction = manualRefreshAction
        self.signInAction = signInAction
        self.signOutAction = signOutAction
        self.requestNotificationAuthorizationAction = requestNotificationAuthorizationAction
        self.openLoginItemsSettingsAction = openLoginItemsSettingsAction
        self.workflowListService = workflowListService
        self.workflowJobListService = workflowJobListService
        self.actionsInsightsService = actionsInsightsService
        self.repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        self.repositoryValidationMessages = []
        self.pollingIntervalText = String(store.settings.pollingIntervalSeconds)
        self.pollingIntervalValidationMessage = nil
        self.hideDockIcon = store.settings.hideDockIcon
        self.startAtLogin = store.settings.startAtLogin
        self.startAtLoginRegistrationStatus = startAtLoginRegistrationStatus
        self.startAtLoginErrorMessage = nil
    }

    deinit {
        workflowListTasksByRepositoryID.values.forEach { $0.cancel() }
        workflowJobListTasksByKey.values.forEach { $0.cancel() }
        actionsInsightsTask?.cancel()
    }

    var settings: AppSettings {
        store.settings
    }

    var authenticationDescription: String {
        switch authenticationState {
        case .notConfigured:
            return "OAuth is not configured for this build"
        case .signedOut:
            return "Not signed in"
        case .authorizing(let userCode, _):
            if let userCode, !userCode.isEmpty {
                return "Waiting for code \(userCode) to be approved"
            }

            return "Requesting a GitHub device sign-in code"
        case .authenticated(let username):
            return "Signed in as \(username)"
        case .authFailure(let message):
            return "Authentication failed: \(message)"
        }
    }

    var hasManualRefreshAction: Bool {
        manualRefreshAction != nil
    }

    var canStartSignIn: Bool {
        guard signInAction != nil else {
            return false
        }

        switch authenticationState {
        case .authorizing, .notConfigured:
            return false
        case .signedOut, .authenticated, .authFailure:
            return true
        }
    }

    var canSignOut: Bool {
        if case .authenticated = authenticationState {
            return signOutAction != nil
        }

        return false
    }

    var observedRepositories: [ObservedRepository] {
        store.settings.observedRepositories
    }

    var actionsInsightsSelectedRepository: ObservedRepository? {
        if let repositoryID = store.settings.actionsInsightsSelection.repositoryID,
           let repository = store.settings.observedRepositories.first(where: {
               $0.normalizedLookupKey == RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
           }) {
            return repository
        }

        return store.settings.observedRepositories.first
    }

    var actionsInsightsSelectedRepositoryID: String? {
        actionsInsightsSelectedRepository?.id
    }

    var actionsInsightsSelectedWorkflow: ActionsWorkflowItem? {
        guard let repository = actionsInsightsSelectedRepository else {
            return nil
        }

        let workflows = availableWorkflows(repositoryID: repository.id)
        let selection = store.settings.actionsInsightsSelection

        if let workflowID = selection.workflowID,
           let workflow = workflows.first(where: { $0.id == workflowID }) {
            return workflow
        }

        if let workflowName = selection.workflowName,
           let workflow = workflows.first(where: {
               RepositoryNotificationSettings.normalizedWorkflowName($0.name) ==
                   RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
           }) {
            return workflow
        }

        return workflows.first
    }

    var actionsInsightsSelectedWorkflowID: Int? {
        actionsInsightsSelectedWorkflow?.id
    }

    var actionsInsightsSelectedJobName: String? {
        store.settings.actionsInsightsSelection.jobName
    }

    var canRefreshActionsInsights: Bool {
        guard case .authenticated = authenticationState else {
            return false
        }

        return actionsInsightsSelectedRepository != nil &&
            actionsInsightsSelectedWorkflow != nil
    }

    var actionsInsightsPeriod: ActionsInsightsPeriod {
        get { store.settings.actionsInsightsSelection.period }
        set {
            updateActionsInsightsSelection { selection in
                selection.period = newValue
            }
            actionsInsightsState = .idle
        }
    }

    var notificationAuthorizationDescription: String {
        notificationAuthorizationStatus.description
    }

    var canRequestNotificationAuthorization: Bool {
        guard requestNotificationAuthorizationAction != nil else {
            return false
        }

        switch notificationAuthorizationStatus {
        case .notDetermined, .unknown:
            return true
        case .denied, .authorized, .provisional, .ephemeral:
            return false
        }
    }

    var pollingIntervalStepperValue: Int {
        Int(pollingIntervalText) ?? store.settings.pollingIntervalSeconds
    }

    var pollingIntervalAdvisoryMessage: String? {
        guard pollingIntervalValidationMessage == nil,
              store.settings.pollingIntervalSeconds < AppSettings.defaultPollingIntervalSeconds
        else {
            return nil
        }

        return "Short polling intervals can hit GitHub API rate limits, especially with many repositories or Actions checks. Use 60 seconds or longer unless you need faster updates."
    }

    var startAtLoginSubtitle: String {
        if let startAtLoginStatusMessage {
            return startAtLoginStatusMessage
        }

        return "Launch GHOrchestrator automatically when you sign in."
    }

    var startAtLoginStatusMessage: String? {
        if let startAtLoginErrorMessage {
            return "Could not update login item: \(startAtLoginErrorMessage)"
        }

        switch startAtLoginRegistrationStatus {
        case .enabled:
            return startAtLogin ? "GHOrchestrator is registered to launch at login." : nil
        case .disabled:
            return nil
        case .requiresApproval:
            return "macOS needs approval in Login Items before GHOrchestrator can launch at login."
        case .notFound:
            return "macOS could not find GHOrchestrator as a login item. Move the app to Applications and try again."
        case .unknown:
            return "macOS returned an unrecognized login item state."
        }
    }

    var canOpenLoginItemsSettings: Bool {
        openLoginItemsSettingsAction != nil &&
            (startAtLoginErrorMessage != nil ||
             startAtLoginRegistrationStatus == .requiresApproval ||
             startAtLoginRegistrationStatus == .notFound ||
             startAtLoginRegistrationStatus == .unknown)
    }

    var graphQLSearchResultLimit: Int {
        get { store.settings.graphQLSearchResultLimit }
        set {
            store.settings.graphQLSearchResultLimit = AppSettings.clampGraphQLConnectionLimit(newValue)
        }
    }

    var graphQLReviewThreadLimit: Int {
        get { store.settings.graphQLReviewThreadLimit }
        set {
            store.settings.graphQLReviewThreadLimit = AppSettings.clampGraphQLConnectionLimit(newValue)
        }
    }

    var graphQLReviewThreadCommentLimit: Int {
        get { store.settings.graphQLReviewThreadCommentLimit }
        set {
            store.settings.graphQLReviewThreadCommentLimit = AppSettings.clampGraphQLReviewThreadCommentLimit(newValue)
        }
    }

    var graphQLCheckContextLimit: Int {
        get { store.settings.graphQLCheckContextLimit }
        set {
            store.settings.graphQLCheckContextLimit = AppSettings.clampGraphQLConnectionLimit(newValue)
        }
    }

    var graphQLDashboardLimitAdvisoryMessage: String {
        "Higher limits can multiply GraphQL cost because review threads, comments, and check contexts are nested under every returned PR."
    }

    var deviceAuthorizationUserCode: String? {
        guard case .authorizing(let userCode, _) = authenticationState else {
            return nil
        }

        return userCode
    }

    var deviceAuthorizationVerificationURI: URL? {
        guard case .authorizing(_, let verificationURI) = authenticationState else {
            return nil
        }

        return verificationURI
    }

    func reloadFromStore() {
        repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        repositoryValidationMessages = []
        pollingIntervalText = String(store.settings.pollingIntervalSeconds)
        pollingIntervalValidationMessage = nil
        hideDockIcon = store.settings.hideDockIcon
        startAtLogin = store.settings.startAtLogin
    }

    func requestManualRefresh() {
        manualRefreshAction?()
    }

    func requestSignIn() {
        signInAction?()
    }

    func requestSignOut() {
        signOutAction?()
    }

    func requestNotificationAuthorization() {
        requestNotificationAuthorizationAction?()
    }

    func requestOpenLoginItemsSettings() {
        openLoginItemsSettingsAction?()
    }

    func setActionsInsightsRepositoryID(_ repositoryID: String?) {
        let normalizedRepositoryID = repositoryID.map(RepositoryNotificationSettings.normalizedRepositoryID)
        updateActionsInsightsSelection { selection in
            selection.repositoryID = normalizedRepositoryID
            selection.workflowID = nil
            selection.workflowName = nil
            selection.jobName = nil
        }
        actionsInsightsState = .idle

        if let normalizedRepositoryID {
            loadWorkflowNamesIfNeeded(repositoryID: normalizedRepositoryID)
        }
    }

    func setActionsInsightsWorkflowID(_ workflowID: Int?) {
        let workflow = workflowID.flatMap { id in
            actionsInsightsSelectedRepository.flatMap {
                availableWorkflows(repositoryID: $0.id).first(where: { $0.id == id })
            }
        }

        updateActionsInsightsSelection { selection in
            selection.workflowID = workflow?.id
            selection.workflowName = workflow?.name
            selection.jobName = nil
        }
        actionsInsightsState = .idle

        if let repository = actionsInsightsSelectedRepository,
           let workflow {
            loadWorkflowJobNamesIfNeeded(repositoryID: repository.id, workflow: workflow)
        }
    }

    func setActionsInsightsJobName(_ jobName: String?) {
        let trimmed = jobName?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateActionsInsightsSelection { selection in
            selection.jobName = trimmed?.isEmpty == false ? trimmed : nil
        }
        actionsInsightsState = .idle
    }

    func loadActionsInsightsDependenciesIfNeeded() {
        guard let repository = actionsInsightsSelectedRepository else {
            return
        }

        loadWorkflowNamesIfNeeded(repositoryID: repository.id)

        if let workflow = actionsInsightsSelectedWorkflow {
            loadWorkflowJobNamesIfNeeded(repositoryID: repository.id, workflow: workflow)
        }
    }

    func refreshActionsInsights(now: Date = Date()) {
        actionsInsightsTask?.cancel()

        guard let actionsInsightsService else {
            actionsInsightsState = .failed("Sign in before loading Actions insights.")
            return
        }

        guard case .authenticated = authenticationState else {
            actionsInsightsState = .failed("Sign in with GitHub before loading Actions insights.")
            return
        }

        guard let repository = actionsInsightsSelectedRepository else {
            actionsInsightsState = .failed("Add a repository before loading Actions insights.")
            return
        }

        guard let workflow = actionsInsightsSelectedWorkflow else {
            actionsInsightsState = .failed("Load and choose a workflow before loading Actions insights.")
            loadWorkflowNamesIfNeeded(repositoryID: repository.id)
            return
        }

        let selectedJobName = actionsInsightsSelectedJobName
        let selectedPeriod = actionsInsightsPeriod
        actionsInsightsState = .loading

        let task = Task { [actionsInsightsService] in
            do {
                let dashboard = try await actionsInsightsService.loadInsights(
                    repository: repository,
                    workflow: workflow,
                    jobName: selectedJobName,
                    period: selectedPeriod,
                    now: now
                )
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.actionsInsightsState = .loaded(dashboard)
                    self.actionsInsightsTask = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.actionsInsightsState = .failed(error.localizedDescription)
                    self.actionsInsightsTask = nil
                }
            }
        }

        actionsInsightsTask = task
    }

    @discardableResult
    func addObservedRepository(from rawValue: String) -> Bool {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            repositoryValidationMessages = ["Enter a repository in owner/name format."]
            return false
        }

        guard let repository = ObservedRepository(rawValue: trimmed) else {
            repositoryValidationMessages = ["Invalid repository entry: \(trimmed)"]
            return false
        }

        if store.settings.observedRepositories.contains(where: { $0.normalizedLookupKey == repository.normalizedLookupKey }) {
            repositoryValidationMessages = ["Repository already added: \(repository.fullName)"]
            return false
        }

        repositoryValidationMessages = []
        store.settings.observedRepositories.append(repository)
        repositoryText = Self.repositoryText(from: store.settings.observedRepositories)
        return true
    }

    func removeObservedRepositories(withIDs ids: Set<String>) {
        guard !ids.isEmpty else {
            return
        }

        let normalizedIDs = Set(
            ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )

        guard !normalizedIDs.isEmpty else {
            return
        }

        let updatedRepositories = store.settings.observedRepositories.filter { repository in
            !normalizedIDs.contains(repository.id)
        }

        guard updatedRepositories != store.settings.observedRepositories else {
            return
        }

        repositoryValidationMessages = []

        var updatedSettings = store.settings
        updatedSettings.observedRepositories = updatedRepositories
        updatedSettings.reconcileNotificationSettingsWithObservedRepositories()
        updatedSettings.reconcileActionsInsightsSelectionWithObservedRepositories()
        store.settings = updatedSettings
        repositoryText = Self.repositoryText(from: updatedRepositories)
    }

    func repositoryNotificationSettings(
        for repository: ObservedRepository
    ) -> RepositoryNotificationSettings {
        store.settings.effectiveNotificationSettings(for: repository)
    }

    func isRepositoryNotificationsEnabled(repositoryID: String) -> Bool {
        store.settings
            .notificationSettings(forRepositoryID: repositoryID)?
            .enabled ?? false
    }

    func setRepositoryNotificationsEnabled(
        _ isEnabled: Bool,
        repositoryID: String
    ) {
        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            settings.enabled = isEnabled
        }
    }

    func isNotificationTriggerEnabled(
        _ trigger: RepositoryNotificationTrigger,
        repositoryID: String
    ) -> Bool {
        repositoryNotificationSettings(forRepositoryID: repositoryID).enabledTriggers.contains(trigger)
    }

    func setNotificationTrigger(
        _ trigger: RepositoryNotificationTrigger,
        isEnabled: Bool,
        repositoryID: String
    ) {
        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            if isEnabled {
                settings.enabledTriggers.insert(trigger)
            } else {
                settings.enabledTriggers.remove(trigger)
            }
        }
    }

    func workflowNameFilterText(repositoryID: String) -> String {
        repositoryNotificationSettings(forRepositoryID: repositoryID)
            .workflowNameFilters
            .joined(separator: "\n")
    }

    func setWorkflowNameFilterText(
        _ text: String,
        repositoryID: String
    ) {
        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            settings.workflowNameFilters = RepositoryNotificationSettings.parseWorkflowNameFilters(from: text)
        }
    }

    func workflowListState(repositoryID: String) -> SettingsWorkflowListState {
        workflowListStatesByRepositoryID[
            RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        ] ?? .idle
    }

    func loadWorkflowNamesIfNeeded(repositoryID: String) {
        let normalizedRepositoryID = RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        switch workflowListState(repositoryID: normalizedRepositoryID) {
        case .idle, .failed:
            loadWorkflowNames(repositoryID: normalizedRepositoryID)
        case .loading, .loaded:
            return
        }
    }

    func refreshWorkflowNames(repositoryID: String) {
        let normalizedRepositoryID = RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        workflowListTasksByRepositoryID[normalizedRepositoryID]?.cancel()
        workflowListTasksByRepositoryID[normalizedRepositoryID] = nil
        loadWorkflowNames(repositoryID: normalizedRepositoryID)
    }

    func availableWorkflowNames(repositoryID: String) -> [String] {
        workflowListState(repositoryID: repositoryID).workflowNames
    }

    func availableWorkflows(repositoryID: String) -> [ActionsWorkflowItem] {
        workflowItemsByRepositoryID[
            RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        ] ?? []
    }

    func isWorkflowNameFilterSelected(
        _ workflowName: String,
        repositoryID: String
    ) -> Bool {
        let normalizedWorkflowName = RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
        return repositoryNotificationSettings(forRepositoryID: repositoryID)
            .workflowNameFilters
            .contains(normalizedWorkflowName)
    }

    func setWorkflowNameFilter(
        _ workflowName: String,
        isSelected: Bool,
        repositoryID: String
    ) {
        let normalizedWorkflowName = RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
        guard !normalizedWorkflowName.isEmpty else {
            return
        }

        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            var filters = settings.workflowNameFilters

            if isSelected {
                if !filters.contains(normalizedWorkflowName) {
                    filters.append(normalizedWorkflowName)
                }
            } else {
                filters.removeAll { $0 == normalizedWorkflowName }
            }

            settings.workflowNameFilters = RepositoryNotificationSettings.normalizedWorkflowNameFilters(filters)
        }
    }

    func clearWorkflowNameFilters(repositoryID: String) {
        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            settings.workflowNameFilters = []
        }
    }

    func workflowNameFilterSummary(repositoryID: String) -> String {
        let filters = repositoryNotificationSettings(forRepositoryID: repositoryID).workflowNameFilters
        guard !filters.isEmpty else {
            return "All workflows"
        }

        return "\(filters.count) selected"
    }

    func workflowJobListState(
        repositoryID: String,
        workflowName: String
    ) -> SettingsWorkflowListState {
        workflowJobListStatesByKey[
            workflowJobListStateKey(
                repositoryID: repositoryID,
                workflowName: workflowName
            )
        ] ?? .idle
    }

    func loadWorkflowJobNamesIfNeeded(
        repositoryID: String,
        workflow: ActionsWorkflowItem
    ) {
        let key = workflowJobListStateKey(
            repositoryID: repositoryID,
            workflowName: workflow.name
        )

        switch workflowJobListStatesByKey[key] ?? .idle {
        case .idle, .failed:
            loadWorkflowJobNames(
                repositoryID: repositoryID,
                workflow: workflow
            )
        case .loading, .loaded:
            return
        }
    }

    func refreshWorkflowJobNames(
        repositoryID: String,
        workflow: ActionsWorkflowItem
    ) {
        let key = workflowJobListStateKey(
            repositoryID: repositoryID,
            workflowName: workflow.name
        )
        workflowJobListTasksByKey[key]?.cancel()
        workflowJobListTasksByKey[key] = nil
        loadWorkflowJobNames(
            repositoryID: repositoryID,
            workflow: workflow
        )
    }

    func isWorkflowJobNameFilterSelected(
        _ jobName: String,
        repositoryID: String,
        workflowName: String
    ) -> Bool {
        let normalizedWorkflowName = RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
        let normalizedJobName = RepositoryNotificationSettings.normalizedWorkflowJobName(jobName)
        return repositoryNotificationSettings(forRepositoryID: repositoryID)
            .workflowJobNameFiltersByWorkflowName[normalizedWorkflowName]?
            .contains(normalizedJobName) ?? false
    }

    func setWorkflowJobNameFilter(
        _ jobName: String,
        isSelected: Bool,
        repositoryID: String,
        workflowName: String
    ) {
        let normalizedWorkflowName = RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
        let normalizedJobName = RepositoryNotificationSettings.normalizedWorkflowJobName(jobName)
        guard !normalizedWorkflowName.isEmpty, !normalizedJobName.isEmpty else {
            return
        }

        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            var filtersByWorkflowName = settings.workflowJobNameFiltersByWorkflowName
            var filters = filtersByWorkflowName[normalizedWorkflowName] ?? []

            if isSelected {
                if !filters.contains(normalizedJobName) {
                    filters.append(normalizedJobName)
                }
            } else {
                filters.removeAll { $0 == normalizedJobName }
            }

            filtersByWorkflowName[normalizedWorkflowName] = filters
            settings.workflowJobNameFiltersByWorkflowName = RepositoryNotificationSettings.normalizedWorkflowJobNameFilters(filtersByWorkflowName)
        }
    }

    func clearWorkflowJobNameFilters(
        repositoryID: String,
        workflowName: String
    ) {
        let normalizedWorkflowName = RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
        updateRepositoryNotificationSettings(repositoryID: repositoryID) { settings in
            settings.workflowJobNameFiltersByWorkflowName[normalizedWorkflowName] = nil
        }
    }

    func workflowJobNameFilterSummary(
        repositoryID: String,
        workflowName: String
    ) -> String {
        let normalizedWorkflowName = RepositoryNotificationSettings.normalizedWorkflowName(workflowName)
        let filters = repositoryNotificationSettings(forRepositoryID: repositoryID)
            .workflowJobNameFiltersByWorkflowName[normalizedWorkflowName] ?? []

        guard !filters.isEmpty else {
            return "All jobs"
        }

        return "\(filters.count) selected"
    }

    private func syncRepositories() {
        let parseResult = ObservedRepository.parseList(from: repositoryText)

        repositoryValidationMessages = parseResult.invalidEntries.map {
            "Invalid repository entry: \($0)"
        }

        if store.settings.observedRepositories != parseResult.repositories {
            var updatedSettings = store.settings
            updatedSettings.observedRepositories = parseResult.repositories
            updatedSettings.reconcileNotificationSettingsWithObservedRepositories()
            updatedSettings.reconcileActionsInsightsSelectionWithObservedRepositories()
            store.settings = updatedSettings
        }
    }

    private func syncPollingInterval() {
        guard !isUpdatingPollingIntervalText else {
            return
        }

        let trimmed = pollingIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = Int(trimmed) else {
            pollingIntervalValidationMessage = "Polling interval must be a whole number."
            return
        }

        let clamped = AppSettings.clampPollingInterval(parsed)
        pollingIntervalValidationMessage = parsed == clamped ? nil : "Polling interval must be between 15 and 900 seconds."

        if pollingIntervalText != String(clamped) {
            isUpdatingPollingIntervalText = true
            pollingIntervalText = String(clamped)
            isUpdatingPollingIntervalText = false
        }

        if store.settings.pollingIntervalSeconds != clamped {
            store.settings.pollingIntervalSeconds = clamped
        }
    }

    private func syncHideDockIcon() {
        if store.settings.hideDockIcon != hideDockIcon {
            store.settings.hideDockIcon = hideDockIcon
        }
    }

    private func syncStartAtLogin() {
        if store.settings.startAtLogin != startAtLogin {
            store.settings.startAtLogin = startAtLogin
        }
    }

    private func updateActionsInsightsSelection(
        mutate: (inout ActionsInsightsSelection) -> Void
    ) {
        var settings = store.settings
        mutate(&settings.actionsInsightsSelection)
        store.settings = settings
    }

    private func repositoryNotificationSettings(
        forRepositoryID repositoryID: String
    ) -> RepositoryNotificationSettings {
        guard let repository = store.settings.observedRepositories.first(where: {
            $0.normalizedLookupKey == RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        }) else {
            return RepositoryNotificationSettings(repositoryID: repositoryID)
        }

        return repositoryNotificationSettings(for: repository)
    }

    private func updateRepositoryNotificationSettings(
        repositoryID: String,
        mutate: (inout RepositoryNotificationSettings) -> Void
    ) {
        let normalizedRepositoryID = RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        guard let repository = store.settings.observedRepositories.first(where: {
            $0.normalizedLookupKey == normalizedRepositoryID
        }) else {
            return
        }

        var settings = store.settings.effectiveNotificationSettings(for: repository)
        mutate(&settings)
        store.settings.updateNotificationSettings(settings)
    }

    private func loadWorkflowNames(repositoryID: String) {
        guard let workflowListService else {
            workflowListStatesByRepositoryID[repositoryID] = .failed("Sign in before loading repository workflows.")
            return
        }

        guard let repository = store.settings.observedRepositories.first(where: {
            $0.normalizedLookupKey == repositoryID
        }) else {
            return
        }

        workflowListStatesByRepositoryID[repositoryID] = .loading

        let task = Task { [workflowListService] in
            do {
                let workflows = try await workflowListService.listWorkflows(repository: repository)
                guard !Task.isCancelled else {
                    return
                }

                let names = workflows.map(\.name)
                await MainActor.run {
                    self.workflowListStatesByRepositoryID[repositoryID] = .loaded(names)
                    self.workflowItemsByRepositoryID[repositoryID] = workflows
                    self.workflowListTasksByRepositoryID[repositoryID] = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.workflowListStatesByRepositoryID[repositoryID] = .failed(error.localizedDescription)
                    self.workflowListTasksByRepositoryID[repositoryID] = nil
                }
            }
        }

        workflowListTasksByRepositoryID[repositoryID] = task
    }

    private func loadWorkflowJobNames(
        repositoryID: String,
        workflow: ActionsWorkflowItem
    ) {
        let key = workflowJobListStateKey(
            repositoryID: repositoryID,
            workflowName: workflow.name
        )

        guard let workflowJobListService else {
            workflowJobListStatesByKey[key] = .failed("Sign in before loading workflow jobs.")
            return
        }

        let normalizedRepositoryID = RepositoryNotificationSettings.normalizedRepositoryID(repositoryID)
        guard let repository = store.settings.observedRepositories.first(where: {
            $0.normalizedLookupKey == normalizedRepositoryID
        }) else {
            return
        }

        workflowJobListStatesByKey[key] = .loading

        let task = Task { [workflowJobListService] in
            do {
                let jobNames = try await workflowJobListService.listJobNames(
                    repository: repository,
                    workflow: workflow
                )
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.workflowJobListStatesByKey[key] = .loaded(jobNames)
                    self.workflowJobListTasksByKey[key] = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self.workflowJobListStatesByKey[key] = .failed(error.localizedDescription)
                    self.workflowJobListTasksByKey[key] = nil
                }
            }
        }

        workflowJobListTasksByKey[key] = task
    }

    private func workflowJobListStateKey(
        repositoryID: String,
        workflowName: String
    ) -> String {
        "\(RepositoryNotificationSettings.normalizedRepositoryID(repositoryID))::\(RepositoryNotificationSettings.normalizedWorkflowName(workflowName))"
    }

    private static func repositoryText(from repositories: [ObservedRepository]) -> String {
        repositories.map(\.fullName).joined(separator: "\n")
    }
}
