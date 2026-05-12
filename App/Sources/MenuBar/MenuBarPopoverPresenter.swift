import AppKit
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
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
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
    }

    private func configurePopover() {
        configuration.apply(to: popover)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPlaceholderView(
                model: controller.dashboardModel,
                softwareUpdateModel: softwareUpdateModel,
                openSettingsAction: { [weak self] in
                    self?.openSettingsWindow()
                },
                onMenuVisibilityChange: { [weak controller] isVisible in
                    controller?.setMenuVisible(isVisible)
                }
            )
            .frame(
                width: configuration.contentSize.width,
                height: configuration.contentSize.height,
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
