import CryptoKit
import GHOrchestratorCore
import SwiftUI

struct PRDiffFileHeader: View {
    let file: PRDiffFile
    @Bindable var model: PRDiffModel
    let openBrowser: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showsError = false

    // Detached hosting views need fresh glass surfaces after an appearance change.
    var body: some View { content.id(colorScheme) }

    @ViewBuilder private var content: some View {
        if #available(macOS 26, *), !reduceTransparency {
            card.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8))
        } else { card.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) }
    }

    private var emptyDiffMessage: String? {
        guard !model.collapsed.contains(file.path), model.renderErrors[file.path] == nil,
              let patch = model.patches.first(where: { $0.filename == file.path }), patch.patch?.isEmpty != false else { return nil }
        if file.additions == 0 && file.deletions == 0 {
            switch file.changeType {
            case "ADDED": return "Empty file."
            case "DELETED": return "Empty file deleted."
            case "RENAMED": return "File renamed without content changes."
            default: return "No text changes."
            }
        }
        return patch.unavailable ?? "GitHub did not supply a text patch for this file."
    }

    private var card: some View {
        VStack(spacing: 0) {
            header
            if let message = emptyDiffMessage {
                Divider()
                HStack {
                    Text(message).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        .lineLimit(1).help(message).textSelection(.enabled)
                    Spacer(minLength: 8)
                    if file.additions != 0 || file.deletions != 0 {
                        Button("Open on GitHub", systemImage: "arrow.up.right.square", action: openFile)
                            .buttonStyle(.link).font(.caption)
                    }
                }.padding(.horizontal, 12).frame(height: 35)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8).strokeBorder((model.visiblePath ?? model.selectedPath) == file.path ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.12))
                    .allowsHitTesting(false)
            }
    }

    private var header: some View {
        ZStack {
            Button { model.toggleCollapsed(file.path) } label: {
                Rectangle().fill(.clear).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.pending.contains(file.path))
                .accessibilityLabel("\(model.collapsed.contains(file.path) ? "Expand" : "Collapse") diff \(file.path)")
            headerContent
        }.frame(height: 44)
    }

    private var headerContent: some View {
        HStack(spacing: 8) {
            Image(systemName: model.collapsed.contains(file.path) ? "chevron.right" : "chevron.down").allowsHitTesting(false)
            Text(file.path).font(.caption.monospaced())
                .lineLimit(1).truncationMode(.middle).help(file.path).allowsHitTesting(false)
            Spacer(minLength: 4)
            if !model.collapsed.contains(file.path), model.patches.first(where: { $0.filename == file.path })?.patch == nil || model.renderErrors[file.path] != nil {
                if model.patchesLoading && !model.patches.contains(where: { $0.filename == file.path }) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Loading diff…").foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine).accessibilityLabel("Loading diff for \(file.path)")
                } else if model.nextPatchPage != nil && !model.patches.contains(where: { $0.filename == file.path }) {
                    Button("Retry loading") { model.loadMorePatches() }
                } else if emptyDiffMessage == nil {
                    Button("Open on GitHub", systemImage: "arrow.up.right.square", action: openFile)
                        .help(model.renderErrors[file.path] ?? model.patches.first(where: { $0.filename == file.path })?.unavailable ?? model.errors["Limit"] ?? "Open file on GitHub")
                }
            }
            if let error = model.errors[file.path] ?? model.renderErrors[file.path] {
                Button { showsError = true } label: { Image(systemName: "exclamationmark.triangle").foregroundStyle(.yellow) }
                    .buttonStyle(.plain).help(error).accessibilityLabel("Error details for \(file.path)")
                    .popover(isPresented: $showsError) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(file.path).font(.caption.monospaced())
                            Text(error).textSelection(.enabled)
                        }.padding(16).frame(maxWidth: 360)
                    }
            }
            Text("+\(file.additions)").foregroundStyle(StatusTint.success.color).fixedSize().allowsHitTesting(false)
            Text("−\(file.deletions)").foregroundStyle(StatusTint.danger.color).fixedSize().allowsHitTesting(false)
            if #available(macOS 26, *), !reduceTransparency {
                GlassEffectContainer(spacing: 8) { actions.buttonStyle(.glass) }
            } else { actions.buttonStyle(.bordered) }
        }.font(.caption).padding(.horizontal, 12)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { model.composeComment() } label: { Image(systemName: "bubble.left").frame(width: 28, height: 28) }
                .accessibilityLabel("Comment on selection").help("Comment on the selected line or range")
                .disabled(model.selection?.path != file.path || model.postingComment || model.collapsed.contains(file.path))
            Button { model.setViewed(file.path, !model.viewed.contains(file.path)) } label: {
                Image(systemName: model.viewed.contains(file.path) ? "eye.fill" : "eye")
                    .foregroundStyle(model.viewed.contains(file.path) ? StatusTint.success.color : .primary)
                    .frame(width: 28, height: 28)
                    .overlay { if model.pending.contains(file.path) { ProgressView().controlSize(.small) } }
                    .opacity(model.pending.contains(file.path) ? 0.4 : 1)
            }.disabled(model.pending.contains(file.path))
                .accessibilityLabel("Viewed \(file.path)")
                .accessibilityValue(model.pending.contains(file.path) ? "Saving" : model.viewed.contains(file.path) ? "Viewed" : "Unviewed")
                .help(model.viewed.contains(file.path) ? "Mark as unviewed" : "Mark as viewed")
        }.buttonBorderShape(.circle).controlSize(.small)
    }

    private func openFile() {
        let hash = SHA256.hash(data: Data(file.path.utf8)).map { String(format: "%02x", $0) }.joined()
        var url = URLComponents(url: model.address.url.appendingPathComponent("files"), resolvingAgainstBaseURL: false)
        url?.fragment = "diff-\(hash)"
        if let url = url?.url { openBrowser(url) }
    }
}

struct PRDiffLineCommentButton: View {
    let selection: PRDiffLineSelection
    @Bindable var model: PRDiffModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View { content.id(colorScheme) }

    @ViewBuilder private var content: some View {
        if #available(macOS 26, *), !reduceTransparency { button.buttonStyle(.glassProminent) }
        else { button.buttonStyle(.bordered) }
    }

    private var button: some View {
        Button {
            model.selectedPath = selection.path
            let keepsRange = model.selection.map { range in
                guard range.path == selection.path else { return false }
                if range.startSide == range.endSide {
                    return range.startSide == selection.startSide && range.start <= selection.start && selection.start <= range.end
                }
                return selection.startSide == range.startSide ? selection.start >= range.start : selection.start <= range.end
            } ?? false
            if !keepsRange {
                model.selectLines(path: selection.path, start: selection.start, end: selection.end, startSide: selection.startSide, endSide: selection.endSide)
            }
            model.composeComment()
        } label: { Image(systemName: "plus").frame(width: 20, height: 20) }
            .buttonBorderShape(.circle).controlSize(.small).disabled(model.postingComment)
            .accessibilityLabel("Add comment on \(selection.startSide == .left ? "old" : "new") line \(selection.start)")
            .help("Comment on this line or the selected range")
    }
}
