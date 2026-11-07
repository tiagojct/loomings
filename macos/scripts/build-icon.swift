import AppKit
import Foundation

// Rebuild the native app icon in the Tryworks style: a padded squircle
// (about 81% optical size, the size of other macOS icons): a dark ground lit
// from above, a fine light edge and a woven Markdown hash in a Tryworks blue
// gradient with a soft glow.
// The web and social icons are separate assets and are not touched.

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // scripts
    .deletingLastPathComponent() // macos
    .deletingLastPathComponent() // repository
let masterURL = root.appendingPathComponent("icons/native/icon_1024.png")
let resourceIcon = root.appendingPathComponent("macos/Resources/AppIcon.icns")
let referenceURL = root.appendingPathComponent("macos/Resources/AppIcon-1024.png")

let canvas: CGFloat = 1024
let opticalScale: CGFloat = 0.81
let contentSide = canvas * opticalScale
let contentRect = NSRect(
    x: (canvas - contentSide) / 2,
    y: (canvas - contentSide) / 2,
    width: contentSide,
    height: contentSide
)

// Tryworks tokens (vendor/tryworks-design/css/tokens.css).
let sheet = NSColor(srgbRed: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF1 / 255, alpha: 1) // --raised
let blue = NSColor(srgbRed: 0x2C / 255, green: 0x5D / 255, blue: 0x87 / 255, alpha: 1) // --accent
let edge = NSColor(srgbRed: 0x1B / 255, green: 0x3F / 255, blue: 0x5F / 255, alpha: 1) // the blue, deeper

func signedPow(_ value: CGFloat, _ exponent: CGFloat) -> CGFloat {
    let magnitude = pow(abs(value), exponent)
    return value < 0 ? -magnitude : magnitude
}

func squircle(in rect: NSRect, exponent: CGFloat = 4.6) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 1440
    for index in 0...steps {
        let t = CGFloat(index) / CGFloat(steps) * 2 * .pi
        let cosine = cos(t)
        let sine = sin(t)
        let point = NSPoint(
            x: rect.midX + rect.width / 2 * signedPow(cosine, 2 / exponent),
            y: rect.midY + rect.height / 2 * signedPow(sine, 2 / exponent)
        )
        if index == 0 {
            path.move(to: point)
        } else {
            path.line(to: point)
        }
    }
    path.close()
    return path
}

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bitmapFormat: [],
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.setShouldAntialias(true)

    let scale = size / canvas
    let rect = NSRect(
        x: contentRect.origin.x * scale,
        y: contentRect.origin.y * scale,
        width: contentRect.width * scale,
        height: contentRect.height * scale
    )

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()


    // A dark ground, lit from above, so the lit L stands out (the way a
    // glossy dark icon does). Tryworks night: --term-bg and --bg.
    let ground = squircle(in: rect)
    NSGradient(colors: [
        NSColor(srgbRed: 0x1E / 255, green: 0x2A / 255, blue: 0x34 / 255, alpha: 1),
        NSColor(srgbRed: 0x0B / 255, green: 0x0F / 255, blue: 0x13 / 255, alpha: 1),
    ])!.draw(in: ground, angle: -90)

    // A fine light edge, drawn inside the bounds, so the squircle holds its
    // shape on a dark Dock too.
    let outline = squircle(in: rect.insetBy(dx: 1.5 * scale, dy: 1.5 * scale))
    outline.lineWidth = 3 * scale
    NSColor.white.withAlphaComponent(0.12).setStroke()
    outline.stroke()

    // The mark: a Markdown hash woven like cloth on a loom. Two upright and
    // two level bars, each passing over one bar and under the next, in a
    // Tryworks blue gradient (light at the top left) with a soft glow.
    let centre = NSPoint(x: rect.midX, y: rect.midY)
    let half: CGFloat = 250 * scale      // half the length of a bar
    let gap: CGFloat = 108 * scale       // bar axis to centre
    let width: CGFloat = 86 * scale      // bar thickness
    let halo: CGFloat = 9 * scale        // the dark seam where one bar crosses another

    func bar(vertical: Bool, at offset: CGFloat) -> NSRect {
        vertical
            ? NSRect(x: centre.x + offset - width / 2, y: centre.y - half, width: width, height: half * 2)
            : NSRect(x: centre.x - half, y: centre.y + offset - width / 2, width: half * 2, height: width)
    }
    func rounded(_ r: NSRect) -> NSBezierPath {
        NSBezierPath(roundedRect: r, xRadius: width * 0.22, yRadius: width * 0.22)
    }
    let box = NSRect(x: centre.x - half, y: centre.y - half, width: half * 2, height: half * 2)
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0xE4 / 255, green: 0xF0 / 255, blue: 0xFA / 255, alpha: 1), // light, top left
        NSColor(srgbRed: 0x86 / 255, green: 0xB4 / 255, blue: 0xDA / 255, alpha: 1), // --term-acc
        NSColor(srgbRed: 0x2C / 255, green: 0x5D / 255, blue: 0x87 / 255, alpha: 1), // --accent
    ], atLocations: [0, 0.45, 1], colorSpace: .sRGB)!
    func lit(_ path: NSBezierPath) {
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        gradient.draw(in: box, angle: -55)
        NSGraphicsContext.restoreGraphicsState()
    }

    let uprights = [-gap, gap].map { bar(vertical: true, at: $0) }
    let levels = [gap, -gap].map { bar(vertical: false, at: $0) } // top, bottom

    // The glow: the whole hash in blue, with a shadow.
    context.cgContext.saveGState()
    context.cgContext.setShadow(
        offset: CGSize(width: 0, height: -10 * scale),
        blur: 44 * scale,
        color: blue.withAlphaComponent(0.75).cgColor
    )
    blue.setFill()
    for r in uprights + levels { rounded(r).fill() }
    context.cgContext.restoreGState()

    for r in uprights + levels { lit(rounded(r)) }

    // The weave: at each crossing the "over" bar is drawn again across the
    // other, with a seam of the ground colour cut into the bar below it.
    let seam = NSColor(srgbRed: 0x10 / 255, green: 0x17 / 255, blue: 0x1D / 255, alpha: 1)
    // (upright index, level index, level is over)
    let crossings: [(Int, Int, Bool)] = [(0, 0, true), (1, 0, false), (0, 1, false), (1, 1, true)]
    for (u, l, levelOver) in crossings {
        let under = levelOver ? uprights[u] : levels[l]
        let over = levelOver ? levels[l] : uprights[u]
        let crossing = under.intersection(over)
        // The over bar's piece across the under bar, a little longer each side.
        let piece = levelOver
            ? NSRect(x: under.minX - halo, y: over.minY, width: under.width + halo * 2, height: over.height)
            : NSRect(x: over.minX, y: under.minY - halo, width: over.width, height: under.height + halo * 2)
        _ = crossing
        NSGraphicsContext.saveGraphicsState()
        rounded(under).addClip()
        seam.setFill()
        let seamRect = levelOver
            ? piece.insetBy(dx: 0, dy: -halo)
            : piece.insetBy(dx: -halo, dy: 0)
        NSBezierPath(rect: seamRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: piece).addClip()
        lit(rounded(over))
        NSGraphicsContext.restoreGraphicsState()
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

let master = drawIcon(size: canvas)
try FileManager.default.createDirectory(
    at: masterURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try master.representation(using: .png, properties: [:])!.write(to: masterURL)
try FileManager.default.createDirectory(
    at: referenceURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try master.representation(using: .png, properties: [:])!.write(to: referenceURL)

// Optical bounds must match the Dock sizing of other macOS icons.
var minX = 1024, maxX = 0, minY = 1024, maxY = 0
for y in 0..<1024 {
    for x in 0..<1024 where (master.colorAt(x: x, y: y)?.alphaComponent ?? 0) >= 0.5 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
let width = maxX - minX + 1
let height = maxY - minY + 1
precondition((800...850).contains(width), "Optical width \(width) outside 800...850")
precondition((800...850).contains(height), "Optical height \(height) outside 800...850")
precondition(abs(minX - (1023 - maxX)) <= 3, "Icon must be centred horizontally")
precondition(abs(minY - (1023 - maxY)) <= 3, "Icon must be centred vertically")

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("Loomings-\(UUID().uuidString).iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = CGFloat(points * scale)
        let bitmap = drawIcon(size: size)
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}

try FileManager.default.createDirectory(
    at: resourceIcon.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resourceIcon.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
try? FileManager.default.removeItem(at: iconset)

print("icon: \(width)×\(height) optical, centred; wrote \(resourceIcon.path)")
