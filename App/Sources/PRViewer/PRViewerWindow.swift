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
        window.titleVisibility = .hidden
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
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
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
            if let summary = model.summary {
                Label(summary.state == "OPEN" ? summary.isDraft ? "Draft" : "Open" : summary.state.capitalized, systemImage: "arrow.triangle.pull")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(summary.state == "OPEN" && !summary.isDraft ? StatusTint.success.color : StatusTint.neutral.color)
                    .padding(.vertical, 6)
            }
            Text("\(model.address.repository.name) #\(model.address.number)").foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            if !model.loading.isEmpty { ProgressView().controlSize(.small) }
        }.font(.system(size: 13)).fixedSize(horizontal: true, vertical: false).padding(.horizontal, 12)
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
    @State private var showsAllChecks = false

    var body: some View {
        VStack(spacing: 0) {
            if model.rows.isEmpty && !model.loading.isEmpty {
                ProgressView("Loading pull request…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PRConversationWebView(model: model, revision: model.revision, focusRevision: model.focusRevision, openURL: openContentURL ?? openBrowser, openBrowser: openBrowser)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background(.regularMaterial)
        .inspector(isPresented: .constant(true)) { sidebar.inspectorColumnWidth(320) }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(isPresented: $model.composerPresented) { composer }
        .sheet(isPresented: $model.textEditorPresented) { textEditor }
        .sheet(isPresented: $model.mergeConfirmationPresented) { mergeConfirmation }
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
            }.padding(8)
        } else {
            pagination.buttonStyle(.bordered).controlSize(.small)
                .background(.bar)
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
            ForEach(model.errors.keys.sorted().filter { ($0 != "Merge" || !model.mergeConfirmationPresented) && ($0 != "Comment" || !model.composerPresented) && ($0 != "PR text" || !model.textEditorPresented) && (!["Find reviewers", "Request review"].contains($0) || !model.reviewerPickerPresented) }, id: \.self) { key in
                HStack {
                    Label("\(key.hasPrefix("Reaction:") ? "Reaction" : key.hasPrefix("Resolve:") ? "Thread action" : key): \(model.errors[key] ?? "")", systemImage: "exclamationmark.triangle")
                        .font(.caption).textSelection(.enabled)
                    Spacer()
                    if key == "Comment" { Button("Open draft") { model.compose(threadID: model.composerThreadID) } }
                    else if key == "PR text" { Button("Open draft") { model.editText() } }
                    else if key == "Request review" { Button("Open reviewer picker") { model.reviewerPickerPresented = true } }
                    else if key == "Description" { Button("Refresh description") { model.loadSummary() } }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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

    private var textEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Cancel") { model.textEditorPresented = false }
                    .keyboardShortcut(.cancelAction).disabled(model.loading.contains("PR text"))
                Text("Edit pull request").font(.headline).frame(maxWidth: .infinity)
                if model.loading.contains("PR text") { ProgressView().controlSize(.small) }
                Button("Save") { model.saveText() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .modifier(PRViewerSubmitStyle(glass: !reduceTransparency))
                    .disabled(!model.canSaveText)
            }.buttonStyle(.bordered)
            TextField("Title", text: $model.titleDraft)
                .textFieldStyle(.roundedBorder).font(.headline).accessibilityLabel("Pull request title")
                .disabled(model.loading.contains("PR text"))
            Text("Description").font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $model.descriptionDraft)
                .scrollContentBackground(.hidden).font(.system(size: 14)).padding(8).frame(height: 280)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
                .disabled(model.loading.contains("PR text"))
                .accessibilityLabel("Pull request description, GitHub Markdown supported")
            if let error = model.errors["PR text"] {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).textSelection(.enabled)
            }
            Text("GitHub Markdown supported").font(.caption).foregroundStyle(.secondary)
        }
        .padding(24).frame(width: 640)
        .interactiveDismissDisabled(model.loading.contains("PR text"))
    }

    private var reviewerPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add reviewers").font(.headline)
            TextField("Search by name or username", text: $model.reviewerQuery)
                .textFieldStyle(.roundedBorder).accessibilityLabel("Search reviewers")
                .onChange(of: model.reviewerQuery) { _, _ in model.searchReviewers() }
                .disabled(model.loading.contains("Request review"))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.reviewerCandidates) { reviewer in
                        Button { model.selectReviewer(reviewer) } label: {
                            HStack(spacing: 8) {
                                reviewerAvatar(url: reviewer.avatarUrl, login: reviewer.login)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(reviewer.login).foregroundStyle(.primary)
                                    if let name = reviewer.name, !name.isEmpty { Text(name).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if model.selectedReviewers.contains(where: { $0.id == reviewer.id }) { Image(systemName: "checkmark").accessibilityLabel("Selected") }
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(model.loading.contains("Request review"))
                    }
                    if model.loading.contains("Find reviewers") { ProgressView().frame(maxWidth: .infinity) }
                    else if model.reviewerCandidates.isEmpty { empty("No matching reviewers") }
                    if let cursor = model.reviewersCursor {
                        Button("Load more reviewers") { model.searchReviewers(after: cursor) }
                            .disabled(model.loading.contains("Find reviewers"))
                    }
                }
            }.frame(height: 240)
            ForEach(["Find reviewers", "Request review"], id: \.self) { key in
                if let error = model.errors[key] {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).textSelection(.enabled)
                    if key == "Find reviewers" { Button("Retry search") { model.searchReviewers() } }
                }
            }
            HStack {
                Button("Cancel") { model.reviewerPickerPresented = false }
                    .keyboardShortcut(.cancelAction).disabled(model.loading.contains("Request review"))
                Spacer()
                if model.loading.contains("Request review") { ProgressView().controlSize(.small) }
                Button("Request review\(model.selectedReviewers.isEmpty ? "" : " (\(model.selectedReviewers.count))")") { model.requestSelectedReviewers() }
                    .modifier(PRViewerSubmitStyle(glass: !reduceTransparency))
                    .disabled(!model.canEditText || model.selectedReviewers.isEmpty)
            }
        }.padding(20).frame(width: 360)
        .interactiveDismissDisabled(model.loading.contains("Request review"))
    }

    private func reviewerAvatar(url: URL?, login: String) -> some View {
        AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
            Text(String(login.prefix(2)).uppercased()).font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(.regularMaterial)
        }
        .frame(width: 28, height: 28).clipShape(Circle()).accessibilityHidden(true)
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                sectionTitle("Changes")
                if let summary = model.summary {
                    HStack(spacing: 8) {
                        Label(summary.changedFiles.map { "\($0) files" } ?? "Changes", systemImage: "doc.badge.plus")
                        Text("+\(summary.additions)").foregroundStyle(StatusTint.success.color)
                        Text("−\(summary.deletions)").foregroundStyle(StatusTint.danger.color)
                    }
                }
                Divider()
                reviewsSection
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
                                        Text(threadTitle(thread))
                                            .font(.system(size: 12, weight: .regular)).lineLimit(1)
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
                DisclosureGroup(isExpanded: $checksExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.checks.isEmpty { empty("No checks reported") }
                        ForEach(showsAllChecks ? model.checks : Array(model.checks.prefix(4))) { check in
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
                        if model.checks.count > 4 {
                            Button(showsAllChecks ? "Show less" : "Show more") { showsAllChecks.toggle() }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                        if model.checksCursor != nil {
                            Button("Load more checks") { model.loadChecks() }.disabled(model.loading.contains("Checks"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: { checksHeader }
                Divider()
                mergeSection
            }
            .disclosureGroupStyle(PRViewerSidebarDisclosureStyle())
            .font(.system(size: 14))
            .padding(.horizontal, 24).padding(.vertical, 28)
        }
    }

    private var reviewsSection: some View {
        DisclosureGroup(isExpanded: $reviewsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                if let decision = model.summary?.reviewDecision {
                    Text(decision.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.summary?.reviewRequests?.nodes ?? []) { request in
                    if let reviewer = request.requestedReviewer {
                        HStack(spacing: 8) {
                            reviewerAvatar(url: reviewer.avatarUrl, login: reviewer.login)
                            Text(reviewer.login).lineLimit(1)
                            Spacer()
                            Image(systemName: "clock").foregroundStyle(.secondary).accessibilityLabel("Review requested")
                        }.help("Review requested from \(reviewer.login)")
                    } else if request.isTeam {
                        Button { openBrowser(model.address.url) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "person.3").frame(width: 28, height: 28).foregroundStyle(.secondary)
                                Text("Team review requested").lineLimit(1)
                                Spacer()
                                Image(systemName: "clock").foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel("View requested team review on GitHub")
                            .help("View the requested team on GitHub")
                    }
                }
                if model.summary?.reviewRequests?.pageInfo.hasNextPage == true {
                    Button("More reviewers on GitHub") { openBrowser(model.address.url) }.font(.caption)
                }
                if !model.activity.contains(where: { $0.kind == "PullRequestReview" }) && (model.summary?.reviewRequests?.nodes.isEmpty ?? true) { empty("No reviews") }
                ForEach(model.sidebarReviews) { review in
                    Button { model.focus(rowID: review.id) } label: {
                        HStack(spacing: 8) {
                            reviewerAvatar(url: review.author?.avatarUrl, login: review.author?.login ?? "?")
                            Text(review.author?.login ?? "Deleted user").lineLimit(1)
                            Spacer()
                            Image(systemName: review.state == "APPROVED" ? "checkmark.circle" : review.state == "CHANGES_REQUESTED" ? "xmark.circle" : "bubble.left")
                                .foregroundStyle(review.state == "APPROVED" ? StatusTint.success.color : review.state == "CHANGES_REQUESTED" ? StatusTint.danger.color : .secondary)
                                .accessibilityLabel(review.state?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Reviewed")
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        } label: { sectionTitle("Reviews").frame(maxWidth: .infinity, alignment: .leading) }
        .overlay(alignment: .topTrailing) {
            Button { model.openReviewerPicker() } label: { Image(systemName: "plus").frame(width: 28, height: 32) }
                .buttonStyle(.plain).accessibilityLabel("Add reviewers").help("Search and request reviewers")
                .disabled(!model.canEditText)
                .popover(isPresented: $model.reviewerPickerPresented) { reviewerPicker }
        }
    }

    private var mergeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Merge status")
            if let summary = model.summary {
                let blocked = summary.state == "OPEN" && (summary.mergeable == "CONFLICTING" || ["BLOCKED", "BEHIND"].contains(summary.mergeStateStatus ?? ""))
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: mergeSymbol(summary))
                        .foregroundStyle(blocked ? StatusTint.danger.color : summary.state == "CLOSED" ? StatusTint.neutral.color : summary.state == "MERGED" || summary.mergeable == "MERGEABLE" ? StatusTint.success.color : StatusTint.neutral.color)
                    Text(mergeText(summary))
                        .foregroundStyle(blocked ? StatusTint.danger.color : .primary)
                }
                    .font(.system(size: 14, weight: blocked ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
                if summary.state == "OPEN" && summary.mergeable == "CONFLICTING" {
                    Text("Use GitHub's web editor or the command line to resolve conflicts with \(summary.baseRefName) before continuing.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Resolve conflicts") { openBrowser(model.address.url.appendingPathComponent("conflicts")) }
                        .buttonStyle(.bordered).controlSize(.small).help("Open conflict resolution on GitHub")
                }
                if summary.state == "OPEN" && !summary.isDraft {
                    if summary.isMergeQueueEnabled == true {
                        Text("This branch uses a merge queue.").font(.caption).foregroundStyle(.secondary)
                        Button("Open merge queue on GitHub") { openBrowser(model.address.url) }
                    } else if let repository = summary.repository, repository.canWrite || (summary.autoMergeRequest != nil && summary.viewerCanDisableAutoMerge == true), !repository.methods.isEmpty {
                        mergeControls(summary, repository: repository)
                    }
                }
            }
        }
    }

    private func mergeControls(_ summary: PRSummary, repository: PRMergeRepository) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let autoMerge = summary.autoMergeRequest {
                Text("Auto-merge enabled (\(mergeMethodTitle(autoMerge.mergeMethod))).").font(.caption).foregroundStyle(.secondary)
                Button("Disable auto-merge") { model.beginMerge(.disableAutoMerge) }
                    .disabled(model.isWriting || model.loading.contains("Summary") || summary.viewerCanDisableAutoMerge != true)
            } else {
                Picker("Merge method", selection: $model.mergeMethod) {
                    ForEach(repository.methods, id: \.self) { method in Text(mergeMethodTitle(method)).tag(method) }
                }
                .pickerStyle(.menu)
                .disabled(model.isWriting || model.loading.contains("Summary"))
                if summary.mergeable == "MERGEABLE", summary.viewerCanMergeAsAdmin == true,
                   ["BLOCKED", "BEHIND"].contains(summary.mergeStateStatus ?? ""), summary.isMergeQueueEnabled == false {
                    Toggle("Merge without waiting for requirements (bypass rules)", isOn: $model.bypassMergeRules)
                        .toggleStyle(.checkbox).font(.caption).foregroundStyle(StatusTint.danger.color)
                        .disabled(model.isWriting || model.loading.contains("Summary"))
                }
                Button(model.bypassMergeRules ? "Bypass rules and merge (\(model.mergeMethod.rawValue.lowercased()))" : mergeMethodTitle(model.mergeMethod)) { model.beginMerge(.merge) }
                    .modifier(PRViewerSubmitStyle(glass: !reduceTransparency))
                    .tint(model.bypassMergeRules ? StatusTint.danger.color : StatusTint.success.color)
                    .disabled(model.isWriting || model.loading.contains("Summary") || !summary.canMerge(method: model.mergeMethod, bypassRules: model.bypassMergeRules))
                if repository.autoMergeAllowed && summary.viewerCanEnableAutoMerge == true {
                    Button("Enable auto-merge (\(model.mergeMethod.rawValue.lowercased()))") { model.beginMerge(.enableAutoMerge) }
                        .disabled(model.isWriting || model.loading.contains("Summary") || model.bypassMergeRules || !summary.canEnableAutoMerge(method: model.mergeMethod))
                }
            }
        }
    }

    private var mergeConfirmation: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let request = model.pendingMerge {
                let title = request.action == .enableAutoMerge ? "Enable auto-merge" : request.action == .disableAutoMerge ? "Disable auto-merge" : mergeMethodTitle(request.method)
                Text(title).font(.title2.bold())
                Text(model.summary?.title ?? "Pull request #\(model.address.number)")
                Text("\(model.summary?.headRefName ?? "") → \(request.expectedBaseRefName) · \(request.expectedHeadOID.prefix(7))").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if request.action != .disableAutoMerge {
                    Text(mergeMethodDescription(request.method)).font(.callout)
                }
                if request.action == .enableAutoMerge { Text("GitHub will merge when required reviews and checks pass.").font(.callout) }
                if request.bypassRules { Label("This merge bypasses branch requirements.", systemImage: "exclamationmark.triangle").foregroundStyle(StatusTint.danger.color) }
                if let error = model.errors["Merge"] {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Refresh merge status") { model.cancelMerge(); model.loadSummary() }.disabled(model.isWriting)
                }
                HStack {
                    Button("Cancel") { model.cancelMerge() }.keyboardShortcut(.cancelAction).disabled(model.isWriting)
                    Spacer()
                    if model.loading.contains("Merge") { ProgressView().controlSize(.small) }
                    Button(request.bypassRules ? "Bypass rules and merge" : title) { model.confirmMerge() }
                        .keyboardShortcut(.defaultAction).modifier(PRViewerSubmitStyle(glass: !reduceTransparency))
                        .tint(request.bypassRules ? StatusTint.danger.color : .accentColor).disabled(model.isWriting)
                }
            }
        }
        .padding(24).frame(width: 460).interactiveDismissDisabled(model.isWriting)
    }

    private func mergeMethodTitle(_ method: PRMergeMethod) -> String {
        switch method { case .merge: "Create a merge commit"; case .squash: "Squash and merge"; case .rebase: "Rebase and merge" }
    }

    private func mergeMethodDescription(_ method: PRMergeMethod) -> String {
        switch method {
        case .merge: "Add all commits to the base branch with a merge commit."
        case .squash: "Combine all commits into one commit on the base branch."
        case .rebase: "Rebase each commit and add it to the base branch."
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 14)).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
    }
    private func threadTitle(_ thread: PRThread) -> String {
        let line = thread.comments.nodes.first?.body.components(separatedBy: .newlines).first ?? thread.path
        return (try? AttributedString(markdown: line)).map { String($0.characters) } ?? line
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
        if summary.mergeable == "MERGEABLE", ["BLOCKED", "BEHIND"].contains(summary.mergeStateStatus ?? "") { return "Merging is blocked by branch requirements" }
        switch summary.mergeable {
        case "MERGEABLE": return "Can merge without conflicts"
        case "CONFLICTING": return "This branch has conflicts that must be resolved"
        default: return "GitHub is calculating merge status"
        }
    }
    private func mergeSymbol(_ summary: PRSummary) -> String {
        if summary.state == "CLOSED" { return "xmark.circle" }
        if summary.state == "OPEN", ["BLOCKED", "BEHIND"].contains(summary.mergeStateStatus ?? "") { return "exclamationmark.triangle.fill" }
        return summary.state == "MERGED" || summary.mergeable == "MERGEABLE" ? "checkmark.circle.fill" : summary.mergeable == "CONFLICTING" ? "exclamationmark.triangle.fill" : "clock"
    }
    private func checkTint(_ check: PRCheck) -> StatusTint {
        PRViewerCheckCounts.tint(check)
    }
    private func checkLabel(_ check: PRCheck) -> some View {
        HStack(spacing: 12) {
            Image(systemName: checkSymbol(check)).foregroundStyle(checkTint(check).color)
            Text(check.name).foregroundStyle(.primary)
        }
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
        case "Summary", "Merge": model.loadSummary()
        case "Activity": model.loadActivity()
        case "Threads": model.loadThreads()
        case "Checks": model.loadChecks()
        case "Find reviewers": model.searchReviewers()
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
