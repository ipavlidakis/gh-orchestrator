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
    var textEditorPresented = false
    var titleDraft = ""
    var descriptionDraft = ""
    var mergeMethod: PRMergeMethod = .squash
    var bypassMergeRules = false
    var mergeConfirmationPresented = false
    private(set) var pendingMerge: PRMergeRequest?
    private var editingSummary: PRSummary?
    var reviewerPickerPresented = false
    var reviewerQuery = ""
    private(set) var reviewerCandidates: [PRReviewer] = []
    private(set) var reviewersCursor: String?
    private(set) var selectedReviewers: [PRReviewer] = []
    private(set) var composerThreadID: String?
    private var drafts: [String: String] = [:]
    var composerDraft: String {
        get { drafts[composerThreadID ?? "pull-request"] ?? "" }
        set { drafts[composerThreadID ?? "pull-request"] = newValue }
    }
    var isWriting: Bool { loading.contains("Merge") || loading.contains("Description") || loading.contains("PR text") || loading.contains("Request review") || loading.contains("Comment") || loading.contains { $0.hasPrefix("Resolve:") || $0.hasPrefix("Reaction:") } }
    var canEditText: Bool { summary?.viewerCanUpdate == true && summary?.id != nil && !isWriting && !loading.contains("Summary") }
    var canSaveText: Bool {
        canEditText && !titleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (titleDraft != editingSummary?.title || descriptionDraft != editingSummary?.body)
    }
    var sidebarReviews: [PRActivity] {
        let pending = Set(summary?.reviewRequests?.nodes.compactMap { $0.requestedReviewer?.login.lowercased() } ?? [])
        var seen: Set<String> = []
        return activity.reversed().filter { review in
            let login = review.author?.login.lowercased() ?? review.id
            return review.kind == "PullRequestReview" && !pending.contains(login) && seen.insert(login).inserted
        }.reversed()
    }
    var canComment: Bool { summary?.id != nil && summary?.locked != true && !loading.contains("Merge") }
    var canSubmitComment: Bool {
        !loading.contains("Merge") && !loading.contains("Comment") && !composerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
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
        guard !loading.contains("Merge"), !loading.contains("Description"), !loading.contains("PR text"), !loading.contains("Request review") else { return }
        errors["Description"] = nil
        request("Summary") { [self] in
            let result = try await service.summary(address, checksAfter: nil)
            let cursor = try result.checksPageInfo?.nextCursor()
            return { [self] in
                summary = result; checks = result.checks; checksCursor = cursor
                if let method = result.autoMergeRequest?.mergeMethod { mergeMethod = method }
                else if let methods = result.repository?.methods, !methods.contains(mergeMethod), let first = methods.first { mergeMethod = first }
                bypassMergeRules = false
                pendingMerge = nil
                mergeConfirmationPresented = false
                errors["Merge"] = nil
            }
        }
        prepareRows()
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
        guard !loading.contains("Merge"), let thread = threads.first(where: { $0.id == threadID }),
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
        guard !loading.contains("Merge"), let row = rows.first(where: { $0.id == subjectID && $0.canReact }),
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

    func setDescriptionTask(offset: Int, checked: Bool, expectedBody: String) {
        guard let summary, summary.viewerCanUpdate == true, summary.body == expectedBody,
              !loading.contains("Merge"), !loading.contains("Summary"), !loading.contains("Description"), !loading.contains("PR text"),
              PRDescriptionTask.items(in: summary.body).contains(where: { $0.offset == offset }) else { return }
        request("Description") { [self] in
            let result = try await service.setDescriptionTask(address, offset: offset, checked: checked, expectedBody: expectedBody)
            return { [self] in
                self.summary?.body = result.body
                self.summary?.bodyHTML = result.bodyHTML
            }
        }
        prepareRows()
    }

    func editText() {
        guard canEditText, let summary else { return }
        if editingSummary?.title != summary.title || editingSummary?.body != summary.body {
            titleDraft = summary.title
            descriptionDraft = summary.body
            editingSummary = summary
        }
        errors["PR text"] = nil
        textEditorPresented = true
    }

    func saveText() {
        guard canSaveText, let original = editingSummary else { return }
        let title = titleDraft, body = descriptionDraft
        request("PR text") { [self] in
            let result = try await service.updateText(address, title: title, body: body, expectedTitle: original.title, expectedBody: original.body)
            return { [self] in
                guard summary?.id == result.id else { return }
                summary?.title = result.title
                summary?.body = result.body
                summary?.bodyHTML = result.bodyHTML
                editingSummary = nil
                textEditorPresented = false
            }
        }
        prepareRows()
    }

    func openReviewerPicker() {
        guard canEditText else { return }
        selectedReviewers = []
        reviewerQuery = ""
        reviewerPickerPresented = true
        searchReviewers()
    }

    func searchReviewers(after: String? = nil) {
        if after == nil {
            tasks.removeValue(forKey: "Find reviewers")?.cancel()
            loading.remove("Find reviewers")
            reviewerCandidates = []
            reviewersCursor = nil
        }
        let query = reviewerQuery
        request("Find reviewers") { [self] in
            if after == nil { try await Task.sleep(for: .milliseconds(200)) }
            let result = try await service.reviewers(address, query: query, after: after)
            let cursor = try result.pageInfo.nextCursor(after: after)
            return { [self] in
                guard reviewerQuery == query else { return }
                let existing = Set(reviewerCandidates.map(\.id))
                let requested = Set(summary?.reviewRequests?.nodes.compactMap { $0.requestedReviewer?.id } ?? [])
                reviewerCandidates += result.nodes.filter { !existing.contains($0.id) && !requested.contains($0.id) && $0.login != summary?.author?.login }
                reviewersCursor = cursor
            }
        }
    }

    func selectReviewer(_ reviewer: PRReviewer) {
        guard !loading.contains("Request review"), reviewerCandidates.contains(where: { $0.id == reviewer.id }) else { return }
        if selectedReviewers.contains(where: { $0.id == reviewer.id }) { selectedReviewers.removeAll { $0.id == reviewer.id } }
        else { selectedReviewers.append(reviewer) }
    }

    func requestSelectedReviewers() {
        guard canEditText, !selectedReviewers.isEmpty else { return }
        let users = selectedReviewers.map(\.id)
        request("Request review") { [self] in
            let result = try await service.requestReviewers(address, userIDs: users)
            return { [self] in
                guard summary?.id == result.id else { return }
                summary?.reviewRequests = result.reviewRequests
                selectedReviewers = []
                reviewerPickerPresented = false
            }
        }
    }

    func beginMerge(_ action: PRMergeAction) {
        guard !isWriting, !loading.contains("Summary"), let summary, let head = summary.headRefOid else { return }
        let permitted: Bool
        switch action {
        case .merge: permitted = summary.canMerge(method: mergeMethod, bypassRules: bypassMergeRules)
        case .enableAutoMerge: permitted = !bypassMergeRules && summary.canEnableAutoMerge(method: mergeMethod)
        case .disableAutoMerge: permitted = summary.state == "OPEN" && summary.autoMergeRequest != nil && summary.viewerCanDisableAutoMerge == true
        }
        guard permitted else { return }
        pendingMerge = PRMergeRequest(method: action == .disableAutoMerge ? summary.autoMergeRequest?.mergeMethod ?? mergeMethod : mergeMethod, action: action, expectedHeadOID: head, expectedBaseRefName: summary.baseRefName, bypassRules: action == .merge && bypassMergeRules)
        errors["Merge"] = nil
        mergeConfirmationPresented = true
    }

    func confirmMerge() {
        guard mergeConfirmationPresented, !isWriting, let pendingMerge else { return }
        request("Merge") { [self] in
            let result = try await service.merge(address, request: pendingMerge)
            return { [self] in
                summary?.state = result.state
                summary?.autoMergeRequest = result.autoMergeRequest
                self.pendingMerge = nil
                mergeConfirmationPresented = false
                bypassMergeRules = false
            }
        }
        prepareRows()
    }

    func cancelMerge() {
        guard !loading.contains("Merge") else { return }
        mergeConfirmationPresented = false
        pendingMerge = nil
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
                if key == "Merge" { self.loadSummary() }
            } catch {
                guard let self, self.generation == token, !Task.isCancelled else { return }
                self.errors[key] = error.localizedDescription
                self.loading.remove(key)
                self.tasks[key] = nil
                if key.hasPrefix("Reaction:") || ["Description", "PR text", "Summary", "Merge"].contains(key) { self.prepareRows() }
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
