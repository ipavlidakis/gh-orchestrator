import AppKit
import GHOrchestratorCore

// Attributed strings are immutable after preparation and only read by the table on the main actor.
struct PRViewerRow: @unchecked Sendable {
    let id: String
    let title: String
    let subtitle: String
    let body: NSAttributedString
    let url: URL?
    let isSummary: Bool
    let threadID: String?

    static func prepare(address: PullRequestAddress, summary: PRSummary?, activity: [PRActivity], threads: [PRThread]) -> [Self] {
        var rows: [Self] = []
        if let summary {
            rows.append(Self(id: "summary", title: summary.title,
                             subtitle: "\(summary.isDraft ? "Draft" : summary.state.capitalized)  ·  \(address.repository.fullName) #\(address.number)\n\(summary.author?.login ?? "Deleted user")  ·  \(summary.headRefName) → \(summary.baseRefName)",
                             body: PRMarkdown.render(summary.body), url: address.url, isSummary: true, threadID: nil))
        }
        rows.append(Self(id: "activity-heading", title: "Activity", subtitle: "", body: NSAttributedString(), url: nil, isSummary: true, threadID: nil))
        var events: [(Date, Self)] = []
        for item in activity {
            if Task.isCancelled { return [] }
            let name = item.author?.login ?? (item.kind == "PullRequestCommit" ? "Commit" : "Deleted user")
            let event: String
            switch item.kind {
            case "PullRequestReview": event = (item.state ?? "Reviewed").replacingOccurrences(of: "_", with: " ").capitalized
            case "PullRequestCommit": event = "Committed"
            case "MergedEvent": event = "Merged this pull request"
            case "ClosedEvent": event = "Closed this pull request"
            case "ReopenedEvent": event = "Reopened this pull request"
            case "ReadyForReviewEvent": event = "Marked ready for review"
            case "ConvertToDraftEvent": event = "Converted to draft"
            default: event = "Commented"
            }
            events.append((item.createdAt, Self(id: item.id, title: name, subtitle: "\(event)  ·  \(item.createdAt.formatted(date: .abbreviated, time: .shortened))", body: PRMarkdown.render(item.body), url: item.url, isSummary: false, threadID: nil)))
        }
        for thread in threads {
            for (index, comment) in thread.comments.nodes.enumerated() {
                if Task.isCancelled { return [] }
                let context = "\(thread.path)\(thread.line.map { ":\($0)" } ?? "")  ·  \(thread.isResolved ? "Resolved" : "Open thread")\(thread.isOutdated ? "  ·  Outdated" : "")"
                events.append((comment.createdAt, Self(id: comment.id, title: comment.author?.login ?? "Deleted user", subtitle: "\(context)\n\(comment.createdAt.formatted(date: .abbreviated, time: .shortened))", body: PRMarkdown.render(comment.body), url: comment.url, isSummary: false, threadID: index == thread.comments.nodes.count - 1 && thread.comments.pageInfo.hasNextPage ? thread.id : nil)))
            }
        }
        rows += events.sorted { $0.0 == $1.0 ? $0.1.id < $1.1.id : $0.0 < $1.0 }.map(\.1)
        return rows
    }
}

enum PRMarkdown {
    static func render(_ markdown: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var inCode = false
        for raw in markdown.components(separatedBy: "\n") {
            if Task.isCancelled { break }
            if raw.hasPrefix("```") { inCode.toggle(); continue }
            var line = raw
            let heading = inCode ? 0 : line.prefix(while: { $0 == "#" }).count
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = heading > 0 ? 10 : 5
            var font = NSFont.systemFont(ofSize: 14)
            if heading > 0 && heading <= 6 && line.dropFirst(heading).first == " " {
                line = String(line.dropFirst(heading + 1))
                font = .systemFont(ofSize: heading == 1 ? 22 : 18, weight: .semibold)
            } else if inCode || line.hasPrefix("|") {
                font = .monospacedSystemFont(ofSize: 12.5, weight: .regular)
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                line = "• " + line.dropFirst(2)
                paragraph.headIndent = 16
            } else if line.hasPrefix("> ") {
                line = "│ " + line.dropFirst(2)
                paragraph.headIndent = 16
            }
            let parsed = inCode ? nil : try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
            let text = parsed.map(NSAttributedString.init) ?? NSAttributedString(string: line)
            let styled = NSMutableAttributedString(attributedString: text)
            let range = NSRange(location: 0, length: styled.length)
            styled.addAttributes([.font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph], range: range)
            if inCode { styled.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: range) }
            if let parsed {
                var offset = 0
                for run in parsed.runs {
                    let content = String(parsed.characters[run.range])
                    let r = NSRange(location: offset, length: content.utf16.count)
                    offset += r.length
                    if run.inlinePresentationIntent?.contains(.code) == true {
                        styled.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), range: r)
                    } else if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                        styled.addAttribute(.font, value: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold), range: r)
                    } else if run.inlinePresentationIntent?.contains(.emphasized) == true {
                        let descriptor = font.fontDescriptor.withSymbolicTraits(.italic)
                        styled.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: r)
                    }
                }
            }
            result.append(styled)
            result.append(NSAttributedString(string: "\n", attributes: [.font: font, .paragraphStyle: paragraph]))
        }
        return NSAttributedString(attributedString: result)
    }
}
