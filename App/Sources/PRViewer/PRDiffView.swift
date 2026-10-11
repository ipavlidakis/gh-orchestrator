import AppKit
import GHOrchestratorCore
import SwiftUI

struct PRDiffView: View {
    @Bindable var model: PRDiffModel
    @Binding var columnVisibility: NavigationSplitViewVisibility
    let openBrowser: (URL) -> Void
    var reviewModel: PRViewerModel? = nil
    @FocusState private var editorFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if model.loading && (model.files.isEmpty || (model.focusedThreadID != nil && (model.selectedFile == nil || model.selectedPatch == nil))) {
                ProgressView("Loading files…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    PRDiffSidebar(model: model, reviewModel: reviewModel)
                        .navigationSplitViewColumnWidth(min: 160, ideal: 220, max: 240)
                } detail: {
                    ZStack {
                        PRDiffWebView(model: model, revision: "\(model.dataRevision):\(model.stateRevision):\(model.selectedPath ?? ""): \(model.query):\(model.extensions.sorted()):\(model.style):\(model.wraps):\(reviewModel?.threadRevision ?? 0)", openBrowser: openBrowser, reviewModel: reviewModel)
                        if model.filteredFiles.isEmpty {
                            ContentUnavailableView("No matching files", systemImage: "doc.text.magnifyingglass", description: Text("Change the filename or extension filters."))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.navigationSplitViewStyle(.balanced)
            }
        }
        .onChange(of: model.selectedPath) { _, path in if path != model.automaticallySelectedPath && model.focusedThreadID == nil { model.selectFile() } }
        .onChange(of: model.query) { _, _ in model.filterSelection() }
        .onChange(of: model.extensions) { _, _ in model.filterSelection() }
        .onChange(of: model.postedComment?.id) { _, _ in reviewModel?.reloadThreads() }
        .sheet(isPresented: $model.composerPresented) { composer }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            composerControls
            if let selection = model.commentSelection {
                Text(selection.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("\(selection.startSide == .left ? "Old" : "New") \(selection.isRange ? "lines \(selection.start)–\(selection.end)" : "line \(selection.start)")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextEditor(text: $model.commentDraft).font(.system(size: 14))
                .scrollContentBackground(.hidden).padding(8).frame(height: 180)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .disabled(model.postingComment).focused($editorFocused).accessibilityLabel("Line comment body")
            if let error = model.errors["Comment"] {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).textSelection(.enabled)
            }
            Text("Posts immediately. GitHub Markdown supported.").font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 560).interactiveDismissDisabled(model.postingComment)
            .defaultFocus($editorFocused, true)
    }

    @ViewBuilder private var composerControls: some View {
        if #available(macOS 26, *), !reduceTransparency {
            GlassEffectContainer { composerActions.buttonStyle(.glass) }
        } else { composerActions.buttonStyle(.bordered) }
    }

    private var composerActions: some View {
        HStack {
            Button("Cancel") { model.composerPresented = false }.disabled(model.postingComment).keyboardShortcut(.cancelAction)
            Text("Comment on diff").font(.headline).frame(maxWidth: .infinity)
            if model.postingComment { ProgressView().controlSize(.small) }
            Button("Post comment") { model.postComment() }
                .disabled(model.postingComment || model.commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
        }
    }

}

private struct PRDiffSidebar: View {
    @Bindable var model: PRDiffModel
    let reviewModel: PRViewerModel?

    var body: some View {
        VStack(spacing: 0) {
            fileList
            HStack(spacing: 8) {
                PRDiffFilters(model: model)
                PRDiffSearchField(query: $model.query).frame(height: 28)
            }.padding(10)
        }
    }

    private var fileList: some View {
        ScrollViewReader { proxy in
            List(selection: Binding(get: { model.visiblePath ?? model.selectedPath }, set: { path in
                if model.selectedPath == path { model.selectFile() }
                else { model.selectedPath = path }
            })) {
                Section {
                    if let reviewModel, let error = reviewModel.errors["Threads"] {
                        VStack(alignment: .leading) {
                            Label("Review comments: \(error)", systemImage: "exclamationmark.triangle").font(.caption).textSelection(.enabled)
                            Button("Retry comments") { reviewModel.loadThreads() }.disabled(reviewModel.loading.contains("Threads"))
                        }
                    }
                    ForEach(model.errors.keys.sorted().filter { key in
                        (key != "Comment" || !model.composerPresented) && !model.files.contains { $0.path == key }
                    }, id: \.self) { key in
                        Label("\(key): \(model.errors[key] ?? "")", systemImage: "exclamationmark.triangle")
                            .font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            .help(model.errors[key] ?? "")
                    }
                    PRDiffTreeRows(nodes: model.fileTree, model: model)
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(model.filteredFiles.count) of \(model.total) files · \(model.viewed.count) viewed")
                        if reviewModel?.loading.contains("Threads") == true {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Loading review comments…") }
                        }
                        if model.loading {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(model.catalogLoading ? "\(model.files.count) files loaded" : "\(model.patches.count) of \(min(model.total, 3_000)) diffs loaded")
                            }
                        }
                    }.font(.caption).foregroundStyle(.secondary).textCase(nil)
                }
            }.listStyle(.sidebar)
                // SwiftUI can retain removed disclosure rows and their heights across filtering.
                .id([model.query] + model.extensions.sorted())
                .toolbar(removing: .sidebarToggle)
                .task(id: model.visiblePath) {
                    await Task.yield()
                    guard !Task.isCancelled, let path = model.visiblePath else { return }
                    proxy.scrollTo(path)
                }
        }
    }
}

private struct PRDiffSearchField: NSViewRepresentable {
    @Binding var query: String

    func makeCoordinator() -> Coordinator { Coordinator(query: $query) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Filter files…"
        field.setAccessibilityLabel("Filter files by name or path")
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.searchChanged(_:))
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.query = $query
        if field.stringValue != query { field.stringValue = query }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var query: Binding<String>
        init(query: Binding<String>) { self.query = query }
        @objc func searchChanged(_ field: NSSearchField) {
            if query.wrappedValue != field.stringValue { query.wrappedValue = field.stringValue }
        }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { searchChanged(field) }
        }
    }
}

private struct PRDiffTreeRows: View {
    let nodes: [PRDiffTreeNode]
    @Bindable var model: PRDiffModel

    var body: some View {
        ForEach(nodes) { node in
            if let children = node.children {
                DisclosureGroup(isExpanded: Binding(
                    get: { !model.collapsedDirectories.contains(node.id) },
                    set: { if $0 { model.collapsedDirectories.remove(node.id) } else { model.collapsedDirectories.insert(node.id) } }
                )) {
                    PRDiffTreeRows(nodes: children, model: model)
                } label: {
                    Label(node.name, systemImage: "folder").font(.caption).lineLimit(1).help(node.id).selectionDisabled()
                }.accessibilityIdentifier("directory:\(node.id)")
            } else {
                HStack(spacing: 8) {
                    Label(node.name, systemImage: "doc.text").font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                    if model.viewed.contains(node.id) {
                        Image(systemName: "eye.fill").accessibilityLabel("Viewed")
                    }
                }.font(.caption).tag(node.id).selectionDisabled(false).help(node.id)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(node.name)
                    .accessibilityValue(model.viewed.contains(node.id) ? "Viewed" : "Unviewed")
                    .accessibilityIdentifier("file:\(node.id)")
            }
        }
    }
}

private struct PRDiffFilters: View {
    @Bindable var model: PRDiffModel
    var body: some View {
        Menu {
            Section("File extensions") {
                Button("All extensions") { model.extensions = [] }
                ForEach(model.availableExtensions, id: \.self) { ext in
                    Toggle(ext.isEmpty ? "No extension" : ".\(ext)", isOn: Binding(
                        get: { model.extensions.contains(ext) },
                        set: { if $0 { model.extensions.insert(ext) } else { model.extensions.remove(ext) } }
                    ))
                }
            }
        } label: {
            Image(systemName: model.extensions.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                .frame(width: 28, height: 28)
        }.menuStyle(.borderlessButton).fixedSize().focusEffectDisabled()
            .accessibilityLabel("File filters").help("Filter file extensions")
            .accessibilityValue(model.extensions.isEmpty ? "All extensions" : "\(model.extensions.count) extensions selected")
    }
}

struct PRDiffToolbarSettings: View {
    @Bindable var model: PRDiffModel
    var body: some View {
        Menu {
            Picker("Diff layout", selection: $model.style) {
                Text("Unified").tag("unified"); Text("Split").tag("split")
            }
            Toggle("Wrap lines", isOn: $model.wraps)
        } label: {
            Image(systemName: "gearshape").frame(width: 28, height: 28)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().focusEffectDisabled()
            .accessibilityLabel("Diff settings").help("Configure diff layout and wrapping")
    }
}

