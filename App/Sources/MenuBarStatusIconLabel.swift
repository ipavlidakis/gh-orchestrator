import AppKit
import SwiftUI

struct MenuBarStatusIconLabel: View {
    let applicationIconController: ApplicationIconController

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(nsImage: Self.menuBarTemplateImage)
            .accessibilityLabel(AppMetadata.menuBarTitle)
            .onChange(of: colorScheme, initial: true) { _, newColorScheme in
                applicationIconController.apply(colorScheme: newColorScheme)
            }
    }

    @MainActor
    private static var menuBarTemplateImage: NSImage {
        let image = (NSImage(named: NSImage.Name("MenuBarIcon"))?.copy() as? NSImage) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
