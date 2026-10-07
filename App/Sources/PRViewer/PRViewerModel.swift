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
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var preparation: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var preparationID = UUID()

    init(address: PullRequestAddress, service: any PullRequestDetailLoading) {
        self.address = address
        self.service = service
    }

    func refresh() {
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
                threads[index].comments = PRConnection(nodes: threads[index].comments.nodes + page.nodes, pageInfo: page.pageInfo)
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
            }
        }
    }

    private func prepareRows() {
        preparation?.cancel()
        let token = UUID()
        preparationID = token
        let summary = summary, activity = activity, threads = threads, address = address
        let worker = Task.detached(priority: .userInitiated) {
            PRViewerRow.prepare(address: address, summary: summary, activity: activity, threads: threads)
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
