import AppKit
import GHOrchestratorCore
import Observation

@MainActor
@Observable
final class PRViewerModel {
    let address: PullRequestAddress
    private let service: any PullRequestDetailLoading
    private(set) var summary: PRSummary?
    private(set) var activity: [PRActivity] = []
    private(set) var threads: [PRThread] = []
    private(set) var checks: [PRCheck] = []
    private(set) var rows: [PRViewerRow] = []
    private(set) var revision = 0
    private(set) var loading: Set<String> = []
    private(set) var errors: [String: String] = [:]
    private(set) var activityCursor: String?
    private(set) var threadsCursor: String?
    private(set) var checksCursor: String?
    private(set) var focusedRowID: String?
    private(set) var focusRevision = 0
    private(set) var pendingCommentURL: URL?
    var composerPresented = false
    private(set) var composerThreadID: String?
    private var drafts: [String: String] = [:]
    var composerDraft: String {
        get { drafts[composerThreadID ?? "pull-request"] ?? "" }
        set { drafts[composerThreadID ?? "pull-request"] = newValue }
    }
    var isWriting: Bool { loading.contains("Comment") || loading.contains { $0.hasPrefix("Resolve:") || $0.hasPrefix("Reaction:") } }
    var canComment: Bool { summary?.id != nil && summary?.locked != true }
    var canSubmitComment: Bool {
        !loading.contains("Comment") && !composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (composerThreadID == nil ? canComment : threads.contains { $0.id == composerThreadID && $0.viewerCanReply == true })
    }
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var preparationID = UUID()

    init(address: PullRequestAddress, service: any PullRequestDetailLoading) {
        self.address = address
        self.service = service
    }

    func refresh() {
        guard !isWriting else { return }
        cancel()
        summary = nil
        activity = []
        threads = []
        checks = []
        rows = []
        revision += 1
        activityCursor = nil
        threadsCursor = nil
        checksCursor = nil
        errors = [:]
        loadSummary()
        loadActivity()
        loadThreads()
    }

    func cancel() {
        generation = UUID()
        preparationID = UUID()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        preparation?.cancel()
        preparation = nil
        loading = []
    }

    func loadSummary() {
        request("Summary") { [self] in
            let result = try await service.summary(address, checksAfter: nil)
            let cursor = try result.checksPageInfo?.nextCursor()
            return { [self] in summary = result; checks = result.checks; checksCursor = cursor }
        }
    }

    func loadActivity() {
        let cursor = activityCursor
        request("Activity") { [self] in
            let page = try await service.activity(address, after: cursor)
            let next = try page.pageInfo.nextCursor()
            return { [self] in
                let existing = Set(activity.map(\.id))
                activity += page.nodes.filter { !existing.contains($0.id) }
                activityCursor = next
            }
        }
    }

    func loadThreads() {
        let cursor = threadsCursor
        request("Threads") { [self] in
            let page = try await service.threads(address, after: cursor)
            let next = try page.pageInfo.nextCursor()
            return { [self] in
                let existing = Set(threads.map(\.id))
                threads += page.nodes.filter { !existing.contains($0.id) }
                threadsCursor = next
            }
        }
    }

    func loadChecks() {
        guard let cursor = checksCursor else { return }
        request("Checks") { [self] in
            let result = try await service.summary(address, checksAfter: cursor)
            let next = try result.checksPageInfo?.nextCursor()
            return { [self] in
                let existing = Set(checks.map(\.id))
                checks += result.checks.filter { !existing.contains($0.id) }
                checksCursor = next
            }
        }
    }

    func loadReplies(_ threadID: String) {
        guard let thread = threads.first(where: { $0.id == threadID }),
              let cursor = try? thread.comments.pageInfo.nextCursor() else { return }
        request(threadID) { [self] in
            let page = try await service.replies(threadID: threadID, after: cursor)
            return { [self] in
                guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
                threads[index].comments = PRConnection(nodes: threads[index].comments.nodes + page.nodes.filter { comment in !threads[index].comments.nodes.contains(where: { $0.id == comment.id }) }, pageInfo: page.pageInfo)
            }
        }
    }

    func compose(threadID: String? = nil) {
        guard !loading.contains("Comment") else { return }
        if let threadID {
            guard threads.contains(where: { $0.id == threadID && $0.viewerCanReply == true }) else { return }
        } else if !canComment { return }
        composerThreadID = threadID
        errors["Comment"] = nil
        composerPresented = true
    }

    func submitComment() {
        guard canSubmitComment else { return }
        let body = composerDraft
        let threadID = composerThreadID
        guard let subjectID = threadID ?? summary?.id else { return }
        request("Comment") { [self] in
            let comment: PRComment
            if threadID != nil { comment = try await service.reply(threadID: subjectID, body: body) }
            else { comment = try await service.addComment(pullRequestID: subjectID, body: body) }
            return { [self] in
                if let threadID, let index = threads.firstIndex(where: { $0.id == threadID }) {
                    if !threads[index].comments.nodes.contains(where: { $0.id == comment.id }) {
                        threads[index].comments = PRConnection(nodes: threads[index].comments.nodes + [comment], pageInfo: threads[index].comments.pageInfo)
                    }
                } else if threadID == nil, !activity.contains(where: { $0.id == comment.id }) {
                    activity.append(PRActivity(comment: comment))
                }
                drafts[threadID ?? "pull-request"] = nil
                composerPresented = false
                focus(url: comment.url)
            }
        }
    }

    func toggleResolved(_ threadID: String) {
        guard let thread = threads.first(where: { $0.id == threadID }),
              (thread.isResolved ? thread.viewerCanUnresolve : thread.viewerCanResolve) == true else { return }
        request("Resolve:\(threadID)") { [self] in
            let result = try await service.setResolved(threadID: threadID, resolved: !thread.isResolved)
            return { [self] in
                guard let index = threads.firstIndex(where: { $0.id == result.id }) else { return }
                threads[index].isResolved = result.isResolved
                threads[index].viewerCanResolve = result.viewerCanResolve
                threads[index].viewerCanUnresolve = result.viewerCanUnresolve
            }
        }
    }

    func focus(url: URL) {
        pendingCommentURL = url.fragment == nil ? nil : url
        if let row = rows.first(where: { $0.url?.fragment == url.fragment && url.fragment != nil }) {
            focus(rowID: row.id)
            pendingCommentURL = nil
        }
    }

    func toggleReaction(subjectID: String, content: PRReactionContent) {
        guard let row = rows.first(where: { $0.id == subjectID && $0.canReact }),
              !loading.contains("Reaction:\(subjectID)") else { return }
        let added = !row.reactionGroups.contains { $0.content == content && $0.viewerHasReacted }
        request("Reaction:\(subjectID)") { [self] in
            let result = try await service.setReaction(subjectID: subjectID, content: content, added: added)
            return { [self] in
                if let index = activity.firstIndex(where: { $0.id == result.id }) {
                    activity[index].viewerCanReact = result.viewerCanReact
                    activity[index].reactionGroups = result.reactionGroups
                }
                for index in threads.indices {
                    var comments = threads[index].comments.nodes
                    guard let comment = comments.firstIndex(where: { $0.id == result.id }) else { continue }
                    comments[comment].viewerCanReact = result.viewerCanReact
                    comments[comment].reactionGroups = result.reactionGroups
                    threads[index].comments = PRConnection(nodes: comments, pageInfo: threads[index].comments.pageInfo)
                }
            }
        }
        prepareRows()
    }

    func focus(rowID: String?) {
        focusedRowID = rowID
        focusRevision += 1
    }

    private func request(_ key: String, operation: @escaping @MainActor () async throws -> (@MainActor () -> Void)) {
        guard !loading.contains(key) else { return }
        loading.insert(key)
        errors[key] = nil
        let token = generation
        tasks[key] = Task { [weak self] in
            do {
                let apply = try await operation()
                guard let self, self.generation == token, !Task.isCancelled else { return }
                apply()
                self.loading.remove(key)
                self.tasks[key] = nil
                self.prepareRows()
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.errors[key] = error.localizedDescription
                self.loading.remove(key)
                self.tasks[key] = nil
                if key.hasPrefix("Reaction:") { self.prepareRows() }
            }
        }
    }

    private func prepareRows() {
        preparation?.cancel()
        let token = UUID()
        preparationID = token
        let summary = summary, activity = activity, threads = threads, address = address, loading = loading
        let worker = Task.detached(priority: .userInitiated) {
            PRViewerRow.prepare(address: address, summary: summary, activity: activity, threads: threads, loading: loading)
        }
        preparation = Task { [weak self] in
            let prepared = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
            guard let self, !Task.isCancelled, self.preparationID == token else { return }
            self.rows = prepared
            self.revision += 1
            if let url = self.pendingCommentURL { self.focus(url: url) }
        }
    }
}
