import AppKit
import Foundation

struct Color {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    let alpha: CGFloat

    var nsColor: NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private let iconSizes: [(String, Int)] = [
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

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render-app-icon.swift ICONSET_DIR\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for (filename, size) in iconSizes {
    let image = renderIcon(size: size)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fputs("error: could not render \(filename)\n", stderr)
        exit(1)
    }

    try pngData.write(to: outputURL.appendingPathComponent(filename))
}

private func renderIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer {
        image.unlockFocus()
    }

    let scale = CGFloat(size) / 1024
    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
    func radius(_ value: CGFloat) -> CGFloat {
        value * scale
    }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    let background = NSBezierPath(
        roundedRect: rect(64, 64, 896, 896),
        xRadius: radius(214),
        yRadius: radius(214)
    )
    let backgroundGradient = NSGradient(colors: [
        Color(red: 0.08, green: 0.18, blue: 0.26, alpha: 1).nsColor,
        Color(red: 0.08, green: 0.45, blue: 0.55, alpha: 1).nsColor,
        Color(red: 0.12, green: 0.62, blue: 0.50, alpha: 1).nsColor
    ])
    backgroundGradient?.draw(in: background, angle: -35)

    drawPulseRings(scale: scale)
    drawMonitor(scale: scale)
    drawWaveform(scale: scale)
    drawCursor(scale: scale)

    return image
}

private func drawPulseRings(scale: CGFloat) {
    let ringColor = Color(red: 0.80, green: 1.00, blue: 0.93, alpha: 0.20).nsColor
    ringColor.setStroke()

    for (index, rectValue) in [
        NSRect(x: 144, y: 132, width: 736, height: 736),
        NSRect(x: 204, y: 192, width: 616, height: 616)
    ].enumerated() {
        let path = NSBezierPath(ovalIn: scaled(rectValue, scale))
        path.lineWidth = CGFloat(index == 0 ? 28 : 20) * scale
        path.stroke()
    }
}

private func drawMonitor(scale: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = 28 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -18 * scale)
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.28)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    let screenOuter = NSBezierPath(
        roundedRect: scaled(NSRect(x: 168, y: 292, width: 688, height: 448), scale),
        xRadius: 68 * scale,
        yRadius: 68 * scale
    )
    Color(red: 0.91, green: 0.98, blue: 1.00, alpha: 1).nsColor.setFill()
    screenOuter.fill()
    NSGraphicsContext.restoreGraphicsState()

    let screenInner = NSBezierPath(
        roundedRect: scaled(NSRect(x: 214, y: 340, width: 596, height: 352), scale),
        xRadius: 40 * scale,
        yRadius: 40 * scale
    )
    Color(red: 0.04, green: 0.13, blue: 0.19, alpha: 1).nsColor.setFill()
    screenInner.fill()

    let stand = NSBezierPath(roundedRect: scaled(NSRect(x: 456, y: 210, width: 112, height: 104), scale), xRadius: 28 * scale, yRadius: 28 * scale)
    Color(red: 0.89, green: 0.97, blue: 0.99, alpha: 1).nsColor.setFill()
    stand.fill()

    let base = NSBezierPath(roundedRect: scaled(NSRect(x: 346, y: 176, width: 332, height: 70), scale), xRadius: 35 * scale, yRadius: 35 * scale)
    Color(red: 0.89, green: 0.97, blue: 0.99, alpha: 1).nsColor.setFill()
    base.fill()
}

private func drawWaveform(scale: CGFloat) {
    let glow = NSBezierPath()
    waveformPoints(scale: scale).enumerated().forEach { index, point in
        if index == 0 {
            glow.move(to: point)
        } else {
            glow.line(to: point)
        }
    }
    glow.lineCapStyle = .round
    glow.lineJoinStyle = .round
    glow.lineWidth = 58 * scale
    Color(red: 0.16, green: 0.95, blue: 0.83, alpha: 0.20).nsColor.setStroke()
    glow.stroke()

    let wave = NSBezierPath()
    waveformPoints(scale: scale).enumerated().forEach { index, point in
        if index == 0 {
            wave.move(to: point)
        } else {
            wave.line(to: point)
        }
    }
    wave.lineCapStyle = .round
    wave.lineJoinStyle = .round
    wave.lineWidth = 34 * scale
    Color(red: 0.25, green: 1.00, blue: 0.86, alpha: 1).nsColor.setStroke()
    wave.stroke()
}

private func drawCursor(scale: CGFloat) {
    let cursor = NSBezierPath()
    cursor.move(to: scaled(NSPoint(x: 690, y: 450), scale))
    cursor.line(to: scaled(NSPoint(x: 792, y: 396), scale))
    cursor.line(to: scaled(NSPoint(x: 710, y: 360), scale))
    cursor.line(to: scaled(NSPoint(x: 690, y: 450), scale))
    cursor.close()

    Color(red: 1.00, green: 1.00, blue: 1.00, alpha: 1).nsColor.setFill()
    cursor.fill()
    Color(red: 0.04, green: 0.13, blue: 0.19, alpha: 1).nsColor.setStroke()
    cursor.lineWidth = 14 * scale
    cursor.stroke()
}

private func waveformPoints(scale: CGFloat) -> [NSPoint] {
    [
        NSPoint(x: 288, y: 516),
        NSPoint(x: 358, y: 516),
        NSPoint(x: 394, y: 604),
        NSPoint(x: 448, y: 420),
        NSPoint(x: 504, y: 596),
        NSPoint(x: 558, y: 462),
        NSPoint(x: 612, y: 516),
        NSPoint(x: 684, y: 516)
    ].map { scaled($0, scale) }
}

private func scaled(_ rect: NSRect, _ scale: CGFloat) -> NSRect {
    NSRect(
        x: rect.origin.x * scale,
        y: rect.origin.y * scale,
        width: rect.width * scale,
        height: rect.height * scale
    )
}

private func scaled(_ point: NSPoint, _ scale: CGFloat) -> NSPoint {
    NSPoint(x: point.x * scale, y: point.y * scale)
}
