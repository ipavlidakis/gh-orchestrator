import Foundation
import GHOrchestratorCore
import Observation

@MainActor
@Observable
final class PRDiffModel {
    let address: PullRequestAddress
    private let service: any PullRequestDiffLoading
    private(set) var files: [PRDiffFile] = [] { didSet { rebuildTree() } }
    private(set) var filteredFiles: [PRDiffFile] = []
    private(set) var fileTree: [PRDiffTreeNode] = []
    var collapsedDirectories: Set<String> = []
    private(set) var patches: [PRDiffPatch] = []
    private(set) var viewed: Set<String> = []
    private(set) var collapsed: Set<String> = []
    private(set) var pending: Set<String> = []
    private(set) var errors: [String: String] = [:]
    private(set) var renderErrors: [String: String] = [:]
    private(set) var catalogLoading = false
    private(set) var patchesLoading = false
    var loading: Bool { catalogLoading || patchesLoading }
    private(set) var started = false
    private(set) var total = 0
    private(set) var nextPatchPage: Int? = 1
    private(set) var dataRevision = 0
    private(set) var loadRevision = 0
    private(set) var stateRevision = 0
    private(set) var navigationRevision = 0
    private(set) var visiblePath: String?
    private(set) var focusedThreadID: String?
    var query = "" { didSet { rebuildTree() } }
    var extensions: Set<String> = [] { didSet { rebuildTree() } }
    var style = "unified"
    var wraps = false
    private(set) var automaticallySelectedPath: String?
    var selectedPath: String? { didSet { if selectedPath != oldValue { automaticallySelectedPath = nil; focusedThreadID = nil } } }
    private(set) var selection: PRDiffLineSelection?
    var composerPresented = false
    private var commentDrafts: [PRDiffLineSelection: String] = [:]
    var commentDraft: String {
        get { commentSelection.flatMap { commentDrafts[$0] } ?? "" }
        set { if let commentSelection { commentDrafts[commentSelection] = newValue } }
    }
    private(set) var commentSelection: PRDiffLineSelection?
    private(set) var postingComment = false
    private(set) var postedComment: PRComment?
    func commentDeleted(_ id: String) { if postedComment?.id == id { postedComment = nil } }
    private var patchBytes = 0
    private var commentRevision: PRDiffRevision?
    private var snapshotRevision: PRDiffRevision?
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var generation = UUID()
    var isWriting: Bool { !pending.isEmpty || postingComment }
    var selectedFile: PRDiffFile? { files.first { $0.path == selectedPath } }
    var selectedPatch: PRDiffPatch? { patches.first { $0.filename == selectedPath } }
    var availableExtensions: [String] { Set(files.map(\.fileExtension)).sorted() }
    private func rebuildTree() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingFiles = files.filter {
            (extensions.isEmpty || extensions.contains($0.fileExtension)) &&
            (name.isEmpty || $0.path.localizedStandardContains(name))
        }
        fileTree = PRDiffTreeNode.nodes(paths: matchingFiles.map(\.path))
        let byPath = Dictionary(uniqueKeysWithValues: matchingFiles.map { ($0.path, $0) })
        filteredFiles = fileTree.flatMap(\.filePaths).compactMap { byPath[$0] }
    }
    var filteredPaths: [String] { filteredFiles.map(\.path) }

    init(address: PullRequestAddress, service: any PullRequestDiffLoading) { self.address = address; self.service = service }

    func cancel() {
        generation = UUID()
        tasks.values.forEach { $0.cancel() }; tasks = [:]
        catalogLoading = false; patchesLoading = false; pending = []; postingComment = false; stateRevision += 1
    }

    func refresh() {
        guard !isWriting else { return }
        cancel(); files = []; patches = []; viewed = []; collapsed = []; errors = [:]; renderErrors = [:]
        snapshotRevision = nil; total = 0; nextPatchPage = 1; patchBytes = 0; started = false; dataRevision += 1; loadRevision += 1
        selection = nil; composerPresented = false; commentSelection = nil; commentRevision = nil; visiblePath = nil; focusedThreadID = nil
        load()
    }

    func load() {
        guard !started else { return }
        started = true; catalogLoading = true
        let token = generation
        tasks["Files"] = Task { [weak self] in
            guard let self else { return }
            do {
                var cursor: String?, seenCursors: Set<String> = [], seenPaths: Set<String> = []
                repeat {
                    let page = try await service.diffSnapshot(address, after: cursor)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    if let snapshotRevision, snapshotRevision != page.revision { throw changedPR() }
                    snapshotRevision = page.revision; total = page.changedFiles
                    let added = Array(page.files.nodes.filter { seenPaths.insert($0.path).inserted }.prefix(3_000 - files.count))
                    files += added
                    let alreadyViewed = added.filter(\.isViewed).map(\.path)
                    viewed.formUnion(alreadyViewed); collapsed.formUnion(alreadyViewed)
                    if focusedThreadID != nil, let selectedPath { collapsed.remove(selectedPath) }
                    if selectedPath == nil {
                        selectedPath = filteredFiles.first?.path
                        automaticallySelectedPath = selectedPath
                    }
                    dataRevision += 1; stateRevision += 1
                    loadMorePatches()
                    cursor = try page.files.pageInfo.nextCursor(after: cursor)
                    if let cursor, !seenCursors.insert(cursor).inserted { throw changedPR() }
                } while cursor != nil && files.count < 3_000
                guard generation == token else { return }
                filterSelection()
                if cursor != nil || files.count < total { errors["Limit"] = "Only \(files.count) of \(total) files are available locally. Open GitHub for the complete change." }
                catalogLoading = false; tasks["Files"] = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                errors["Files"] = error.localizedDescription; catalogLoading = false; tasks["Files"] = nil
            }
        }
    }

    func loadMorePatches() {
        guard !patchesLoading, nextPatchPage != nil, let expected = snapshotRevision else { return }
        patchesLoading = true; errors["Patches"] = nil
        let token = generation
        tasks["Patches"] = Task { [weak self] in
            guard let self else { return }
            do {
                while let page = nextPatchPage {
                    let result = try await service.diffPatches(address, page: page)
                    try Task.checkCancellation()
                    guard generation == token else { return }
                    var known = Set(patches.map(\.filename))
                    let added = result.filter { known.insert($0.filename).inserted }
                    let bytes = added.reduce(0) { $0 + ($1.patch?.utf8.count ?? 0) }
                    guard patchBytes + bytes <= 16_777_216 else {
                        errors["Limit"] = "The loaded diffs reached the local memory limit. Open GitHub for the remaining patches."
                        nextPatchPage = nil; break
                    }
                    patches += added; patchBytes += bytes
                    nextPatchPage = result.count == PRDiffPatch.pageSize && page * PRDiffPatch.pageSize < min(total, 3_000) ? page + 1 : nil
                    dataRevision += 1
                }
                let current = try await service.diffRevision(address)
                try Task.checkCancellation()
                guard generation == token else { return }
                guard current == expected else {
                    patches = []; patchBytes = 0; selection = nil; dataRevision += 1
                    throw changedPR()
                }
                patchesLoading = false; tasks["Patches"] = nil
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                errors["Patches"] = error.localizedDescription; patchesLoading = false; tasks["Patches"] = nil
            }
        }
    }

    func toggleCollapsed(_ path: String) {
        guard files.contains(where: { $0.path == path }), !pending.contains(path) else { return }
        if !collapsed.insert(path).inserted { collapsed.remove(path) }
        if path == selectedPath { selection = nil }
        stateRevision += 1
    }

    func rendererFailed(_ message: String, path: String? = nil) {
        if let path { renderErrors[path] = message }
        else { errors["Renderer"] = message }
    }

    func rendererRecovered() { errors["Renderer"] = nil }

    func selectFile() {
        focusedThreadID = nil
        automaticallySelectedPath = nil
        navigationRevision += 1; visiblePath = selectedPath
        if selection?.path != selectedPath { selection = nil }
        stateRevision += 1
        if selectedPatch == nil { loadMorePatches() }
    }

    func openThread(_ thread: PRThread) {
        query = ""; extensions = []
        selectedPath = thread.path
        selectFile()
        focusedThreadID = thread.id
        collapsed.remove(thread.path)
        load()
    }

    func syncVisibleFile(_ path: String) {
        guard visiblePath != path, filteredFiles.contains(where: { $0.path == path }) else { return }
        visiblePath = path
        let ancestors = collapsedDirectories.filter { path.hasPrefix($0 + "/") }
        if !ancestors.isEmpty { collapsedDirectories.subtract(ancestors) }
    }

    func filterSelection() {
        if catalogLoading && focusedThreadID != nil { return }
        if !filteredPaths.contains(selectedPath ?? "") { selectedPath = filteredPaths.first }
    }

    func clearLineSelection() { selection = nil }

    func selectLines(path: String, start: Int, end: Int, startSide: PRDiffLineSelection.Side, endSide: PRDiffLineSelection.Side) {
        guard path == selectedPath, !collapsed.contains(path), selectedPatch?.patch != nil else { return }
        selection = PRDiffLineSelection(path: path, start: start, end: end, startSide: startSide, endSide: endSide)
    }

    func composeComment() {
        guard let selection, !postingComment else { return }
        commentSelection = selection; commentRevision = snapshotRevision; composerPresented = true
    }

    func postComment() {
        guard let selection = commentSelection, let expected = commentRevision, !postingComment, !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let body = commentDraft, token = generation
        postingComment = true; errors["Comment"] = nil
        tasks["Comment"] = Task { [weak self] in
            guard let self else { return }
            do {
                let comment = try await service.addLineComment(address, selection: selection, body: body, expected: expected)
                guard generation == token, !Task.isCancelled else { return }
                postedComment = comment; commentDraft = ""; composerPresented = false
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                errors["Comment"] = error.localizedDescription
            }
            postingComment = false; tasks["Comment"] = nil
        }
    }

    func setViewed(_ path: String, _ value: Bool) {
        guard let expected = snapshotRevision, files.contains(where: { $0.path == path }), !pending.contains(path), viewed.contains(path) != value else { return }
        pending.insert(path); errors[path] = nil; stateRevision += 1
        let token = generation
        tasks[path] = Task { [weak self] in
            guard let self else { return }
            do {
                try await service.setFileViewed(address, path: path, viewed: value, expected: expected)
                guard generation == token, !Task.isCancelled else { return }
                if value { viewed.insert(path); collapsed.insert(path); if path == selectedPath { selection = nil } }
                else { viewed.remove(path); collapsed.remove(path) }
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                errors[path] = error.localizedDescription
            }
            pending.remove(path); tasks[path] = nil; stateRevision += 1
        }
    }

    private func changedPR() -> GitHubAPIClientError { .invalidResponse(message: "This PR changed on GitHub. Refresh files to load the current diff.") }
}
