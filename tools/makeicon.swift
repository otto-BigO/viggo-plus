import AppKit

// Renders the Viggo+ icon: blue squircle, white graduation cap, small "+" badge.
func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.01)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [NSColor(calibratedRed: 0.32, green: 0.56, blue: 1.0, alpha: 1),
                        NSColor(calibratedRed: 0.28, green: 0.25, blue: 0.86, alpha: 1)])!
        .draw(in: path, angle: -90)

    let cfg = NSImage.SymbolConfiguration(pointSize: rect.width * 0.46, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let cap = NSImage(systemSymbolName: "graduationcap.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let sz = cap.size
        cap.draw(in: NSRect(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2 - rect.height * 0.03,
                            width: sz.width, height: sz.height))
    }
    // "+" badge
    let b = rect.width * 0.26
    let bRect = NSRect(x: rect.maxX - b * 1.22, y: rect.maxY - b * 1.22, width: b, height: b)
    NSColor.white.setFill(); NSBezierPath(ovalIn: bRect).fill()
    let plusCfg = NSImage.SymbolConfiguration(pointSize: b * 0.62, weight: .black)
        .applying(.init(paletteColors: [NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.95, alpha: 1)]))
    if let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)?.withSymbolConfiguration(plusCfg) {
        let ps = plus.size
        plus.draw(in: NSRect(x: bRect.midX - ps.width / 2, y: bRect.midY - ps.height / 2, width: ps.width, height: ps.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
