import AppKit
import GHOrchestratorCore
import SwiftUI

@MainActor
final class PRViewerWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate, NSToolbarItemValidation {
    let model: PRViewerModel
    private let onClose: () -> Void
    private let openBrowser: (URL) -> Void

    init(address: PullRequestAddress, service: any PullRequestDetailLoading, openBrowser: @escaping (URL) -> Void, openContentURL: ((URL) -> Void)? = nil, onClose: @escaping () -> Void) {
        model = PRViewerModel(address: address, service: service)
        self.onClose = onClose
        self.openBrowser = openBrowser
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "\(address.repository.fullName) #\(address.number)"
        window.minSize = NSSize(width: 860, height: 600)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PRViewer")
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PRViewerWindowView(model: model, openBrowser: openBrowser, openContentURL: openContentURL))
        let toolbar = NSToolbar(identifier: "PRViewer")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
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

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [NSToolbarItem.Identifier("summary"), .flexibleSpace, NSToolbarItem.Identifier("refresh"), NSToolbarItem.Identifier("copy"), NSToolbarItem.Identifier("browser")]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        if identifier.rawValue == "summary" {
            let view = NSHostingView(rootView: PRViewerSummary(model: model))
            view.frame = NSRect(x: 0, y: 0, width: 190, height: 28)
            item.view = view
            item.label = "Summary"
        } else {
            let title: String, symbol: String, action: Selector
            switch identifier.rawValue {
            case "refresh": (title, symbol, action) = ("Refresh pull request", "arrow.clockwise", #selector(refresh))
            case "copy": (title, symbol, action) = ("Copy pull request link", "link", #selector(copyLink))
            case "browser": (title, symbol, action) = ("Open in Browser", "arrow.up.right.square", #selector(openInBrowser))
            default: return nil
            }
            item.label = title; item.toolTip = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            item.target = self; item.action = action
        }
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool { item.itemIdentifier.rawValue != "refresh" || !model.isWriting }
    @objc private func refresh() { if !model.isWriting { model.refresh() } }
    @objc private func copyLink() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(model.address.url.absoluteString, forType: .string)
    }
    @objc private func openInBrowser() { openBrowser(model.address.url) }
}

private struct PRViewerSummary: View {
    let model: PRViewerModel
    var body: some View {
        HStack(spacing: 8) {
            Text("Summary").fontWeight(.semibold)
            if let summary = model.summary {
                Text("+\(summary.additions)").foregroundStyle(StatusTint.success.color)
                Text("−\(summary.deletions)").foregroundStyle(StatusTint.danger.color)
            }
            if !model.loading.isEmpty { ProgressView().controlSize(.small) }
        }.font(.system(size: 12)).padding(.horizontal, 12).fixedSize()
    }
}

struct PRViewerWindowView: View {
    @Bindable var model: PRViewerModel
    let openBrowser: (URL) -> Void
    var openContentURL: ((URL) -> Void)? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var editorFocused: Bool
    @State private var threadsExpanded = true
    @State private var reviewsExpanded = true
    @State private var checksExpanded = true

    var body: some View {
        VStack(spacing: 0) {
            if model.rows.isEmpty && !model.loading.isEmpty {
                ProgressView("Loading pull request…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PRConversationWebView(model: model, revision: model.revision, focusRevision: model.focusRevision, openURL: openContentURL ?? openBrowser, openBrowser: openBrowser)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .inspector(isPresented: .constant(true)) {
            sidebar.inspectorColumnWidth(280)
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $model.composerPresented) { composer }
        .onKeyPress("r", phases: .down) { event in
            guard event.modifiers.contains(.command), !model.isWriting else { return .ignored }
            model.refresh(); return .handled
        }
    }

    @ViewBuilder private var footer: some View {
        if #available(macOS 26, *), !reduceTransparency {
            GlassEffectContainer {
                pagination
                    .buttonStyle(.glass).controlSize(.small)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }.padding(8)
        } else {
            pagination.buttonStyle(.bordered).controlSize(.small)
                .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var pagination: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = model.pendingCommentURL {
                HStack {
                    Text("The linked comment has not loaded yet.").font(.caption).foregroundStyle(.secondary)
                    Button("Open comment on GitHub") { openBrowser(url) }
                }
            }
            ForEach(model.errors.keys.sorted().filter { $0 != "Comment" || !model.composerPresented }, id: \.self) { key in
                HStack {
                    Label("\(key.hasPrefix("Reaction:") ? "Reaction" : key.hasPrefix("Resolve:") ? "Thread action" : key): \(model.errors[key] ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.caption).textSelection(.enabled)
                    Spacer()
                    if key == "Comment" { Button("Open draft") { model.compose(threadID: model.composerThreadID) } }
                    else if !key.hasPrefix("Reaction:") { Button("Retry") { retry(key) } }
                }
            }
            HStack {
                Button("Leave a comment", systemImage: "bubble.left") { model.compose() }
                    .disabled(!model.canComment || model.loading.contains("Comment"))
                    .help(model.summary?.locked == true ? "This conversation is locked. Open GitHub to check access." : "Comment on this pull request")
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

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            composerControls
            if let thread = model.threads.first(where: { $0.id == model.composerThreadID }) {
                Text(thread.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(thread.path)
            }
            ZStack(alignment: .topLeading) {
                if model.composerDraft.isEmpty {
                    Text(model.composerThreadID == nil ? "Write a comment…" : "Write a reply…")
                        .foregroundStyle(.tertiary).padding(.horizontal, 6).padding(.vertical, 8)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                TextEditor(text: $model.composerDraft)
                    .scrollContentBackground(.hidden).focused($editorFocused)
                    .disabled(model.loading.contains("Comment"))
                    .accessibilityLabel("Comment body, GitHub Markdown supported")
            }
            .font(.system(size: 14)).padding(8).frame(height: 168)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
            if let error = model.errors["Comment"] {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).textSelection(.enabled)
            }
            Text("GitHub Markdown supported").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 560)
        .onAppear { editorFocused = true }
        .interactiveDismissDisabled(model.loading.contains("Comment"))
    }

    @ViewBuilder private var composerControls: some View {
        if #available(macOS 26, *), !reduceTransparency {
            GlassEffectContainer { composerActions.buttonStyle(.glass) }
        } else { composerActions.buttonStyle(.bordered) }
    }

    private var composerActions: some View {
        HStack(spacing: 8) {
            Button("Cancel") { model.composerPresented = false }
                .keyboardShortcut(.cancelAction).disabled(model.loading.contains("Comment"))
            Text(model.composerThreadID == nil ? "Leave a comment" : "Reply to thread")
                .font(.headline).frame(maxWidth: .infinity)
            if model.loading.contains("Comment") { ProgressView().controlSize(.small) }
            Button(model.composerThreadID == nil ? "Comment" : "Reply") { model.submitComment() }
                .keyboardShortcut(.return, modifiers: .command)
                .modifier(PRViewerSubmitStyle(glass: !reduceTransparency))
                .disabled(!model.canSubmitComment)
        }
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                sectionTitle("Merge status")
                if let summary = model.summary {
                    Label(mergeText(summary), systemImage: mergeSymbol(summary))
                        .font(.system(size: 13, weight: summary.state == "OPEN" && summary.mergeable == "CONFLICTING" ? .semibold : .regular))
                        .foregroundStyle(summary.state == "CLOSED" ? StatusTint.neutral.color : summary.state == "MERGED" ? StatusTint.success.color : summary.mergeable == "CONFLICTING" ? StatusTint.danger.color : summary.mergeable == "MERGEABLE" ? StatusTint.success.color : StatusTint.neutral.color)
                        .fixedSize(horizontal: false, vertical: true)
                    if summary.state == "OPEN" && summary.mergeable == "CONFLICTING" {
                        Text("Use GitHub's web editor or the command line to resolve conflicts with \(summary.baseRefName) before continuing.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Resolve conflicts") {
                            openBrowser(model.address.url.appendingPathComponent("conflicts"))
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                        .help("Open conflict resolution on GitHub")
                    }
                    Text(summary.state == "OPEN" && summary.isDraft ? "Draft pull request" : summary.state.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                DisclosureGroup(isExpanded: $threadsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.threads.isEmpty { empty("No loaded review threads") }
                        ForEach(model.threads) { thread in
                            Button {
                                model.focus(rowID: thread.comments.nodes.first?.id)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: thread.isResolved || thread.isOutdated ? "checkmark.bubble" : "bubble.left")
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(thread.comments.nodes.first?.body ?? thread.path).lineLimit(2)
                                        Text("\(thread.isOutdated ? "Outdated" : thread.isResolved ? "Resolved" : "Open") · \(thread.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Go to \(thread.isOutdated ? "outdated" : thread.isResolved ? "resolved" : "open") thread in \(thread.path)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { sectionTitle("Threads").frame(maxWidth: .infinity, alignment: .leading) }
                Divider()
                DisclosureGroup(isExpanded: $reviewsExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { sectionTitle("Reviews").frame(maxWidth: .infinity, alignment: .leading) }
                Divider()
                DisclosureGroup(isExpanded: $checksExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { checksHeader }
            }
            .disclosureGroupStyle(PRViewerSidebarDisclosureStyle())
            .font(.system(size: 13))
            .padding(24)
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary).accessibilityAddTraits(.isHeader)
    }
    private var checksHeader: some View {
        let counts = PRViewerCheckCounts(model.checks)
        return HStack(spacing: 6) {
            sectionTitle("Checks").fixedSize()
            Spacer(minLength: 0)
            checkCount(counts.failed, "failed", "xmark.circle.fill", .danger)
            checkCount(counts.succeeded, "succeeded", "checkmark.circle.fill", .success)
            checkCount(counts.running, "running", "clock", .warning)
            checkCount(counts.neutral, "neutral", "minus.circle", .neutral)
        }
        .font(.system(size: 11)).monospacedDigit()
        .accessibilityElement(children: .combine)
        .help("Loaded checks: \(counts.failed) failed, \(counts.succeeded) succeeded, \(counts.running) running, \(counts.neutral) neutral\(model.checksCursor == nil ? "" : "; more checks available")")
    }
    @ViewBuilder private func checkCount(_ count: Int, _ status: String, _ symbol: String, _ tint: StatusTint) -> some View {
        if count > 0 {
            Label("\(count)", systemImage: symbol).foregroundStyle(tint.color)
                .accessibilityLabel("\(count) \(status) checks")
        }
    }
    private func empty(_ title: String) -> some View { Text(title).font(.caption).foregroundStyle(.secondary) }
    private func mergeText(_ summary: PRSummary) -> String {
        if summary.state == "MERGED" { return "Pull request merged" }
        if summary.state == "CLOSED" { return "Pull request closed" }
        switch summary.mergeable {
        case "MERGEABLE": return "Can merge without conflicts"
        case "CONFLICTING": return "This branch has conflicts that must be resolved"
        default: return "GitHub is calculating merge status"
        }
    }
    private func mergeSymbol(_ summary: PRSummary) -> String {
        if summary.state == "CLOSED" { return "xmark.circle" }
        return summary.state == "MERGED" || summary.mergeable == "MERGEABLE" ? "checkmark.circle.fill" : summary.mergeable == "CONFLICTING" ? "exclamationmark.triangle.fill" : "clock"
    }
    private func checkTint(_ check: PRCheck) -> StatusTint {
        PRViewerCheckCounts.tint(check)
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
        default:
            if key.hasPrefix("Resolve:") { model.toggleResolved(String(key.dropFirst("Resolve:".count))) }
            else { model.loadReplies(key) }
        }
    }
}

private struct PRViewerSidebarDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isHeader)
            if configuration.isExpanded { configuration.content }
        }
    }
}

struct PRViewerCheckCounts {
    var failed = 0, succeeded = 0, running = 0, neutral = 0

    init(_ checks: [PRCheck]) {
        for check in checks {
            switch Self.tint(check) {
            case .danger: failed += 1
            case .success: succeeded += 1
            case .warning: running += 1
            case .neutral: neutral += 1
            }
        }
    }

    static func tint(_ check: PRCheck) -> StatusTint {
        switch check.conclusion {
        case "SUCCESS": return .success
        case "FAILURE", "ERROR", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE": return .danger
        case "SKIPPED", "NEUTRAL", "CANCELLED", "STALE": return .neutral
        case "PENDING": return .warning
        default: return check.status == "COMPLETED" ? .neutral : .warning
        }
    }
}

private struct PRViewerSubmitStyle: ViewModifier {
    let glass: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26, *), glass { content.buttonStyle(.glassProminent) }
        else { content.buttonStyle(.borderedProminent) }
    }
}
