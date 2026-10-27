import AppKit

// Original vector artwork rendered at standard macOS icon sizes.
let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    NSColor(srgbRed: 0.12, green: 0.17, blue: 0.25, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 205, yRadius: 205).fill()
    NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 215, y: 245, width: 594, height: 534), xRadius: 56, yRadius: 56).fill()
    NSColor(srgbRed: 0.87, green: 0.89, blue: 0.93, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 215, y: 666, width: 594, height: 113), xRadius: 56, yRadius: 56).fill()
    NSColor(srgbRed: 0.98, green: 0.27, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 267, y: 699, width: 48, height: 48)).fill()
    NSColor(srgbRed: 0.12, green: 0.17, blue: 0.25, alpha: 1).setStroke()
    let cross = NSBezierPath()
    cross.lineWidth = 55
    cross.lineCapStyle = .round
    cross.move(to: NSPoint(x: 424, y: 390))
    cross.line(to: NSPoint(x: 600, y: 566))
    cross.move(to: NSPoint(x: 424, y: 566))
    cross.line(to: NSPoint(x: 600, y: 390))
    cross.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    if [16, 32, 128, 256, 512].contains(size) {
        try png.write(to: destination.appendingPathComponent("icon_\(size)x\(size).png"))
    }
    if [32, 64, 256, 512, 1024].contains(size) {
        try png.write(to: destination.appendingPathComponent("icon_\(size / 2)x\(size / 2)@2x.png"))
    }
}
