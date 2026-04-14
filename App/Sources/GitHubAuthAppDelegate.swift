import AppKit
import Foundation

final class GitHubAuthAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NotificationCenter.default.post(
                name: .gitHubOAuthCallbackReceived,
                object: url
            )
        }
    }
}
