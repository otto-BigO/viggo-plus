import AppKit

// docs/banner.png: icon + "Viggo+" + tagline on a Viggo-blue background.
let w = 1600, h = 500
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let r = NSRect(x: 0, y: 0, width: w, height: h)
NSGradient(colors: [NSColor(srgbRed: 0x30/255, green: 0x6A/255, blue: 0xBD/255, alpha: 1),
                    NSColor(srgbRed: 0x1F/255, green: 0x4E/255, blue: 0x96/255, alpha: 1)])!
    .draw(in: NSBezierPath(roundedRect: r, xRadius: 40, yRadius: 40), angle: -90)
if let icon = NSImage(contentsOfFile: CommandLine.arguments[1]) {
    icon.draw(in: NSRect(x: 110, y: 70, width: 360, height: 360))
}
let title = NSAttributedString(string: "Viggo+", attributes: [
    .font: NSFont.systemFont(ofSize: 150, weight: .heavy), .foregroundColor: NSColor.white])
title.draw(at: NSPoint(x: 520, y: 225))
let sub = NSAttributedString(string: "Your Viggo schedule in the macOS menu bar", attributes: [
    .font: NSFont.systemFont(ofSize: 44, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.85)])
sub.draw(at: NSPoint(x: 528, y: 150))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
