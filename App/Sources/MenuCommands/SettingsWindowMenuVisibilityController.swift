import AppKit

@MainActor
protocol SettingsWindowMenuVisibilityControlling {
    func setSettingsWindowActive(_ isActive: Bool)
}

struct SettingsWindowMenuVisibilityController: SettingsWindowMenuVisibilityControlling {
    private let hiddenMenuTitles: Set<String>
    private let mainMenuProvider: @MainActor () -> NSMenu?

    init(
        hiddenMenuTitles: Set<String> = ["Edit", "View", "Window"],
        mainMenuProvider: @escaping @MainActor () -> NSMenu? = { NSApplication.shared.mainMenu }
    ) {
        self.hiddenMenuTitles = hiddenMenuTitles
        self.mainMenuProvider = mainMenuProvider
    }

    func setSettingsWindowActive(_ isActive: Bool) {
        guard let mainMenu = mainMenuProvider() else {
            return
        }

        for item in mainMenu.items where hiddenMenuTitles.contains(item.title) {
            item.isHidden = isActive
        }
    }
}
