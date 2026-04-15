import Foundation

enum AppMetadata {
    static let menuBarTitle = "GHOrchestrator"
    static let releaseRepositoryOwner = "ipavlidakis"
    static let releaseRepositoryName = "gh-orchestrator"
    static let helpURL = URL(string: "https://github.com/ipavlidakis/gh-orchestrator")!
    static let gitHubOAuthAppRegistrationURL = URL(string: "https://github.com/settings/applications/new")!
    static let gitHubOAuthAppDocsURL = URL(string: "https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}
