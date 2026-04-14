import AppKit
import GHOrchestratorCore
import SwiftUI

struct MenuBarPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(GHOrchestratorCore.placeholderMessage)
                .font(.headline)

            Text("Menu bar scaffold for GHOrchestrator.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Settings") {
                openSettings()
            }

            Button("Quit GHOrchestrator", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
    }

    private func openSettings() {
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
