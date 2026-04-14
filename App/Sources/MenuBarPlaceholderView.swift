import AppKit
import GHOrchestratorCore
import SwiftUI

struct MenuBarPlaceholderView: View {
    let model: MenuBarDashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(statusTitle)
                .font(.headline)

            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            if case .loaded(let sections) = model.state {
                Text("Loaded \(sections.count) repository section(s).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Open Settings") {
                openSettings()
            }

            Button("Quit GHOrchestrator", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .task {
            model.setMenuVisible(true)
        }
        .onDisappear {
            model.setMenuVisible(false)
        }
    }

    private func openSettings() {
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private var statusTitle: String {
        switch model.state {
        case .idle:
            return GHOrchestratorCore.placeholderMessage
        case .loading:
            return "Refreshing pull requests..."
        case .empty:
            return "No open pull requests"
        case .ghMissing:
            return "Install GitHub CLI"
        case .loggedOut:
            return "Sign in with gh"
        case .noRepositoriesConfigured:
            return "Configure repositories"
        case .commandFailure:
            return "Refresh failed"
        case .loaded:
            return "Dashboard ready"
        }
    }

    private var statusDescription: String {
        switch model.state {
        case .idle:
            return "Menu bar scaffold for GHOrchestrator."
        case .loading:
            return "Fetching the latest pull request state."
        case .empty:
            return "No matching open pull requests were found in the configured repositories."
        case .ghMissing:
            return "Install `gh` from Settings before the dashboard can load."
        case .loggedOut:
            return "Authenticate with `gh auth login` from Settings."
        case .noRepositoriesConfigured:
            return "Add at least one owner/repo entry in Settings."
        case .commandFailure(let message):
            return message
        case .loaded:
            return "Live data is available; richer menu bar UI comes next."
        }
    }
}
