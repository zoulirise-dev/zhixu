import AppKit
let width = 660, height = 440
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
bitmap.size = NSSize(width: width, height: height)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: 1, y: 1)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
NSColor(white: 0.17, alpha: 1).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 2.6; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 276, y: 234))
arrow.curve(to: NSPoint(x: 385, y: 234), controlPoint1: NSPoint(x: 315, y: 251), controlPoint2: NSPoint(x: 351, y: 248))
arrow.move(to: NSPoint(x: 371, y: 247)); arrow.line(to: NSPoint(x: 385, y: 234)); arrow.line(to: NSPoint(x: 369, y: 226))
arrow.stroke()
let text = "将枝序拖入 Applications 文件夹" as NSString
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor(white: 0.53, alpha: 1)]
let size = text.size(withAttributes: attributes)
text.draw(at: NSPoint(x: (660 - size.width) / 2, y: 66), withAttributes: attributes)
NSGraphicsContext.restoreGraphicsState()
// Finder backgrounds use pixel coordinates; match the window dimensions exactly.
try bitmap.tiffRepresentation!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
