#!/usr/bin/env swift

import AppKit
import Foundation

private let artboardSize: CGFloat = 1024

private struct IconPalette {
    let backgroundColors: [NSColor]
    let panelColors: [NSColor]
    let panelStroke: NSColor
    let rim: NSColor
    let shadow: NSColor
    let glyph: NSColor
    let glow: NSColor
    let orbit: NSColor
    let leftNode: NSColor
    let topNode: NSColor
    let lowerRightNode: NSColor
    let branchNode: NSColor
    let nodeHighlight: NSColor
}

private let darkPalette = IconPalette(
    backgroundColors: [
        color(0x06, 0x10, 0x23),
        color(0x10, 0x2C, 0x5E),
        color(0x2A, 0x65, 0xF0)
    ],
    panelColors: [
        color(0xA7, 0xD0, 0xFF, alpha: 0.24),
        color(0x4D, 0xD8, 0xFF, alpha: 0.10)
    ],
    panelStroke: color(0xF6, 0xFA, 0xFF, alpha: 0.20),
    rim: color(0xF8, 0xFB, 0xFF, alpha: 0.18),
    shadow: color(0x00, 0x00, 0x00, alpha: 0.32),
    glyph: color(0xF7, 0xFB, 0xFF),
    glow: color(0x5D, 0xE5, 0xFF, alpha: 0.32),
    orbit: color(0x7B, 0xF0, 0xFF, alpha: 0.34),
    leftNode: color(0x80, 0xD4, 0xFF),
    topNode: color(0xFF, 0xC4, 0x73),
    lowerRightNode: color(0x74, 0xF1, 0xC4),
    branchNode: color(0xF7, 0xFB, 0xFF),
    nodeHighlight: color(0xFF, 0xFF, 0xFF, alpha: 0.48)
)

private let lightPalette = IconPalette(
    backgroundColors: [
        color(0xFB, 0xFD, 0xFF),
        color(0xE8, 0xF1, 0xFF),
        color(0xB9, 0xD2, 0xFF)
    ],
    panelColors: [
        color(0xFF, 0xFF, 0xFF, alpha: 0.80),
        color(0xDD, 0xEB, 0xFF, alpha: 0.64)
    ],
    panelStroke: color(0xFF, 0xFF, 0xFF, alpha: 0.76),
    rim: color(0xFF, 0xFF, 0xFF, alpha: 0.88),
    shadow: color(0x1B, 0x3B, 0x74, alpha: 0.10),
    glyph: color(0x10, 0x26, 0x4F),
    glow: color(0x4F, 0xBE, 0xFF, alpha: 0.22),
    orbit: color(0x52, 0xAB, 0xFF, alpha: 0.26),
    leftNode: color(0x2E, 0x95, 0xE8),
    topNode: color(0xD4, 0x76, 0x2C),
    lowerRightNode: color(0x1E, 0xB3, 0x99),
    branchNode: color(0x10, 0x26, 0x4F),
    nodeHighlight: color(0xFF, 0xFF, 0xFF, alpha: 0.62)
)

private let iconOutputs: [(filename: String, size: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

private let fileManager = FileManager.default
private let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
private let assetsURL = rootURL.appendingPathComponent("App/Resources/Assets.xcassets", isDirectory: true)
private let appIconURL = assetsURL.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
private let darkDockURL = assetsURL.appendingPathComponent("DockIconDark.imageset", isDirectory: true)
private let lightDockURL = assetsURL.appendingPathComponent("DockIconLight.imageset", isDirectory: true)
private let menuBarURL = assetsURL.appendingPathComponent("MenuBarIcon.imageset", isDirectory: true)
private let previewFileURL = fileManager.temporaryDirectory.appendingPathComponent("ghorchestrator-icon-preview.png")

try fileManager.createDirectory(at: appIconURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: darkDockURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: lightDockURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: menuBarURL, withIntermediateDirectories: true)

for output in iconOutputs {
    let data = makePNG(size: output.size) { rect in
        drawAppIcon(in: rect, palette: darkPalette)
    }
    try data.write(to: appIconURL.appendingPathComponent(output.filename))
}

let darkDockPDF = makePDF(size: CGSize(width: artboardSize, height: artboardSize)) { rect in
    drawAppIcon(in: rect, palette: darkPalette)
}
try darkDockPDF.write(to: darkDockURL.appendingPathComponent("DockIconDark.pdf"))

let lightDockPDF = makePDF(size: CGSize(width: artboardSize, height: artboardSize)) { rect in
    drawAppIcon(in: rect, palette: lightPalette)
}
try lightDockPDF.write(to: lightDockURL.appendingPathComponent("DockIconLight.pdf"))

let menuBarPDF = makePDF(size: CGSize(width: 18, height: 18)) { rect in
    drawMenuBarGlyph(in: rect)
}
try menuBarPDF.write(to: menuBarURL.appendingPathComponent("MenuBarIcon.pdf"))

let previewPNG = makePNG(size: 1600, height: 1200) { rect in
    drawPreview(in: rect)
}
try previewPNG.write(to: previewFileURL)

print("Generated icon assets:")
print("- \(appIconURL.path)")
print("- \(darkDockURL.path)")
print("- \(lightDockURL.path)")
print("- \(menuBarURL.path)")
print("- \(previewFileURL.path)")

private func drawAppIcon(in rect: CGRect, palette: IconPalette) {
    let badgeRect = fittedRect(x: 58, y: 58, width: 908, height: 908, in: rect)
    let badgePath = NSBezierPath(
        roundedRect: badgeRect,
        xRadius: scaled(228, in: rect),
        yRadius: scaled(228, in: rect)
    )

    withSavedGraphicsState {
        let shadow = NSShadow()
        shadow.shadowColor = palette.shadow
        shadow.shadowBlurRadius = scaled(56, in: rect)
        shadow.shadowOffset = NSSize(width: 0, height: scaled(-24, in: rect))
        shadow.set()
        palette.backgroundColors.last?.setFill()
        badgePath.fill()
    }

    withSavedGraphicsState {
        badgePath.addClip()
        drawLinearGradient(
            colors: palette.backgroundColors,
            from: point(180, 1000, in: rect),
            to: point(820, 0, in: rect)
        )
        drawRadialGlow(
            in: fittedRect(x: 84, y: 594, width: 540, height: 420, in: rect),
            color: palette.glow
        )
        drawRadialGlow(
            in: fittedRect(x: 494, y: 64, width: 420, height: 420, in: rect),
            color: palette.orbit
        )
        drawSoftTopBand(in: rect)
        drawGlassPanel(in: rect, palette: palette)
        drawOrbit(in: rect, palette: palette)
        drawBranchGlyph(in: rect, palette: palette)
    }

    palette.rim.setStroke()
    badgePath.lineWidth = scaled(10, in: rect)
    badgePath.stroke()
}

private func drawSoftTopBand(in rect: CGRect) {
    let bandRect = fittedRect(x: 76, y: 670, width: 620, height: 220, in: rect)
    let bandPath = NSBezierPath(roundedRect: bandRect, xRadius: scaled(140, in: rect), yRadius: scaled(140, in: rect))
    let gradient = NSGradient(colors: [
        color(0xFF, 0xFF, 0xFF, alpha: 0.22),
        color(0xFF, 0xFF, 0xFF, alpha: 0.00)
    ])!
    gradient.draw(in: bandPath, angle: -18)
}

private func drawGlassPanel(in rect: CGRect, palette: IconPalette) {
    let panelRect = fittedRect(x: 178, y: 198, width: 668, height: 640, in: rect)
    let panelPath = NSBezierPath(
        roundedRect: panelRect,
        xRadius: scaled(176, in: rect),
        yRadius: scaled(176, in: rect)
    )
    var transform = AffineTransform.identity
    transform.translate(x: rect.midX, y: rect.midY)
    transform.rotate(byDegrees: -10)
    transform.translate(x: -rect.midX, y: -rect.midY)
    panelPath.transform(using: transform)

    withSavedGraphicsState {
        panelPath.addClip()
        drawLinearGradient(
            colors: palette.panelColors,
            from: point(250, 880, in: rect),
            to: point(770, 120, in: rect)
        )
        drawRadialGlow(
            in: fittedRect(x: 206, y: 610, width: 360, height: 260, in: rect),
            color: color(0xFF, 0xFF, 0xFF, alpha: 0.16)
        )
    }

    palette.panelStroke.setStroke()
    panelPath.lineWidth = scaled(7, in: rect)
    panelPath.stroke()
}

private func drawOrbit(in rect: CGRect, palette: IconPalette) {
    let orbit = NSBezierPath()
    orbit.appendArc(
        withCenter: point(502, 528, in: rect),
        radius: scaled(324, in: rect),
        startAngle: 204,
        endAngle: 18
    )
    orbit.lineWidth = scaled(42, in: rect)
    orbit.lineCapStyle = .round
    palette.orbit.setStroke()
    orbit.stroke()

    let innerOrbit = NSBezierPath()
    innerOrbit.appendArc(
        withCenter: point(514, 522, in: rect),
        radius: scaled(252, in: rect),
        startAngle: 192,
        endAngle: 28
    )
    innerOrbit.lineWidth = scaled(16, in: rect)
    innerOrbit.lineCapStyle = .round
    color(0xFF, 0xFF, 0xFF, alpha: 0.18).setStroke()
    innerOrbit.stroke()

    drawNode(
        center: point(798, 620, in: rect),
        radius: scaled(22, in: rect),
        fill: color(0xFF, 0xFF, 0xFF, alpha: 0.50),
        rim: color(0xFF, 0xFF, 0xFF, alpha: 0.18),
        highlight: nil
    )
}

private func drawBranchGlyph(in rect: CGRect, palette: IconPalette) {
    let paths = makeGlyphPaths(in: rect)

    for path in paths {
        let glowPath = path.copy() as! NSBezierPath
        glowPath.lineWidth = scaled(132, in: rect)
        glowPath.lineCapStyle = .round
        glowPath.lineJoinStyle = .round
        palette.glow.setStroke()
        glowPath.stroke()
    }

    for path in paths {
        let glyphPath = path.copy() as! NSBezierPath
        glyphPath.lineWidth = scaled(88, in: rect)
        glyphPath.lineCapStyle = .round
        glyphPath.lineJoinStyle = .round
        palette.glyph.setStroke()
        glyphPath.stroke()
    }

    drawNode(
        center: point(300, 560, in: rect),
        radius: scaled(76, in: rect),
        fill: palette.leftNode,
        rim: color(0xFF, 0xFF, 0xFF, alpha: 0.18),
        highlight: palette.nodeHighlight
    )
    drawNode(
        center: point(590, 746, in: rect),
        radius: scaled(74, in: rect),
        fill: palette.topNode,
        rim: color(0xFF, 0xFF, 0xFF, alpha: 0.16),
        highlight: palette.nodeHighlight
    )
    drawNode(
        center: point(720, 314, in: rect),
        radius: scaled(78, in: rect),
        fill: palette.lowerRightNode,
        rim: color(0xFF, 0xFF, 0xFF, alpha: 0.18),
        highlight: palette.nodeHighlight
    )
    drawNode(
        center: point(508, 504, in: rect),
        radius: scaled(58, in: rect),
        fill: palette.branchNode,
        rim: color(0xFF, 0xFF, 0xFF, alpha: 0.20),
        highlight: color(0xFF, 0xFF, 0xFF, alpha: 0.20)
    )
}

private func drawMenuBarGlyph(in rect: CGRect) {
    color(0x00, 0x00, 0x00).setStroke()
    color(0x00, 0x00, 0x00).setFill()

    for path in makeGlyphPaths(in: rect) {
        let glyphPath = path.copy() as! NSBezierPath
        glyphPath.lineWidth = scaled(154, in: rect)
        glyphPath.lineCapStyle = .round
        glyphPath.lineJoinStyle = .round
        glyphPath.stroke()
    }

    for center in [
        point(300, 560, in: rect),
        point(590, 746, in: rect),
        point(720, 314, in: rect),
        point(508, 504, in: rect)
    ] {
        NSBezierPath(ovalIn: CGRect(
            x: center.x - scaled(94, in: rect) / 2,
            y: center.y - scaled(94, in: rect) / 2,
            width: scaled(94, in: rect),
            height: scaled(94, in: rect)
        )).fill()
    }
}

private func makeGlyphPaths(in rect: CGRect) -> [NSBezierPath] {
    let lowerRight = point(720, 314, in: rect)
    let branch = point(508, 504, in: rect)
    let left = point(300, 560, in: rect)
    let top = point(590, 746, in: rect)

    let trunk = NSBezierPath()
    trunk.move(to: lowerRight)
    trunk.curve(
        to: branch,
        controlPoint1: point(646, 362, in: rect),
        controlPoint2: point(566, 436, in: rect)
    )

    let leftBranch = NSBezierPath()
    leftBranch.move(to: branch)
    leftBranch.curve(
        to: left,
        controlPoint1: point(438, 514, in: rect),
        controlPoint2: point(352, 544, in: rect)
    )

    let topBranch = NSBezierPath()
    topBranch.move(to: branch)
    topBranch.curve(
        to: top,
        controlPoint1: point(548, 566, in: rect),
        controlPoint2: point(588, 656, in: rect)
    )

    return [trunk, leftBranch, topBranch]
}

private func drawNode(center: CGPoint, radius: CGFloat, fill: NSColor, rim: NSColor, highlight: NSColor?) {
    let nodeRect = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
    )
    let nodePath = NSBezierPath(ovalIn: nodeRect)

    withSavedGraphicsState {
        let shadow = NSShadow()
        shadow.shadowColor = color(0x00, 0x00, 0x00, alpha: 0.16)
        shadow.shadowBlurRadius = radius * 0.26
        shadow.shadowOffset = NSSize(width: 0, height: -radius * 0.10)
        shadow.set()
        fill.setFill()
        nodePath.fill()
    }

    rim.setStroke()
    nodePath.lineWidth = max(radius * 0.10, 2)
    nodePath.stroke()

    guard let highlight else {
        return
    }

    let gleamRect = CGRect(
        x: nodeRect.minX + radius * 0.22,
        y: nodeRect.midY,
        width: radius * 0.72,
        height: radius * 0.52
    )
    let gleamPath = NSBezierPath(ovalIn: gleamRect)
    highlight.setFill()
    gleamPath.fill()
}

private func drawPreview(in rect: CGRect) {
    color(0xEE, 0xF3, 0xFC).setFill()
    rect.fill()

    let leftCard = CGRect(x: 96, y: 430, width: 560, height: 560)
    let rightCard = CGRect(x: 944, y: 430, width: 560, height: 560)

    drawPreviewCard(title: "Light Dock", subtitle: "light appearance", frame: leftCard) {
        drawAppIcon(in: leftCard.insetBy(dx: 26, dy: 26), palette: lightPalette)
    }
    drawPreviewCard(title: "Dark Dock", subtitle: "dark appearance", frame: rightCard) {
        drawAppIcon(in: rightCard.insetBy(dx: 26, dy: 26), palette: darkPalette)
    }

    let lightMenu = CGRect(x: 96, y: 120, width: 640, height: 180)
    let darkMenu = CGRect(x: 864, y: 120, width: 640, height: 180)

    drawMenuBarPreview(frame: lightMenu, background: color(0xF8, 0xFA, 0xFD), title: "Light Menu Bar")
    drawMenuBarPreview(frame: darkMenu, background: color(0x1D, 0x21, 0x2A), title: "Dark Menu Bar")
}

private func drawPreviewCard(title: String, subtitle: String, frame: CGRect, drawIcon: () -> Void) {
    let card = NSBezierPath(roundedRect: frame, xRadius: 42, yRadius: 42)
    color(0xFF, 0xFF, 0xFF, alpha: 0.92).setFill()
    card.fill()
    color(0xD7, 0xE1, 0xEF).setStroke()
    card.lineWidth = 2
    card.stroke()
    drawIcon()
    drawPreviewText(title: title, subtitle: subtitle, in: CGRect(x: frame.minX, y: frame.minY - 94, width: frame.width, height: 72))
}

private func drawMenuBarPreview(frame: CGRect, background: NSColor, title: String) {
    let band = NSBezierPath(roundedRect: frame, xRadius: 28, yRadius: 28)
    background.setFill()
    band.fill()
    color(0xA5, 0xB7, 0xCF, alpha: background.brightnessComponent > 0.5 ? 0.40 : 0.12).setStroke()
    band.lineWidth = 2
    band.stroke()

    let iconFrame = CGRect(x: frame.minX + 40, y: frame.minY + 48, width: 84, height: 84)
    withSavedGraphicsState {
        if background.brightnessComponent < 0.5 {
            color(0xFF, 0xFF, 0xFF).setStroke()
            color(0xFF, 0xFF, 0xFF).setFill()
        } else {
            color(0x14, 0x19, 0x24).setStroke()
            color(0x14, 0x19, 0x24).setFill()
        }
        drawMenuBarGlyph(in: iconFrame)
    }

    drawPreviewText(title: title, subtitle: "template-rendered glyph", in: CGRect(x: frame.minX + 156, y: frame.minY + 52, width: 360, height: 60), aligned: .left)
}

private func drawPreviewText(title: String, subtitle: String, in rect: CGRect, aligned: NSTextAlignment = .center) {
    let titleParagraph = NSMutableParagraphStyle()
    titleParagraph.alignment = aligned
    let subtitleParagraph = NSMutableParagraphStyle()
    subtitleParagraph.alignment = aligned

    NSAttributedString(
        string: title,
        attributes: [
            .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
            .foregroundColor: color(0x1B, 0x24, 0x36),
            .paragraphStyle: titleParagraph
        ]
    ).draw(in: CGRect(x: rect.minX, y: rect.minY + 24, width: rect.width, height: 30))

    NSAttributedString(
        string: subtitle,
        attributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: color(0x5A, 0x6B, 0x84),
            .paragraphStyle: subtitleParagraph
        ]
    ).draw(in: CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 22))
}

private func makePNG(size: Int, height: Int? = nil, draw: (CGRect) -> Void) -> Data {
    let pixelHeight = height ?? size
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: pixelHeight)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(CGRect(x: 0, y: 0, width: size, height: pixelHeight))
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

private func makePDF(size: CGSize, draw: (CGRect) -> Void) -> Data {
    let data = NSMutableData()
    var mediaBox = CGRect(origin: .zero, size: size)
    let consumer = CGDataConsumer(data: data as CFMutableData)!
    let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!

    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    draw(mediaBox)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()

    return data as Data
}

private func drawLinearGradient(colors: [NSColor], from startPoint: CGPoint, to endPoint: CGPoint) {
    NSGradient(colors: colors)!.draw(from: startPoint, to: endPoint, options: [])
}

private func drawRadialGlow(in rect: CGRect, color: NSColor) {
    let gradient = NSGradient(colors: [color, color.withAlphaComponent(0.0)])!
    gradient.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
}

private func point(_ x: CGFloat, _ y: CGFloat, in rect: CGRect) -> CGPoint {
    CGPoint(
        x: rect.minX + (x / artboardSize) * rect.width,
        y: rect.minY + (y / artboardSize) * rect.height
    )
}

private func fittedRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, in rect: CGRect) -> CGRect {
    CGRect(
        x: rect.minX + (x / artboardSize) * rect.width,
        y: rect.minY + (y / artboardSize) * rect.height,
        width: (width / artboardSize) * rect.width,
        height: (height / artboardSize) * rect.height
    )
}

private func scaled(_ value: CGFloat, in rect: CGRect) -> CGFloat {
    value * min(rect.width, rect.height) / artboardSize
}

private func color(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1.0) -> NSColor {
    NSColor(
        srgbRed: CGFloat(red) / 255,
        green: CGFloat(green) / 255,
        blue: CGFloat(blue) / 255,
        alpha: alpha
    )
}

private func withSavedGraphicsState(_ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

private extension NSColor {
    var brightnessComponent: CGFloat {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return 0
        }

        return (rgb.redComponent * 0.299) + (rgb.greenComponent * 0.587) + (rgb.blueComponent * 0.114)
    }
}
