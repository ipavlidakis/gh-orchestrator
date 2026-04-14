import AppKit
import GHOrchestratorCore
import Observation
import SwiftUI

private enum SettingsPane: String, CaseIterable, Hashable, Identifiable {
    case general
    case github
    case repositories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "General"
        case .github:
            return "GitHub CLI"
        case .repositories:
            return "Repositories"
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
        }
    }
}

struct SettingsWindowView: View {
    @Bindable var model: SettingsModel
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
                    GitHubCLISettingsPane(model: model)
                case .repositories:
                    RepositorySettingsPane(model: model)
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
                } else {
                    Text("When the Dock icon is hidden, reopen Settings from the menu bar extra.")
                }
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

private struct GitHubCLISettingsPane: View {
    let model: SettingsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            SettingsGroup(title: "Connection") {
                SettingsRow(title: "Status") {
                    Text(model.cliHealthDescription)
                        .foregroundStyle(statusColor)
                        .multilineTextAlignment(.trailing)
                }

                switch model.cliHealth {
                case .authenticated(let username):
                    Divider()

                    SettingsTextBlock(
                        title: "Account",
                        bodyText: "Signed in as \(username).\nThe dashboard can fetch GitHub data with this account."
                    )

                case .missing:
                    Divider()

                    SettingsTextBlock(
                        title: "Setup",
                        bodyText: "Install GitHub CLI, then sign in."
                    )

                    Divider()

                    CommandListView(commands: ["brew install gh", "gh auth login"])

                case .loggedOut:
                    Divider()

                    SettingsTextBlock(
                        title: "Setup",
                        bodyText: "GitHub CLI is installed, but no active login was found."
                    )

                    Divider()

                    CommandListView(commands: ["gh auth login"])

                case .commandFailure(let message):
                    Divider()

                    SettingsTextBlock(
                        title: "Health check failed",
                        bodyText: "\(message)\nIf needed, re-run `gh --version` and `gh auth status` from Terminal."
                    )
                }
            }
        }
    }

    private var statusColor: Color {
        switch model.cliHealth {
        case .authenticated:
            return .green
        case .missing, .loggedOut, .commandFailure:
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
                            List(model.observedRepositories, selection: $selectedRepositoryIDs) { repository in
                                Text(repository.fullName)
                                    .font(.system(.body, design: .monospaced))
                                    .tag(repository.id)
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
