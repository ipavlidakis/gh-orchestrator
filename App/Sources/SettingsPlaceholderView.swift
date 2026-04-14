import GHOrchestratorCore
import Observation
import SwiftUI

struct SettingsWindowView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                SectionCard(title: "gh CLI") {
                    cliStatusSection
                }

                SectionCard(title: "Repository allowlist") {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $model.repositoryText)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 150)
                            .overlay(alignment: .topLeading) {
                                if model.repositoryText.isEmpty {
                                    Text("owner/name")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 10)
                                }
                            }

                        Text("One repository per line. Duplicates are ignored.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !model.repositoryValidationMessages.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(model.repositoryValidationMessages, id: \.self) { message in
                                    Label(message, systemImage: "exclamationmark.triangle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                    }
                }

                SectionCard(title: "Polling") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            TextField("Seconds", text: $model.pollingIntervalText)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)

                            Stepper(
                                value: Binding(
                                    get: { model.pollingIntervalStepperValue },
                                    set: { model.pollingIntervalText = String($0) }
                                ),
                                in: AppSettings.allowedPollingIntervalRange,
                                step: 15
                            ) {
                                Text("\(model.pollingIntervalStepperValue) seconds")
                            }
                        }

                        Text("Range: 15 to 900 seconds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let message = model.pollingIntervalValidationMessage {
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionCard(title: "Manual refresh") {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Refresh dashboard now") {
                            model.requestManualRefresh()
                        }
                        .disabled(!model.hasManualRefreshAction)

                        Text(model.hasManualRefreshAction ? "Calls the existing dashboard refresh path." : "No dashboard refresh hook is connected yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 680, idealWidth: 760, minHeight: 620, idealHeight: 720)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.largeTitle.bold())

            Text("Keep the CLI, allowlist, and polling loop in sync.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var cliStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Status") {
                Text(model.cliHealthDescription)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(statusColor)
            }

            switch model.cliHealth {
            case .missing:
                cliSetupBlock(
                    headline: "Install GitHub CLI, then sign in.",
                    details: "Run these from Terminal:",
                    commands: ["brew install gh", "gh auth login"]
                )
            case .loggedOut:
                cliSetupBlock(
                    headline: "GitHub CLI is installed, but no active login was found.",
                    details: "Authenticate from Terminal:",
                    commands: ["gh auth login"]
                )
            case .authenticated(let username):
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signed in as \(username).")
                    Text("The dashboard can fetch GitHub data with this account.")
                        .foregroundStyle(.secondary)
                }
            case .commandFailure(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Text("CLI health check failed.")
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("If needed, re-run `gh --version` and `gh auth status` from Terminal.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func cliSetupBlock(headline: String, details: String, commands: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(headline)

            Text(details)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(commands, id: \.self) { command in
                    CommandLineView(command: command)
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

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

private struct CommandLineView: View {
    let command: String

    var body: some View {
        Text(command)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
