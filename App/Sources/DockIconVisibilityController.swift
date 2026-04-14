import AppKit

protocol DockIconVisibilityControlling {
    @MainActor
    func apply(hideDockIcon: Bool)
}

struct DockIconVisibilityController: DockIconVisibilityControlling {
    @MainActor
    func apply(hideDockIcon: Bool) {
        let desiredPolicy: NSApplication.ActivationPolicy = hideDockIcon ? .accessory : .regular
        let app = NSApplication.shared

        guard app.activationPolicy() != desiredPolicy else {
            return
        }

        let didChangePolicy = app.setActivationPolicy(desiredPolicy)
        guard didChangePolicy, !hideDockIcon else {
            return
        }

        app.activate(ignoringOtherApps: true)
    }
}
