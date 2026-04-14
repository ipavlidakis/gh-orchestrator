import GHOrchestratorCore
import SwiftUI

struct SettingsPlaceholderView: View {
    var body: some View {
        Form {
            LabeledContent("App", value: AppMetadata.menuBarTitle)
            LabeledContent("Core module", value: GHOrchestratorCore.placeholderMessage)
            LabeledContent("Status", value: "Scaffold ready")
        }
        .padding(20)
        .frame(width: 420, height: 180)
    }
}
