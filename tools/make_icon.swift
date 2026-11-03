import AppKit

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    // macOS ikon şablonu: kenarlarda boşluk bırakan yuvarlak kare
    let inset = s * 0.098
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    let grad = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.85, blue: 0.75, alpha: 1),
        NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.98, alpha: 1)
    ])!
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.set()
    NSColor.black.setFill(); path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    grad.draw(in: path, angle: -60)

    // Parıltı sembolü
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .bold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let w = sym.size.width, h = sym.size.height
        sym.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (name, px) in [("16x16",16),("16x16@2x",32),("32x32",32),("32x32@2x",64),("128x128",128),("128x128@2x",256),
                   ("256x256",256),("256x256@2x",512),("512x512",512),("512x512@2x",1024)] {
    try! render(size: px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
