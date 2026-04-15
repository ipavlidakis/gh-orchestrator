import Charts
import GHOrchestratorCore
import SwiftUI

struct ActionsInsightsSettingsPane: View {
    @Bindable var model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Filters") {
                SettingsRow(
                    title: "Repository",
                    subtitle: "Choose one observed repository."
                ) {
                    repositoryPicker
                }

                Divider()

                SettingsRow(
                    title: "Workflow",
                    subtitle: "Load workflows for the selected repository."
                ) {
                    workflowControl
                }

                Divider()

                SettingsRow(
                    title: "Job",
                    subtitle: "Use all jobs for workflow-level duration, or pick one job for job-level duration."
                ) {
                    jobControl
                }

                Divider()

                SettingsRow(
                    title: "Period",
                    subtitle: "Last month is the previous calendar month."
                ) {
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.actionsInsightsPeriod },
                            set: { model.actionsInsightsPeriod = $0 }
                        )
                    ) {
                        ForEach(ActionsInsightsPeriod.allCases) { period in
                            Text(period.title)
                                .tag(period)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                Divider()

                SettingsRow(
                    title: "Actions",
                    subtitle: refreshSubtitle
                ) {
                    HStack(spacing: 10) {
                        if case .loading = model.actionsInsightsState {
                            ProgressView()
                                .controlSize(.small)
                        }

                        Button("Refresh") {
                            model.refreshActionsInsights()
                        }
                        .disabled(!model.canRefreshActionsInsights || isLoading)
                    }
                }
            } footer: {
                Text("Metrics are fetched live from GitHub for the selected period; only these filter choices are saved.")
            }

            SettingsGroup(title: "Summary") {
                summaryContent
            } footer: {
                if let dashboard = model.actionsInsightsState.dashboard,
                   dashboard.isWorkflowRunResultCapped || dashboard.isJobResultCapped {
                    Label("GitHub returned more results than this dashboard loaded. Narrow the period if exact totals matter.", systemImage: "exclamationmark.triangle.fill")
                }
            }

            SettingsGroup(title: "Trends") {
                trendContent
            } footer: {
                Text("Workflow duration uses run start to completion. Job duration uses the selected job’s own start and completion timestamps.")
            }
        }
        .task {
            model.loadActionsInsightsDependenciesIfNeeded()
        }
    }

    private var repositoryPicker: some View {
        Picker(
            "",
            selection: Binding(
                get: { model.actionsInsightsSelectedRepositoryID ?? "" },
                set: { model.setActionsInsightsRepositoryID($0.isEmpty ? nil : $0) }
            )
        ) {
            if model.observedRepositories.isEmpty {
                Text("No repositories")
                    .tag("")
            } else {
                ForEach(model.observedRepositories) { repository in
                    Text(repository.fullName)
                        .tag(repository.id)
                }
            }
        }
        .labelsHidden()
        .frame(width: 220)
        .disabled(model.observedRepositories.isEmpty)
    }

    @ViewBuilder
    private var workflowControl: some View {
        if let repository = model.actionsInsightsSelectedRepository {
            switch model.workflowListState(repositoryID: repository.id) {
            case .idle:
                Button("Load Workflows") {
                    model.loadWorkflowNamesIfNeeded(repositoryID: repository.id)
                }
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .failed:
                Button("Retry") {
                    model.refreshWorkflowNames(repositoryID: repository.id)
                }
            case .loaded:
                let workflows = model.availableWorkflows(repositoryID: repository.id)
                if workflows.isEmpty {
                    Text("No workflows")
                        .foregroundStyle(.secondary)
                } else {
                    Picker(
                        "",
                        selection: Binding<Int?>(
                            get: { model.actionsInsightsSelectedWorkflowID },
                            set: { model.setActionsInsightsWorkflowID($0) }
                        )
                    ) {
                        ForEach(workflows) { workflow in
                            Text(workflow.name)
                                .tag(Optional(workflow.id))
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
            }
        } else {
            Text("No repository")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var jobControl: some View {
        if let repository = model.actionsInsightsSelectedRepository,
           let workflow = model.actionsInsightsSelectedWorkflow {
            switch model.workflowJobListState(repositoryID: repository.id, workflowName: workflow.name) {
            case .idle:
                Button("Load Jobs") {
                    model.loadWorkflowJobNamesIfNeeded(repositoryID: repository.id, workflow: workflow)
                }
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .failed:
                Button("Retry") {
                    model.refreshWorkflowJobNames(repositoryID: repository.id, workflow: workflow)
                }
            case .loaded(let jobNames):
                Picker(
                    "",
                    selection: Binding(
                        get: { model.actionsInsightsSelectedJobName ?? "" },
                        set: { model.setActionsInsightsJobName($0.isEmpty ? nil : $0) }
                    )
                ) {
                    Text("All jobs")
                        .tag("")

                    ForEach(jobNames, id: \.self) { jobName in
                        Text(jobName)
                            .tag(jobName)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
            }
        } else {
            Text("All jobs")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var summaryContent: some View {
        switch model.actionsInsightsState {
        case .idle:
            SettingsTextBlock(
                title: "No data loaded",
                bodyText: "Choose a repository and workflow, then refresh to load Actions insights."
            )
        case .loading:
            SettingsRow(
                title: "Loading",
                subtitle: "Fetching workflow runs and jobs from GitHub."
            ) {
                ProgressView()
                    .controlSize(.small)
            }
        case .failed(let message):
            SettingsTextBlock(
                title: "Could not load insights",
                bodyText: message
            )
        case .loaded(let dashboard):
            if dashboard.summary.totalCount == 0 {
                SettingsTextBlock(
                    title: "No completed results",
                    bodyText: "No completed workflow runs or selected jobs matched the filters."
                )
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ActionsInsightsMetricRow(
                        title: "Completed",
                        value: "\(dashboard.summary.totalCount)",
                        systemImage: "checklist"
                    )

                    Divider()

                    ActionsInsightsMetricRow(
                        title: "Success rate",
                        value: percentageText(dashboard.summary.successRate),
                        systemImage: "checkmark.circle"
                    )

                    Divider()

                    ActionsInsightsMetricRow(
                        title: "Failures",
                        value: "\(dashboard.summary.failureCount)",
                        systemImage: "xmark.circle"
                    )

                    Divider()

                    ActionsInsightsMetricRow(
                        title: "Average duration",
                        value: durationText(dashboard.summary.averageDurationSeconds),
                        systemImage: "timer"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var trendContent: some View {
        if let dashboard = model.actionsInsightsState.dashboard {
            if dashboard.dataPoints.isEmpty {
                SettingsTextBlock(
                    title: "No chart data",
                    bodyText: "Completed results will appear here when the selected period has matching runs."
                )
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Success and failure rate")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Chart {
                            ForEach(dashboard.dataPoints) { point in
                                if let successRate = point.successRate {
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value("Rate", successRate * 100)
                                    )
                                    .foregroundStyle(by: .value("Result", "Success"))
                                }

                                if let failureRate = point.failureRate {
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value("Rate", failureRate * 100)
                                    )
                                    .foregroundStyle(by: .value("Result", "Failure"))
                                }
                            }
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 180)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Average duration")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Chart {
                            ForEach(dashboard.dataPoints) { point in
                                if let averageDurationSeconds = point.averageDurationSeconds {
                                    LineMark(
                                        x: .value("Date", point.date),
                                        y: .value("Minutes", averageDurationSeconds / 60)
                                    )
                                }
                            }
                        }
                        .frame(height: 180)
                    }
                }
                .padding(.vertical, 10)
            }
        } else {
            SettingsTextBlock(
                title: "No chart data",
                bodyText: "Refresh the dashboard after choosing filters."
            )
        }
    }

    private var refreshSubtitle: String {
        if case .authenticated = model.authenticationState {
            return "Fetch live Actions metrics for the selected filters."
        }

        return "Sign in before loading Actions metrics."
    }

    private var isLoading: Bool {
        if case .loading = model.actionsInsightsState {
            return true
        }

        return false
    }

    private func percentageText(_ rate: Double?) -> String {
        guard let rate else {
            return "No data"
        }

        return rate.formatted(.percent.precision(.fractionLength(1)))
    }

    private func durationText(_ seconds: TimeInterval?) -> String {
        guard let seconds else {
            return "No data"
        }

        let totalSeconds = max(0, Int(seconds.rounded()))
        if totalSeconds < 60 {
            return "\(max(totalSeconds, 1))s"
        }

        let totalMinutes = totalSeconds / 60
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }

        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}

private struct ActionsInsightsMetricRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(title)

            Spacer()

            Text(value)
                .font(.headline.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 10)
    }
}
