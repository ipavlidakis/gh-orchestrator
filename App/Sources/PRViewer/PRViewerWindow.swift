import AppKit
import GHOrchestratorCore
import SwiftUI

@MainActor
final class PRViewerWindowController: NSWindowController, NSWindowDelegate {
    let model: PRViewerModel
    private let onClose: () -> Void

    init(address: PullRequestAddress, service: any PullRequestDetailLoading, openBrowser: @escaping (URL) -> Void, onClose: @escaping () -> Void) {
        model = PRViewerModel(address: address, service: service)
        self.onClose = onClose
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(address.repository.fullName) #\(address.number)"
        window.minSize = NSSize(width: 860, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PRViewer")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: openBrowser))
    }

    required init?(coder: NSCoder) { nil }

    func present(url: URL) {
        if model.rows.isEmpty && model.loading.isEmpty { model.refresh() }
        model.focus(url: url)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model.cancel()
        onClose()
    }
}

struct PRViewerWindowView: View {
    @Bindable var model: PRViewerModel
    let openBrowser: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    if model.rows.isEmpty && !model.loading.isEmpty {
                        ProgressView("Loading pull request…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        PRConversationTable(model: model, openURL: openBrowser)
                    }
                    pagination
                }
                Divider()
                sidebar.frame(width: 280)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            Text("Summary").font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .background(Color.primary.opacity(0.08), in: Capsule())
            if let summary = model.summary {
                Text("+\(summary.additions)").foregroundStyle(StatusTint.success.color)
                Text("−\(summary.deletions)").foregroundStyle(StatusTint.danger.color)
            }
            Spacer()
            if !model.loading.isEmpty { ProgressView().controlSize(.small) }
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .accessibilityLabel("Refresh pull request").help("Refresh pull request")
                .keyboardShortcut("r", modifiers: .command)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.address.url.absoluteString, forType: .string)
            } label: { Image(systemName: "link") }
                .accessibilityLabel("Copy pull request link").help("Copy pull request link")
            Button("Open in Browser", systemImage: "arrow.up.right.square") { openBrowser(model.address.url) }
        }
        .font(.system(size: 12.5))
        .buttonStyle(.borderless)
        .padding(.horizontal, 24).padding(.vertical, 12)
    }

    private var pagination: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = model.pendingCommentURL {
                HStack {
                    Text("The linked comment has not loaded yet.").font(.caption).foregroundStyle(.secondary)
                    Button("Open comment on GitHub") { openBrowser(url) }
                }
            }
            ForEach(model.errors.keys.sorted(), id: \.self) { key in
                HStack {
                    Label("\(key == "Summary" || key == "Activity" || key == "Threads" || key == "Checks" ? key : "Replies"): \(model.errors[key] ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.caption).textSelection(.enabled)
                    Spacer()
                    Button("Retry") { retry(key) }
                }
            }
            HStack {
                if model.activityCursor != nil {
                    Button("Load more activity") { model.loadActivity() }.disabled(model.loading.contains("Activity"))
                }
                if model.threadsCursor != nil {
                    Button("Load more threads") { model.loadThreads() }.disabled(model.loading.contains("Threads"))
                }
                Spacer()
                Text("\(model.activity.count) events · \(model.threads.count) threads loaded")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                sectionTitle("Merge status")
                if let summary = model.summary {
                    Label(mergeText(summary), systemImage: mergeSymbol(summary))
                        .font(.system(size: 13))
                        .foregroundStyle(summary.mergeable == "CONFLICTING" ? StatusTint.danger.color : summary.mergeable == "MERGEABLE" ? StatusTint.success.color : StatusTint.neutral.color)
                    Text(summary.isDraft ? "Draft pull request" : summary.state.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                sectionTitle("Threads")
                if model.threads.isEmpty { empty("No loaded review threads") }
                ForEach(model.threads) { thread in
                    Button {
                        model.focus(rowID: thread.comments.nodes.first?.id)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thread.comments.nodes.first?.body ?? thread.path).lineLimit(2)
                                Text("\(thread.isResolved ? "Resolved" : "Open") · \(thread.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Go to \(thread.isResolved ? "resolved" : "open") thread in \(thread.path)")
                }
                Divider()
                sectionTitle("Reviews loaded")
                if let decision = model.summary?.reviewDecision {
                    Text(decision.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.activity.filter { $0.kind == "PullRequestReview" }) { review in
                    Button {
                        model.focus(rowID: review.id)
                    } label: {
                        Label(review.author?.login ?? "Deleted user", systemImage: review.state == "APPROVED" ? "checkmark.circle" : "bubble.left")
                    }.buttonStyle(.plain)
                }
                Divider()
                sectionTitle("Checks")
                if model.checks.isEmpty { empty("No checks reported") }
                ForEach(model.checks) { check in
                    Group {
                        if let url = check.url {
                            Button { openBrowser(url) } label: { checkLabel(check) }.buttonStyle(.plain)
                        } else {
                            checkLabel(check)
                        }
                    }
                        .help("\(check.name): \(check.conclusion ?? check.status)")
                        .accessibilityLabel("\(check.name): \(check.conclusion ?? check.status)")
                }
                if model.checksCursor != nil {
                    Button("Load more checks") { model.loadChecks() }.disabled(model.loading.contains("Checks"))
                }
            }
            .font(.system(size: 13))
            .padding(24)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
    }
    private func empty(_ title: String) -> some View { Text(title).font(.caption).foregroundStyle(.secondary) }
    private func mergeText(_ summary: PRSummary) -> String {
        if summary.state == "MERGED" { return "Pull request merged" }
        if summary.state == "CLOSED" { return "Pull request closed" }
        switch summary.mergeable {
        case "MERGEABLE": return "Can merge without conflicts"
        case "CONFLICTING": return "Merge conflicts need attention"
        default: return "GitHub is calculating merge status"
        }
    }
    private func mergeSymbol(_ summary: PRSummary) -> String {
        summary.state == "MERGED" || summary.mergeable == "MERGEABLE" ? "checkmark.circle.fill" : summary.mergeable == "CONFLICTING" ? "exclamationmark.triangle" : "clock"
    }
    private func checkTint(_ check: PRCheck) -> StatusTint {
        switch check.conclusion {
        case "SUCCESS": return .success
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE": return .danger
        case "SKIPPED", "NEUTRAL", "CANCELLED", "STALE": return .neutral
        default: return .warning
        }
    }
    private func checkLabel(_ check: PRCheck) -> some View {
        Label(check.name, systemImage: checkSymbol(check))
            .foregroundStyle(checkTint(check).color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private func checkSymbol(_ check: PRCheck) -> String {
        switch checkTint(check) {
        case .success: return "checkmark.circle.fill"
        case .danger: return "xmark.circle.fill"
        case .neutral: return "minus.circle"
        case .warning: return "clock"
        }
    }
    private func retry(_ key: String) {
        switch key {
        case "Summary": model.loadSummary()
        case "Activity": model.loadActivity()
        case "Threads": model.loadThreads()
        case "Checks": model.loadChecks()
        default: model.loadReplies(key)
        }
    }
}
