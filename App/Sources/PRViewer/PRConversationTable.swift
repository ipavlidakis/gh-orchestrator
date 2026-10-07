import AppKit
import SwiftUI

struct PRConversationTable: NSViewRepresentable {
    let model: PRViewerModel
    let openURL: (URL) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let table = context.coordinator.table
        table.autoresizingMask = [.width]
        table.frame = NSRect(origin: .zero, size: scroll.contentSize)
        scroll.documentView = table
        return scroll
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model, openURL: openURL) }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(rows: model.rows, revision: model.revision, focus: model.focusedRowID, focusRevision: model.focusRevision)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.cancelLayout()
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let table = NSTableView()
        private(set) var rows: [PRViewerRow] = []
        private var revision = -1
        private var focusRevision = -1
        private var pendingFocusID: String?
        private var expanded: Set<String> = []
        private var layouts: [String: PRConversationLayout] = [:]
        private var layoutWidth: CGFloat = 0
        private var layoutTask: Task<Void, Never>?
        private var layoutID = UUID()
        private let model: PRViewerModel
        private let openURL: (URL) -> Void

        init(model: PRViewerModel, openURL: @escaping (URL) -> Void) {
            self.model = model
            self.openURL = openURL
            super.init()
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("conversation"))
            column.resizingMask = .autoresizingMask
            table.addTableColumn(column)
            table.headerView = nil
            table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
            table.backgroundColor = .clear
            table.intercellSpacing = NSSize(width: 0, height: 12)
            table.selectionHighlightStyle = .none
            table.dataSource = self
            table.delegate = self
            table.setAccessibilityLabel("Pull request summary and activity")
        }

        func update(rows next: [PRViewerRow], revision: Int, focus: String?, focusRevision: Int) {
            if self.revision != revision {
                let old = rows.map(\.id), new = next.map(\.id)
                let oldIDs = Set(old), newIDs = Set(new)
                rows = next
                self.revision = revision
                expanded.formIntersection(newIDs)
                if old.filter(newIDs.contains) == new.filter(oldIDs.contains) {
                    table.beginUpdates()
                    table.removeRows(at: IndexSet(old.indices.filter { !newIDs.contains(old[$0]) }), withAnimation: [])
                    table.insertRows(at: IndexSet(new.indices.filter { !oldIDs.contains(new[$0]) }), withAnimation: [])
                    table.endUpdates()
                    let retained = IndexSet(new.indices.filter { oldIDs.contains(new[$0]) })
                    table.reloadData(forRowIndexes: retained, columnIndexes: IndexSet(integer: 0))
                } else {
                    table.reloadData()
                }
                prepareLayout()
            }
            if focusRevision != self.focusRevision, let focus, let index = rows.firstIndex(where: { $0.id == focus }) {
                table.scrollRowToVisible(index)
                pendingFocusID = layouts[focus] == nil ? focus : nil
            }
            self.focusRevision = focusRevision
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard !rows.isEmpty else { return }
            let width = table.frameOfCell(atColumn: 0, row: 0).width
            guard abs(width - layoutWidth) >= 1 else { return }
            layoutWidth = width
            prepareLayout()
        }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            layouts[rows[row].id]?.height ?? 220
        }

        private func prepareLayout() {
            layoutTask?.cancel()
            guard !rows.isEmpty else { layouts = [:]; return }
            let token = UUID()
            layoutID = token
            let items = rows, expanded = expanded
            let width = max(240, table.frameOfCell(atColumn: 0, row: 0).width - 96)
            layoutTask = Task.detached(priority: .userInitiated) { [weak self] in
                for start in stride(from: 0, to: items.count, by: 25) {
                    let indices = start..<min(start + 25, items.count)
                    var measured: [String: PRConversationLayout] = [:]
                    for index in indices {
                        if Task.isCancelled { return }
                        let item = items[index]
                        measured[item.id] = PRConversationLayout.measure(item, width: width, expanded: expanded.contains(item.id))
                    }
                    await self?.applyLayouts(measured, indices: IndexSet(integersIn: indices), token: token)
                }
            }
        }

        private func applyLayouts(_ measured: [String: PRConversationLayout], indices: IndexSet, token: UUID) {
            guard !Task.isCancelled, layoutID == token else { return }
            layouts.merge(measured) { _, new in new }
            table.noteHeightOfRows(withIndexesChanged: indices)
            let visible = table.rows(in: table.visibleRect)
            let changed = indices.intersection(IndexSet(integersIn: visible.location..<NSMaxRange(visible)))
            table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
            if let pendingFocusID, let index = rows.firstIndex(where: { $0.id == pendingFocusID }), indices.contains(index) {
                table.scrollRowToVisible(index)
                self.pendingFocusID = nil
            }
        }

        func cancelLayout() { layoutTask?.cancel() }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("comment")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? PRConversationCell ?? PRConversationCell()
            cell.identifier = identifier
            let item = rows[row]
            cell.configure(item, body: displayBody(item), layout: layouts[item.id], expanded: expanded.contains(item.id), openURL: openURL,
                           toggle: { [weak self] in self?.toggle(item.id) },
                           replies: { [weak model] in if let threadID = item.threadID { model?.loadReplies(threadID) } })
            return cell
        }

        private func displayBody(_ item: PRViewerRow) -> NSAttributedString {
            PRConversationLayout.body(item, expanded: expanded.contains(item.id))
        }

        private func toggle(_ id: String) {
            if !expanded.insert(id).inserted { expanded.remove(id) }
            prepareLayout()
        }
    }
}

struct PRConversationLayout: Sendable {
    let titleHeight: CGFloat
    let subtitleHeight: CGFloat
    let bodyHeight: CGFloat
    let height: CGFloat
    static func body(_ item: PRViewerRow, expanded: Bool) -> NSAttributedString {
        guard !item.isSummary, !expanded, item.body.length > 4000 else { return item.body }
        let range = (item.body.string as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: 0, length: 4000))
        return item.body.attributedSubstring(from: range)
    }

    static func measure(_ item: PRViewerRow, width: CGFloat, expanded: Bool) -> Self {
        let titleFont = NSFont.systemFont(ofSize: item.isSummary ? 24 : 14, weight: .semibold)
        let title = textHeight(NSAttributedString(string: item.title, attributes: [.font: titleFont]), width: width)
        let subtitle = textHeight(NSAttributedString(string: item.subtitle, attributes: [.font: NSFont.systemFont(ofSize: 12)]), width: width)
        let collapsed = !item.isSummary && !expanded
        let text = body(item, expanded: expanded)
        let bodyHeight = textHeight(text, width: width, maximum: collapsed ? 321 : 1_000_000)
        let visible = collapsed ? min(320, bodyHeight) : bodyHeight
        return Self(titleHeight: title, subtitleHeight: subtitle, bodyHeight: bodyHeight,
                    height: title + subtitle + visible + (item.body.length > 0 ? 80 : 44) + (item.threadID == nil ? 0 : 28))
    }

    private static func textHeight(_ text: NSAttributedString, width: CGFloat, maximum: CGFloat = 1_000_000) -> CGFloat {
        guard text.length > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: width, height: maximum))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let glyphs = manager.glyphRange(for: container)
        let clipped = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil).length < text.length
        return clipped ? maximum : ceil(manager.usedRect(for: container).height)
    }
}

@MainActor
final class PRConversationCell: NSTableCellView {
    private let card = NSView()
    private let title = NSTextField(wrappingLabelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let avatar = NSTextField(labelWithString: "")
    private let bodyView = NSTextView()
    private let expand = NSButton(title: "Expand", target: nil, action: nil)
    private let link = NSButton(title: "Open on GitHub", target: nil, action: nil)
    private let replies = NSButton(title: "Load more replies", target: nil, action: nil)
    private var toggleAction: (() -> Void)?
    private var linkAction: (() -> Void)?
    private var repliesAction: (() -> Void)?
    private var summary = false
    private var expanded = false
    private var fullLength = 0
    private var metrics: PRConversationLayout?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(card)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 0.5
        for view in [title, subtitle, avatar, bodyView, expand, link, replies] { card.addSubview(view) }
        avatar.font = .systemFont(ofSize: 11, weight: .semibold)
        avatar.alignment = .center
        avatar.drawsBackground = true
        avatar.backgroundColor = .quaternaryLabelColor
        avatar.wantsLayer = true
        avatar.layer?.cornerRadius = 14
        avatar.layer?.masksToBounds = true
        title.isSelectable = true
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 12)
        bodyView.isEditable = false
        bodyView.isSelectable = true
        bodyView.drawsBackground = false
        bodyView.textContainerInset = .zero
        bodyView.textContainer?.lineFragmentPadding = 0
        bodyView.isHorizontallyResizable = false
        bodyView.isVerticallyResizable = false
        bodyView.autoresizingMask = []
        bodyView.textContainer?.widthTracksTextView = true
        for button in [expand, link, replies] { button.isBordered = false; button.font = .systemFont(ofSize: 12); button.target = self }
        expand.action = #selector(toggle)
        link.action = #selector(openLink)
        replies.action = #selector(loadReplies)
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ row: PRViewerRow, body: NSAttributedString, layout: PRConversationLayout?, expanded: Bool, openURL: @escaping (URL) -> Void, toggle: @escaping () -> Void, replies: @escaping () -> Void) {
        summary = row.isSummary
        self.expanded = expanded
        fullLength = row.body.length
        metrics = layout
        title.stringValue = row.title
        avatar.stringValue = String(row.title.prefix(2)).uppercased()
        avatar.isHidden = summary
        title.font = .systemFont(ofSize: summary ? 24 : 14, weight: .semibold)
        subtitle.stringValue = row.subtitle
        bodyView.textStorage?.setAttributedString(body)
        expand.title = expanded ? "Collapse" : "Expand"
        link.isHidden = row.url == nil
        self.replies.isHidden = row.threadID == nil
        toggleAction = toggle
        linkAction = { if let url = row.url { openURL(url) } }
        repliesAction = replies
        setAccessibilityLabel("\(row.title). \(row.subtitle)")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        card.frame = NSRect(x: 24, y: 0, width: max(1, bounds.width - 48), height: bounds.height)
        card.layer?.backgroundColor = (summary ? NSColor.clear : NSColor.controlBackgroundColor).cgColor
        card.layer?.borderColor = (summary ? NSColor.clear : NSColor.separatorColor).cgColor
        let width = max(1, card.bounds.width - 48)
        var y = card.bounds.height - 16
        let titleHeight = metrics?.titleHeight ?? (summary ? 30 : 18)
        let titleX: CGFloat = summary ? 24 : 60
        avatar.frame = NSRect(x: 20, y: y - 28, width: 28, height: 28)
        title.frame = NSRect(x: titleX, y: y - titleHeight, width: width - (titleX - 24), height: titleHeight)
        y -= titleHeight + 8
        let subtitleHeight = metrics?.subtitleHeight ?? (subtitle.stringValue.isEmpty ? 0 : 16)
        subtitle.frame = NSRect(x: 24, y: y - subtitleHeight, width: width, height: subtitleHeight)
        y -= subtitleHeight + 12
        let footer: CGFloat = fullLength == 0 ? 0 : 28
        let repliesHeight: CGFloat = replies.isHidden ? 0 : 28
        let bodyHeight = max(0, y - 16 - footer - repliesHeight)
        bodyView.frame = NSRect(x: 24, y: y - bodyHeight, width: width, height: bodyHeight)
        bodyView.textContainer?.containerSize = NSSize(width: width, height: bodyHeight)
        expand.isHidden = summary || (!expanded && fullLength <= 4000 && (metrics?.bodyHeight ?? 0) <= 320)
        expand.frame = NSRect(x: width - 70 + 24, y: 12 + repliesHeight, width: 70, height: 24)
        link.frame = NSRect(x: 24, y: 12 + repliesHeight, width: 120, height: 24)
        replies.frame = NSRect(x: 24, y: 8, width: 160, height: 24)
    }

    @objc private func toggle() { toggleAction?() }
    @objc private func openLink() { linkAction?() }
    @objc private func loadReplies() { repliesAction?() }
}
