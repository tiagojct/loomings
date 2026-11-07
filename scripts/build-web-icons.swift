import AppKit
import Foundation

// Writes the web icons: the woven hash in a Tryworks blue gradient on a dark
// ground. Full-bleed squares, because the browser or the phone rounds them. The Mac icon is separate (macos/scripts/build-icon.swift).
// public/icons/favicon.svg and docs/assets/favicon.svg are written by hand.

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // scripts
    .deletingLastPathComponent() // repository

// The hash, woven: two upright and two level bars in a Tryworks blue gradient
// on the dark ground. The same mark as the Mac icon (macos/scripts/build-icon.swift),
// without the glow, so it stays clean at 16 px.
func render(_ side: Int, to path: String) throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(side)
    let full = NSRect(x: 0, y: 0, width: s, height: s)
    NSGradient(colors: [
        NSColor(srgbRed: 0x1E / 255, green: 0x2A / 255, blue: 0x34 / 255, alpha: 1),
        NSColor(srgbRed: 0x0B / 255, green: 0x0F / 255, blue: 0x13 / 255, alpha: 1),
    ])!.draw(in: full, angle: -90)

    // Inside the 80% safe zone of a maskable icon.
    let k = s * 0.29 / 250
    let half = 250 * k, gap = 108 * k, width = 86 * k, halo = 9 * k
    let c = NSPoint(x: s / 2, y: s / 2)
    func bar(vertical: Bool, at offset: CGFloat) -> NSRect {
        vertical
            ? NSRect(x: c.x + offset - width / 2, y: c.y - half, width: width, height: half * 2)
            : NSRect(x: c.x - half, y: c.y + offset - width / 2, width: half * 2, height: width)
    }
    func rounded(_ r: NSRect) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: width * 0.22, yRadius: width * 0.22) }
    let box = NSRect(x: c.x - half, y: c.y - half, width: half * 2, height: half * 2)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0xE4 / 255, green: 0xF0 / 255, blue: 0xFA / 255, alpha: 1),
        NSColor(srgbRed: 0x86 / 255, green: 0xB4 / 255, blue: 0xDA / 255, alpha: 1),
        NSColor(srgbRed: 0x2C / 255, green: 0x5D / 255, blue: 0x87 / 255, alpha: 1),
    ], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    func lit(_ path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        gradient.draw(in: box, angle: -55)
        NSGraphicsContext.restoreGraphicsState()
    }
    let uprights = [-gap, gap].map { bar(vertical: true, at: $0) }
    let levels = [gap, -gap].map { bar(vertical: false, at: $0) }
    for r in uprights + levels { lit(rounded(r)) }
    let seam = NSColor(srgbRed: 0x15 / 255, green: 0x1E / 255, blue: 0x27 / 255, alpha: 1)
    for (u, l, levelOver) in [(0, 0, true), (1, 0, false), (0, 1, false), (1, 1, true)] {
        let under = levelOver ? uprights[u] : levels[l]
        let over = levelOver ? levels[l] : uprights[u]
        let piece = levelOver
            ? NSRect(x: under.minX - halo, y: over.minY, width: under.width + halo * 2, height: over.height)
            : NSRect(x: over.minX, y: under.minY - halo, width: over.width, height: under.height + halo * 2)
        NSGraphicsContext.saveGraphicsState()
        rounded(under).addClip()
        seam.setFill()
        NSBezierPath(rect: levelOver ? piece.insetBy(dx: 0, dy: -halo) : piece.insetBy(dx: -halo, dy: 0)).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: piece).addClip()
        lit(rounded(over))
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: root.appendingPathComponent(path))
}

try render(192, to: "public/icons/icon-192.png")
try render(512, to: "public/icons/icon-512.png")
try render(1024, to: "docs/assets/icon.png")
print("web icons written")
