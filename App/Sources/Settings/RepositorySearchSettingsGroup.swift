import GHOrchestratorCore
import SwiftUI

struct RepositorySearchSettingsGroup: View {
    @Bindable var model: SettingsModel
    let selectedRepositoryID: String?
    let onSelect: (ObservedRepository) -> Void
    @State private var query = ""
    @State private var repositoryToForget: ObservedRepository?

    var body: some View {
        let repositories = model.repositories(matching: query)
        SettingsGroup(title: "Repositories") {
            if repositories.isEmpty {
                SettingsTextBlock(
                    title: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No configured repositories" : "No matching repositories",
                    bodyText: "Search by repository or owner, then select a repository to configure it."
                )
            } else {
                List(selection: Binding<String?>(
                    get: { selectedRepositoryID },
                    set: { id in
                        if let repository = repositories.first(where: { $0.id == id }) {
                            onSelect(repository)
                            query = ""
                        }
                    }
                )) {
                    ForEach(repositories) { repository in
                        HStack {
                            Text(repository.fullName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if model.isRepositoryNotificationsEnabled(repositoryID: repository.id) {
                                Image(systemName: "bell.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Notifications enabled")
                            }
                        }
                        .frame(minHeight: 24)
                        .help(repository.fullName)
                        .tag(repository.id)
                        .contextMenu {
                            if model.observedRepositories.contains(where: { $0.id == repository.id }) {
                                Button("Forget saved repository settings", role: .destructive) {
                                    repositoryToForget = repository
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(height: min(CGFloat(repositories.count) * 36 + 8, 188))
            }
        } footer: {
            switch model.repositoryListState {
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading repositories from GitHub…")
                }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
            case .idle, .loaded:
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Configured repositories stay here. Search to configure another." : "\(repositories.count) matching repositories. Select one to configure it.")
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search repositories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh repositories", systemImage: "arrow.clockwise") {
                    model.refreshRepositoryCatalog()
                }
                .labelStyle(.iconOnly)
                .help("Refresh repositories from GitHub")
                .disabled(model.repositoryListState == .loading)
            }
        }
        .task { model.loadRepositoryCatalogIfNeeded() }
        .onChange(of: model.authenticationState) { _, _ in model.loadRepositoryCatalogIfNeeded() }
        .confirmationDialog("Forget saved settings for \(repositoryToForget?.fullName ?? "this repository")?", isPresented: Binding(
            get: { repositoryToForget != nil },
            set: { if !$0 { repositoryToForget = nil } }
        )) {
            Button("Forget settings", role: .destructive) {
                if let repositoryToForget {
                    model.removeObservedRepositories(withIDs: [repositoryToForget.id])
                }
                repositoryToForget = nil
            }
        } message: {
            Text("This removes the repository’s notification rules and Insights preferences from this Mac.")
        }
    }
}
