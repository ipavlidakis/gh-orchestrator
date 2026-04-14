import AppKit
import Carbon.HIToolbox
import Foundation

extension Notification.Name {
    static let gitHubOAuthCallbackReceived = Notification.Name("GHOrchestrator.gitHubOAuthCallbackReceived")
}

final class GitHubAuthURLHandler: NSObject {
    static let shared = GitHubAuthURLHandler()

    private var isInstalled = false

    func installIfNeeded() {
        guard !isInstalled else {
            return
        }

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        isInstalled = true
    }

    @objc
    private func handleGetURLEvent(
        _ event: NSAppleEventDescriptor,
        withReplyEvent replyEvent: NSAppleEventDescriptor
    ) {
        guard
            let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: urlString)
        else {
            return
        }

        NotificationCenter.default.post(
            name: .gitHubOAuthCallbackReceived,
            object: url
        )
    }
}
