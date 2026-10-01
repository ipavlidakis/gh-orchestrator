#!/usr/bin/env swift

import AppKit
import Foundation

private let artboardSize: CGFloat = 1024

private struct IconPalette {
    let backgroundColors: [NSColor]
    let ink: NSColor
    let shadow: NSColor
    let rim: NSColor
    let success: NSColor
    let warning: NSColor
}

private let darkPalette = IconPalette(
    backgroundColors: [color(0x86, 0x72, 0xEE), color(0x4A, 0x37, 0xB5), color(0x24, 0x16, 0x60)],
    ink: color(0x24, 0x16, 0x60),
    shadow: color(0x12, 0x0A, 0x38, alpha: 0.35),
    rim: color(0xFF, 0xFF, 0xFF, alpha: 0.18),
    success: color(0x3F, 0xB9, 0x50),
    warning: color(0xF0, 0x88, 0x3E)
)

private let lightPalette = IconPalette(
    backgroundColors: [color(0x86, 0x72, 0xEE), color(0x4A, 0x37, 0xB5), color(0x2A, 0x1B, 0x70)],
    ink: color(0x2A, 0x1B, 0x70),
    shadow: color(0x24, 0x16, 0x60, alpha: 0.30),
    rim: color(0xFF, 0xFF, 0xFF, alpha: 0.22),
    success: color(0x2E, 0xA0, 0x43),
    warning: color(0xF0, 0x88, 0x3E)
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
        shadow.shadowBlurRadius = scaled(40, in: rect)
        shadow.shadowOffset = NSSize(width: 0, height: scaled(-20, in: rect))
        shadow.set()
        palette.backgroundColors.last?.setFill()
        badgePath.fill()
    }

    withSavedGraphicsState {
        badgePath.addClip()
        drawLinearGradient(
            colors: palette.backgroundColors,
            from: point(512, 1000, in: rect),
            to: point(512, 60, in: rect)
        )
        drawBranchGraph(in: rect, palette: palette)
    }

    palette.rim.setStroke()
    badgePath.lineWidth = scaled(8, in: rect)
    badgePath.stroke()
}

private func drawBranchGraph(in rect: CGRect, palette: IconPalette) {
    let top = point(368, 736, in: rect)
    let bottom = point(368, 288, in: rect)
    let branch = point(656, 624, in: rect)

    let trunk = NSBezierPath()
    trunk.move(to: top)
    trunk.line(to: bottom)

    let merge = NSBezierPath()
    merge.move(to: branch)
    merge.curve(
        to: point(368, 344, in: rect),
        controlPoint1: point(656, 432, in: rect),
        controlPoint2: point(520, 384, in: rect)
    )

    for path in [trunk, merge] {
        path.lineWidth = scaled(64, in: rect)
        path.lineCapStyle = .round
        NSColor.white.setStroke()
        path.stroke()
    }

    for center in [top, bottom, branch] {
        let radius = scaled(78, in: rect)
        let node = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        palette.ink.setFill()
        node.fill()
        NSColor.white.setStroke()
        node.lineWidth = scaled(64, in: rect)
        node.stroke()
    }

    drawStatusDot(center: point(752, 288, in: rect), radius: scaled(108, in: rect), fill: palette.success, ring: palette.ink, withCheck: true)
    drawStatusDot(center: point(790, 776, in: rect), radius: scaled(38, in: rect), fill: palette.warning, ring: palette.ink, withCheck: false)
}

private func drawStatusDot(center: CGPoint, radius: CGFloat, fill: NSColor, ring: NSColor, withCheck: Bool) {
    let outer = radius * 1.28
    ring.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2)).fill()
    fill.setFill()
    NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()

    guard withCheck else { return }
    let check = NSBezierPath()
    check.move(to: CGPoint(x: center.x - radius * 0.46, y: center.y - radius * 0.02))
    check.line(to: CGPoint(x: center.x - radius * 0.1, y: center.y - radius * 0.38))
    check.line(to: CGPoint(x: center.x + radius * 0.5, y: center.y + radius * 0.36))
    check.lineWidth = radius * 0.27
    check.lineCapStyle = .round
    check.lineJoinStyle = .round
    NSColor.white.setStroke()
    check.stroke()
}

/// Template glyph: three commit nodes joined by a trunk and a merging branch.
private func drawMenuBarGlyph(in rect: CGRect, stroke: NSColor = .black) {
    let unit = min(rect.width, rect.height) / 22
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: rect.minX + x * unit, y: rect.maxY - y * unit)
    }

    stroke.setStroke()

    let lines = NSBezierPath()
    lines.move(to: p(6, 7.2))
    lines.line(to: p(6, 14.8))
    lines.move(to: p(16, 11.2))
    lines.curve(to: p(6, 14.8), controlPoint1: p(16, 14.2), controlPoint2: p(11, 13.7))
    lines.lineWidth = 1.8 * unit
    lines.lineCapStyle = .round
    lines.stroke()

    for center in [p(6, 5), p(6, 17), p(16, 9)] {
        let r = 2.2 * unit
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        ring.lineWidth = 1.8 * unit
        ring.stroke()
    }
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
        drawMenuBarGlyph(
            in: iconFrame,
            stroke: background.brightnessComponent < 0.5 ? color(0xFF, 0xFF, 0xFF) : color(0x14, 0x19, 0x24)
        )
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
