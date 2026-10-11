import GHOrchestratorCore
import SwiftUI

struct PRDiffThreadView: View {
    let thread: PRThread
    let fileLevel: Bool
    @Bindable var model: PRViewerModel
    let openBrowser: (URL) -> Void
    let heightChanged: (CGFloat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(thread.isOutdated ? "Outdated conversation" : thread.isResolved ? "Resolved conversation" : "Conversation", systemImage: thread.isResolved ? "checkmark.bubble" : "bubble.left")
                Spacer()
                if let line = thread.line ?? thread.originalLine {
                    if let start = thread.startLine, let startSide = thread.startDiffSide, startSide != thread.diffSide {
                        Text("\(startSide == "LEFT" ? "Old" : "New") line \(start) – \(thread.diffSide == "LEFT" ? "Old" : "New") line \(line)")
                    } else {
                        Text("\(thread.diffSide == "LEFT" ? "Old" : "New") \(thread.startLine.flatMap { $0 != line ? "lines \($0)–\(line)" : nil } ?? "line \(line)")")
                    }
                }
            }.font(.caption).foregroundStyle(.secondary).padding(12)
            if fileLevel && !thread.isOutdated && thread.line != nil {
                Text("This line is outside the available diff.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
            }
            ForEach(thread.comments.nodes) { comment in
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        AsyncImage(url: comment.author?.avatarUrl) { image in image.resizable().scaledToFill() } placeholder: { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary) }
                            .frame(width: 24, height: 24).clipShape(Circle()).accessibilityHidden(true)
                        Text(comment.author?.login ?? "Deleted user").fontWeight(.semibold)
                        Text(comment.createdAt, style: .relative).foregroundStyle(.secondary)
                        Spacer()
                        Button { openBrowser(comment.url) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.plain).accessibilityLabel("Open comment on GitHub")
                        if comment.canDelete {
                            Menu {
                                Button("Delete comment", role: .destructive) { model.requestCommentDeletion(comment.id) }
                            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .disabled(model.isWriting).accessibilityLabel("Actions for comment by \(comment.author?.login ?? "you")")
                        }
                    }.font(.caption)
                    Text((try? AttributedString(markdown: comment.body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(comment.body))
                        .font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    if model.loading.contains("Delete:\(comment.id)") { ProgressView("Deleting comment…").controlSize(.small) }
                    if let error = model.errors["Delete:\(comment.id)"] {
                        Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(12)
            }
            Divider()
            HStack {
                if thread.comments.pageInfo.hasNextPage {
                    Button("Load more replies") { model.loadReplies(thread.id) }.disabled(model.loading.contains(thread.id))
                }
                if thread.viewerCanReply == true {
                    Button("Reply…") { model.compose(threadID: thread.id) }.disabled(model.loading.contains("Comment"))
                }
                Spacer()
                if (thread.isResolved ? thread.viewerCanUnresolve : thread.viewerCanResolve) == true {
                    Button(thread.isResolved ? "Unresolve conversation" : "Resolve conversation") { model.toggleResolved(thread.id) }
                        .disabled(model.loading.contains("Resolve:\(thread.id)"))
                }
                if model.loading.contains(thread.id) || model.loading.contains("Resolve:\(thread.id)") { ProgressView().controlSize(.small) }
            }.buttonStyle(.bordered).controlSize(.small).padding(12)
            if let error = model.errors[thread.id] ?? model.errors["Resolve:\(thread.id)"] {
                Text(error).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).padding(12)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(model.diffs?.focusedThreadID == thread.id ? Color.accentColor : Color.primary.opacity(0.15)))
        .padding(.vertical, 8)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heightChanged($0) }
        .accessibilityElement(children: .contain).accessibilityLabel("Inline review thread \(thread.id)")
    }
}
