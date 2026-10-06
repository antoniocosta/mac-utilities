// Makes the Adobe Spyware Killer icon: the Creative Cloud icon with a red
// "prohibited" sign in the top-right corner.
// Usage: swift make_icon.swift <source.icns> <output.icns>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let base = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: swift make_icon.swift <source.icns> <output.icns>\n".data(using: .utf8)!)
    exit(1)
}
let out = URL(fileURLWithPath: args[2])
let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("adobe-spyware-killer-\(getpid()).iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px)
    base.draw(in: NSRect(x: 0, y: 0, width: s, height: s))

    // Badge: top-right, about 46% of the icon (bigger at tiny sizes to stay readable).
    let d = s * (px <= 32 ? 0.60 : 0.46)
    let rect = NSRect(x: s - d - s * 0.02, y: s - d - s * 0.02, width: d, height: d)
    let line = d * 0.15

    // White disc with a soft shadow, so the sign reads on any background.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = d * 0.06
    shadow.shadowOffset = NSSize(width: 0, height: -d * 0.02)
    shadow.set()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: rect).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Red ring and diagonal bar (top-left to bottom-right), clipped to the ring.
    let red = NSColor(srgbRed: 0.86, green: 0.08, blue: 0.10, alpha: 1)
    red.setStroke()
    let ringRect = rect.insetBy(dx: line / 2 + d * 0.03, dy: line / 2 + d * 0.03)
    let ring = NSBezierPath(ovalIn: ringRect)
    ring.lineWidth = line
    ring.stroke()
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(ovalIn: ringRect).addClip()
    let r = ringRect.width / 2
    let c = NSPoint(x: ringRect.midX, y: ringRect.midY)
    let k = r / 2.0.squareRoot()
    let bar = NSBezierPath()
    bar.move(to: NSPoint(x: c.x - k, y: c.y + k))
    bar.line(to: NSPoint(x: c.x + k, y: c.y - k))
    bar.lineWidth = line
    bar.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
    try! render(pt * scale).write(to: iconset.appendingPathComponent(name))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", "-o", out.path, iconset.path]
try! p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
exit(p.terminationStatus)
