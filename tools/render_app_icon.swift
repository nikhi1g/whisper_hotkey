import AppKit
import Foundation

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func strokedPath(
    color: NSColor,
    width: CGFloat,
    drawing: (NSBezierPath) -> Void
) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    drawing(path)
    color.setStroke()
    path.stroke()
}

guard CommandLine.arguments.count == 2 else {
    fputs("usage: render_app_icon.swift OUTPUT.png\n", stderr)
    exit(64)
}

let size = NSSize(width: 1024, height: 1024)
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(size.width),
    pixelsHigh: Int(size.height),
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    exit(1)
}
bitmap.size = size

NSGraphicsContext.saveGraphicsState()
guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    exit(1)
}
NSGraphicsContext.current = context
context.shouldAntialias = true

NSColor.clear.setFill()
NSRect(origin: .zero, size: size).fill()

let background = NSBezierPath(
    roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928),
    xRadius: 205,
    yRadius: 205
)
NSColor(hex: 0x22272E).setFill()
background.fill()

let microphone = NSBezierPath(
    roundedRect: NSRect(x: 392, y: 332, width: 240, height: 350),
    xRadius: 120,
    yRadius: 120
)
NSColor(hex: 0xADBAC7).setFill()
microphone.fill()

let blue = NSColor(hex: 0x539BF5)
strokedPath(color: blue, width: 54) { path in
    path.move(to: NSPoint(x: 338, y: 524))
    path.curve(
        to: NSPoint(x: 512, y: 264),
        controlPoint1: NSPoint(x: 338, y: 349),
        controlPoint2: NSPoint(x: 420, y: 264)
    )
    path.curve(
        to: NSPoint(x: 686, y: 524),
        controlPoint1: NSPoint(x: 604, y: 264),
        controlPoint2: NSPoint(x: 686, y: 349)
    )
}

strokedPath(color: blue, width: 54) { path in
    path.move(to: NSPoint(x: 512, y: 274))
    path.line(to: NSPoint(x: 512, y: 199))
    path.move(to: NSPoint(x: 420, y: 199))
    path.line(to: NSPoint(x: 604, y: 199))
}

let lavender = NSColor(hex: 0x986EE2)
strokedPath(color: lavender, width: 34) { path in
    path.move(to: NSPoint(x: 292, y: 420))
    path.curve(
        to: NSPoint(x: 292, y: 592),
        controlPoint1: NSPoint(x: 255, y: 468),
        controlPoint2: NSPoint(x: 255, y: 544)
    )
}
strokedPath(color: lavender, width: 34) { path in
    path.move(to: NSPoint(x: 732, y: 420))
    path.curve(
        to: NSPoint(x: 732, y: 592),
        controlPoint1: NSPoint(x: 769, y: 468),
        controlPoint2: NSPoint(x: 769, y: 544)
    )
}

context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(
    using: .png,
    properties: [.compressionFactor: 1]
) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
