// Draws AppIcon.iconset (a blue rounded square with the faceid symbol) for iconutil.
// Usage: swift make-icon.swift <output.iconset>
import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let output = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024),
]

for variant in variants {
    let size = CGFloat(variant.pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: variant.pixels, pixelsHigh: variant.pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { exit(1) }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.06
    let plate = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: size * 0.22, yRadius: size * 0.22
    )
    NSGradient(
        starting: NSColor(calibratedRed: 0.24, green: 0.52, blue: 0.98, alpha: 1),
        ending: NSColor(calibratedRed: 0.09, green: 0.25, blue: 0.68, alpha: 1)
    )?.draw(in: plate, angle: -90)

    let configuration = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "faceid", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let drawn = symbol.size
        symbol.draw(in: NSRect(
            x: (size - drawn.width) / 2, y: (size - drawn.height) / 2, width: drawn.width, height: drawn.height
        ))
    }
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
    try data.write(to: output.appendingPathComponent("icon_\(variant.name).png"))
}
