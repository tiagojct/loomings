import AppKit
import Foundation

// Rebuild the native app icon in the Adamastor style: a padded squircle
// (about 81% optical size), a thin cream keyline, and the flat Loomings L.
// The web and social icons are separate assets and are not touched.

let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // scripts
    .deletingLastPathComponent() // macos
    .deletingLastPathComponent() // repository
let lURL = root.appendingPathComponent("icons/loomings.icon/Assets/loomings-L.svg")
let masterURL = root.appendingPathComponent("icons/native/icon_1024.png")
let resourceIcon = root.appendingPathComponent("macos/Resources/AppIcon.icns")
let referenceURL = root.appendingPathComponent("macos/Resources/AppIcon-1024.png")

guard let lMark = NSImage(contentsOf: lURL) else {
    fatalError("Missing Loomings mark: \(lURL.path)")
}

let canvas: CGFloat = 1024
let opticalScale: CGFloat = 0.81
let contentSide = canvas * opticalScale
let contentRect = NSRect(
    x: (canvas - contentSide) / 2,
    y: (canvas - contentSide) / 2,
    width: contentSide,
    height: contentSide
)

let navy = NSColor(srgbRed: 13 / 255, green: 47 / 255, blue: 66 / 255, alpha: 1)
let cream = NSColor(srgbRed: 247 / 255, green: 243 / 255, blue: 238 / 255, alpha: 1)

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

    navy.setFill()
    squircle(in: rect).fill()

    // A thin cream keyline, inset from the squircle edge, as on Adamastor.
    let keylineInset = 14 * scale
    let keylineRect = rect.insetBy(dx: keylineInset, dy: keylineInset)
    let keyline = squircle(in: keylineRect)
    keyline.lineWidth = 2.2 * scale
    cream.withAlphaComponent(0.55).setStroke()
    keyline.stroke()

    // The L mark is flat cream, scaled with the optical content.
    lMark.draw(
        in: rect,
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

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

// Optical bounds must match Adamastor's Dock sizing.
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
