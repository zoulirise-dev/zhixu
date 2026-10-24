import AppKit
import Foundation

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
func drawIcon(size: Int) throws -> Data {
    let n = CGFloat(size)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let inset = n * 0.09, side = n * 0.82
    let bounds = NSRect(x: inset, y: inset, width: side, height: side)
    let tile = NSBezierPath(roundedRect: bounds, xRadius: side * 0.23, yRadius: side * 0.23)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.20); shadow.shadowBlurRadius = n * 0.025; shadow.shadowOffset = NSSize(width: 0, height: -n * 0.012); shadow.set()
    NSColor.systemBlue.setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(red: 0.14, green: 0.63, blue: 1, alpha: 1), ending: NSColor(red: 0.01, green: 0.34, blue: 0.88, alpha: 1))!.draw(in: tile, angle: -55)
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: inset + side * x, y: inset + side * (1 - y)) }
    let branch = NSBezierPath(); branch.lineWidth = side * 0.085; branch.lineCapStyle = .round; branch.lineJoinStyle = .round
    branch.move(to: point(0.25, 0.30))
    branch.line(to: point(0.68, 0.26))
    branch.curve(to: point(0.72, 0.32), controlPoint1: point(0.75, 0.25), controlPoint2: point(0.77, 0.28))
    branch.line(to: point(0.28, 0.68))
    branch.curve(to: point(0.32, 0.74), controlPoint1: point(0.23, 0.72), controlPoint2: point(0.25, 0.76))
    branch.line(to: point(0.75, 0.70))
    NSColor.white.setStroke(); branch.stroke(); NSColor.white.setFill()
    let diameter = side * 0.18
    for p in [point(0.25, 0.30), point(0.75, 0.70)] { NSBezierPath(ovalIn: NSRect(x: p.x - diameter / 2, y: p.y - diameter / 2, width: diameter, height: diameter)).fill() }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try drawIcon(size: size).write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(size: size * 2).write(to: URL(fileURLWithPath: destination).appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
