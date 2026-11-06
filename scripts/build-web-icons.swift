import AppKit
import Foundation

// Writes the web icons in the Tryworks style: the pale sheet and the Loomings
// L in Tryworks blue. Full-bleed squares, because the browser or the phone
// rounds them. The Mac icon is separate (macos/scripts/build-icon.swift).
// public/icons/favicon.svg and docs/assets/favicon.svg are written by hand.

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // scripts
    .deletingLastPathComponent() // repository
let lURL = root.appendingPathComponent("icons/loomings.icon/Assets/loomings-L.svg")
guard var source = try? String(contentsOf: lURL, encoding: .utf8) else { fatalError("Missing \(lURL.path)") }
source = source.replacingOccurrences(of: "#F7F3EE", with: "#2C5D87")
guard let mark = NSImage(data: Data(source.utf8)) else { fatalError("Unreadable mark") }

let sheet = NSColor(srgbRed: 0xE9 / 255, green: 0xEC / 255, blue: 0xE6 / 255, alpha: 1) // --bg

func render(_ side: Int, to path: String) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    sheet.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    // The L is 41% of the height: inside the 80% safe zone of a maskable icon.
    // Drawn 1.15 times larger than its file so it reads at 16 px.
    let box = CGFloat(side) * 1.15
    mark.draw(in: NSRect(x: (CGFloat(side) - box) / 2, y: (CGFloat(side) - box) / 2, width: box, height: box),
              from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: root.appendingPathComponent(path))
}

try render(192, to: "public/icons/icon-192.png")
try render(512, to: "public/icons/icon-512.png")
try render(1024, to: "docs/assets/icon.png")
print("web icons written")
