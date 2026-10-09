import Foundation
import GHOrchestratorCore

struct PRViewerRow: Encodable, Sendable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let time: String
    let body: String
    let bodyHTML: String?
    let url: URL?
    let author: PRActor?
    let isSummary: Bool
    let header: Header?
    let threadID: String?
    let hasMoreReplies: Bool
    let canReply: Bool
    let canResolve: Bool
    let isResolved: Bool
    var parentID: String? = nil
    var badgeResolved = false
    var childCount = 0
    var filePath: String? = nil
    var isThreadEnd = false
    var canReact = false
    var reactionGroups: [PRReactionGroup] = []
    var isReacting = false
    var defaultExpanded = false
    var descriptionTasks: [PRDescriptionTask] = []
    var canEditDescription = false
    var isUpdatingDescription = false

    struct Header: Encodable, Sendable {
        let head: String
        let base: String
    }

    static func prepare(address: PullRequestAddress, summary: PRSummary?, activity: [PRActivity], threads: [PRThread], loading: Set<String> = []) -> [Self] {
        var rows: [Self] = []
        if let summary {
            let relative = RelativeDateTimeFormatter()
            relative.unitsStyle = .short
            var row = Self(id: "summary", kind: "summary", title: summary.title, subtitle: "", time: relative.localizedString(for: summary.createdAt, relativeTo: Date()), body: summary.body, bodyHTML: summary.bodyHTML, url: address.url, author: summary.author, isSummary: true,
                             header: Header(head: summary.headRefName, base: summary.baseRefName),
                             threadID: nil, hasMoreReplies: false, canReply: false, canResolve: false, isResolved: false)
            row.descriptionTasks = PRDescriptionTask.items(in: summary.body)
            row.canEditDescription = summary.viewerCanUpdate == true && summary.id != nil && !loading.contains("Summary")
        row.isUpdatingDescription = loading.contains("Description") || loading.contains("PR text") || loading.contains("Merge")
            rows.append(row)
        }
        rows.append(Self(id: "activity-heading", kind: "heading", title: "Activity", subtitle: "", time: "", body: "", bodyHTML: nil, url: nil, author: nil, isSummary: true, header: nil, threadID: nil, hasMoreReplies: false, canReply: false, canResolve: false, isResolved: false))
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .short
        let now = Date()
        var events: [(Date, [Self])] = []
        let reviews = Set(activity.filter { $0.kind == "PullRequestReview" }.map(\.id))
        let groups = Dictionary(grouping: threads.filter { $0.comments.nodes.first?.pullRequestReview != nil }) {
            $0.comments.nodes.first!.pullRequestReview!.id
        }
        let reviewCommentCounts = Dictionary(grouping: threads.flatMap(\.comments.nodes).compactMap { $0.pullRequestReview?.id }, by: { $0 }).mapValues(\.count)
        func threadRows(_ thread: PRThread, reviewID: String?) -> [Self] {
            guard let root = thread.comments.nodes.first else { return [] }
            let context = "\(thread.path)\(thread.line.map { ":\($0)" } ?? "") · \(thread.isResolved ? "Resolved" : "Open thread")\(thread.isOutdated ? " · Outdated" : "")"
            return thread.comments.nodes.enumerated().map { index, comment in
                let first = index == 0
                let last = index == thread.comments.nodes.count - 1
                var row = Self(id: comment.id, kind: first ? "thread" : "reply", title: comment.author?.login ?? "Deleted user", subtitle: context, time: relative.localizedString(for: comment.createdAt, relativeTo: now), body: comment.body, bodyHTML: comment.bodyHTML, url: comment.url, author: comment.author, isSummary: false, header: nil, threadID: thread.id, hasMoreReplies: last && thread.comments.pageInfo.hasNextPage, canReply: last && thread.viewerCanReply == true, canResolve: last && (thread.isResolved ? thread.viewerCanUnresolve : thread.viewerCanResolve) == true, isResolved: thread.isResolved)
                row.parentID = index == 0 ? reviewID : root.id
                row.badgeResolved = index == 0 && (thread.isResolved || thread.isOutdated)
                row.defaultExpanded = !thread.isResolved && !thread.isOutdated
                row.childCount = index == 0 ? thread.comments.nodes.count - 1 : 0
                row.filePath = "\(thread.path)\(thread.line.map { ":\($0)" } ?? "")"
                row.isThreadEnd = last
                row.canReact = comment.viewerCanReact == true
                row.reactionGroups = comment.reactionGroups ?? []
                row.isReacting = loading.contains("Reaction:\(comment.id)")
                return row
            }
        }
        for item in activity {
            if Task.isCancelled { return [] }
            let event: String
            switch item.kind {
            case "PullRequestReview": event = item.state == "APPROVED" ? "approved these changes" : item.state == "CHANGES_REQUESTED" ? "requested changes" : "reviewed"
            case "PullRequestCommit": event = "Committed"
            case "MergedEvent": event = "merged this pull request"
            case "ClosedEvent": event = "closed this pull request"
            case "ReopenedEvent": event = "reopened this pull request"
            case "ReadyForReviewEvent": event = "marked ready for review"
            case "ConvertToDraftEvent": event = "converted to draft"
            default: event = "Commented"
            }
            let kind = item.kind == "PullRequestCommit" ? "commit" : item.kind == "PullRequestReview" ? "review" : item.kind == "IssueComment" ? "comment" : "event"
            var row = Self(id: item.id, kind: kind, title: item.author?.login ?? (kind == "commit" ? "Commit" : "Deleted user"), subtitle: event, time: relative.localizedString(for: item.createdAt, relativeTo: now), body: item.body, bodyHTML: item.bodyHTML, url: item.url, author: item.author, isSummary: false, header: nil, threadID: nil, hasMoreReplies: false, canReply: false, canResolve: false, isResolved: false)
            row.canReact = item.viewerCanReact == true
            row.reactionGroups = item.reactionGroups ?? []
            row.isReacting = loading.contains("Reaction:\(item.id)")
            let children = (groups[item.id] ?? []).sorted {
                let left = $0.comments.nodes.first!.createdAt, right = $1.comments.nodes.first!.createdAt
                return left == right ? $0.id < $1.id : left < right
            }
            if kind == "review" {
                row.childCount = children.count
                row.badgeResolved = !children.isEmpty && item.reviewCommentCount == reviewCommentCounts[item.id] && children.allSatisfy { $0.isResolved || $0.isOutdated }
            }
            row.defaultExpanded = kind == "comment" || (kind == "review" && !row.badgeResolved)
            events.append((item.createdAt, [row] + children.flatMap { threadRows($0, reviewID: item.id) }))
        }
        for thread in threads {
            if Task.isCancelled { return [] }
            guard let root = thread.comments.nodes.first, !reviews.contains(root.pullRequestReview?.id ?? "") else { continue }
            events.append((root.createdAt, threadRows(thread, reviewID: nil)))
        }
        events.sort { $0.0 == $1.0 ? $0.1[0].id < $1.1[0].id : $0.0 < $1.0 }
        rows += events.flatMap(\.1)
        return rows
    }
}
