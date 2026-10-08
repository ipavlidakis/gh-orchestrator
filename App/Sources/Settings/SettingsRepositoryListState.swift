enum SettingsRepositoryListState: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)
}
