import AppKit
import GHOrchestratorCore
import SwiftUI

struct MenuBarPopoverConfiguration: Equatable {
    let contentSize: CGSize

    static let dashboard = MenuBarPopoverConfiguration(
        contentSize: CGSize(width: 440, height: 620)
    )

    @MainActor
    func apply(to popover: NSPopover) {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = contentSize
    }
}

@MainActor
final class MenuBarPopoverPresenter: NSObject, NSPopoverDelegate {
    private let controller: AppController
    private let softwareUpdateModel: SoftwareUpdateModel
    private let configuration: MenuBarPopoverConfiguration
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    /// Height the dashboard asked for, so the popover fits its content instead of a fixed size.
    private var preferredHeight: CGFloat?

    init(
        controller: AppController,
        softwareUpdateModel: SoftwareUpdateModel,
        applicationIconController: ApplicationIconController,
        configuration: MenuBarPopoverConfiguration = .dashboard
    ) {
        self.controller = controller
        self.softwareUpdateModel = softwareUpdateModel
        self.configuration = configuration
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        configureStatusItem(applicationIconController: applicationIconController)
        configurePopover()
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else {
            return
        }

        configuration.apply(to: popover)
        applyPreferredHeight()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func updatePreferredHeight(_ height: CGFloat) {
        guard height > 1 else { return }
        preferredHeight = min(height.rounded(.up), configuration.contentSize.height)
        applyPreferredHeight()
    }

    private func applyPreferredHeight() {
        guard let preferredHeight, popover.contentSize.height != preferredHeight else { return }
        popover.contentSize = CGSize(width: configuration.contentSize.width, height: preferredHeight)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func popoverWillShow(_: Notification) {
        controller.setMenuVisible(true)
    }

    func popoverDidClose(_: Notification) {
        controller.setMenuVisible(false)
    }

    private func configureStatusItem(applicationIconController: ApplicationIconController) {
        guard let button = statusItem.button else {
            return
        }

        button.image = Self.menuBarTemplateImage
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover)
        button.toolTip = AppMetadata.menuBarTitle
        button.setAccessibilityLabel(AppMetadata.menuBarTitle)
        applicationIconController.applyCurrentSystemAppearance()
        observeStatus()
    }

    /// Re-renders the menu bar glyph whenever the dashboard changes.
    private func observeStatus() {
        withObservationTracking {
            updateStatusImage()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeStatus()
            }
        }
    }

    private func updateStatusImage() {
        guard let button = statusItem.button else { return }
        let status = MenuBarGlyphStatus(contentState: controller.dashboardModel.contentState)
        let base = Self.menuBarTemplateImage

        let attention = controller.dashboardModel.attentionCount
        button.title = attention > 0 ? " \(attention)" : ""
        button.imagePosition = attention > 0 ? .imageLeading : .imageOnly
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)

        guard let badgeColor = status.badgeColor else {
            button.image = base
            return
        }

        let isDark = button.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        button.image = Self.badgedImage(base: base, badge: badgeColor, glyph: isDark ? .white : .black)
        button.setAccessibilityValue(status.accessibilityValue)
    }

    private static func badgedImage(base: NSImage, badge: NSColor, glyph: NSColor) -> NSImage {
        let size = base.size == .zero ? NSSize(width: 18, height: 18) : base.size
        let image = NSImage(size: size, flipped: false) { rect in
            glyph.setFill()
            rect.fill()
            base.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)

            let diameter = rect.width * 0.34
            let dot = NSRect(x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            badge.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func configurePopover() {
        configuration.apply(to: popover)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPlaceholderView(
                model: controller.dashboardModel,
                softwareUpdateModel: softwareUpdateModel,
                requestLogModel: controller.requestLogModel,
                maximumHeight: configuration.contentSize.height,
                onPreferredHeightChange: { [weak self] height in
                    self?.updatePreferredHeight(height)
                },
                openSettingsAction: { [weak self] in
                    self?.openSettingsWindow()
                },
                openURLAction: { [weak controller] url in
                    controller?.openURL(url)
                },
                onMenuVisibilityChange: { [weak controller] isVisible in
                    controller?.setMenuVisible(isVisible)
                }
            )
            .frame(
                width: configuration.contentSize.width,
                alignment: .topLeading
            )
        )
    }

    private func openSettingsWindow() {
        closePopover()
        let application = NSApplication.shared
        application.activate(ignoringOtherApps: true)

        if !Self.performSettingsMenuItemAction(in: application.mainMenu),
           !application.sendAction(
               Selector(("showSettingsWindow:")),
               to: nil,
               from: nil
           )
        {
            application.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }

        Task { @MainActor [application] in
            application.activate(ignoringOtherApps: true)
        }
    }

    private static var menuBarTemplateImage: NSImage {
        let image = (NSImage(named: NSImage.Name("MenuBarIcon"))?.copy() as? NSImage) ?? NSImage()
        image.isTemplate = true
        return image
    }

    static func performSettingsMenuItemAction(in mainMenu: NSMenu?) -> Bool {
        guard
            let settingsItem = settingsMenuItem(in: mainMenu),
            let menu = settingsItem.menu,
            let itemIndex = menu.items.firstIndex(of: settingsItem),
            settingsItem.isEnabled
        else {
            return false
        }

        menu.performActionForItem(at: itemIndex)
        return true
    }

    private static func settingsMenuItem(in mainMenu: NSMenu?) -> NSMenuItem? {
        let settingsTitles = Set(["Settings…", "Settings...", "Preferences…", "Preferences..."])

        return mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { settingsTitles.contains($0.title) }
    }
}


/// Aggregate CI state of the visible pull requests, shown as a badge on the menu bar glyph.
enum MenuBarGlyphStatus: Equatable {
    case idle
    case pending
    case failing

    init(contentState: MenuBarDashboardModel.State) {
        guard case .loaded(let sections) = contentState else {
            self = .idle
            return
        }

        let states = sections.flatMap(\.pullRequests).map(\.checkRollupState)
        if states.contains(.failing) {
            self = .failing
        } else if states.contains(.pending) {
            self = .pending
        } else {
            self = .idle
        }
    }

    var badgeColor: NSColor? {
        switch self {
        case .idle: nil
        case .pending: .systemOrange
        case .failing: .systemRed
        }
    }

    var accessibilityValue: String {
        switch self {
        case .idle: ""
        case .pending: "Checks pending"
        case .failing: "Checks failing"
        }
    }
}
