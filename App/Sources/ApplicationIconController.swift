import AppKit
import SwiftUI

@MainActor
protocol ApplicationIconControlling {
    func apply(colorScheme: ColorScheme)
    func applyCurrentSystemAppearance()
}

@MainActor
struct ApplicationIconController: ApplicationIconControlling {
    private let setApplicationIconImage: (NSImage) -> Void
    private let imageLoader: (String) -> NSImage?

    init(
        setApplicationIconImage: @escaping @MainActor (NSImage) -> Void = { image in
            NSApplication.shared.applicationIconImage = image
        },
        imageLoader: @escaping (String) -> NSImage? = { name in
            NSImage(named: NSImage.Name(name))
        }
    ) {
        self.setApplicationIconImage = setApplicationIconImage
        self.imageLoader = imageLoader
    }

    func apply(colorScheme: ColorScheme) {
        apply(assetName: DockIconAssetName.forColorScheme(colorScheme))
    }

    func applyCurrentSystemAppearance() {
        apply(assetName: DockIconAssetName.forAppearance(NSApplication.shared.effectiveAppearance))
    }

    private func apply(assetName: String) {
        guard let image = imageLoader(assetName) else {
            return
        }

        setApplicationIconImage(image)
    }
}

enum DockIconAssetName {
    static func forColorScheme(_ colorScheme: ColorScheme) -> String {
        switch colorScheme {
        case .light:
            return "DockIconLight"
        case .dark:
            return "DockIconDark"
        @unknown default:
            return "DockIconDark"
        }
    }

    static func forAppearance(_ appearance: NSAppearance) -> String {
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .aqua ? "DockIconLight" : "DockIconDark"
    }
}
