// Loomings social share card renderer (Open Graph / Twitter Card).
// Output: 1200x630 PNG.
// Compile: swiftc -O -o render-og render-og.swift
// Usage:   ./render-og output.png icon.png

import Cocoa
import CoreText

guard CommandLine.arguments.count == 3 else {
    print("usage: render-og output.png icon.png"); exit(1)
}
let outPath  = CommandLine.arguments[1]
let iconPath = CommandLine.arguments[2]

let width:  CGFloat = 1200
let height: CGFloat = 630

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: Int(width), pixelsHigh: Int(height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
let cgCtx = ctx.cgContext

func color(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// Background — dark parchment radial bloom.
let bgGrad = NSGradient(colorsAndLocations:
    (color(0x14, 0x3F, 0x58), 0.0),
    (color(0x0B, 0x1F, 0x2D), 0.55),
    (color(0x04, 0x12, 0x1C), 1.0)
)!
bgGrad.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
            relativeCenterPosition: NSPoint(x: -0.2, y: 0.4))

// Subtle amber glow lower-right.
let glow = NSGradient(colorsAndLocations:
    (color(0xD4, 0xA8, 0x82, 0.20), 0.0),
    (color(0xD4, 0xA8, 0x82, 0.0),  1.0)
)!
glow.draw(in: NSRect(x: width*0.55, y: -height*0.4, width: width*0.6, height: height*1.2),
          relativeCenterPosition: NSPoint(x: 0, y: 0))

// Left margin layout.
let margin: CGFloat = 88
let iconSize: CGFloat = 200

// Icon (drop shadow + image).
if let icon = NSImage(contentsOfFile: iconPath) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.shadowBlurRadius = 32
    shadow.set()
    let iconRect = NSRect(x: margin,
                          y: height - margin - iconSize,
                          width: iconSize, height: iconSize)
    icon.draw(in: iconRect,
              from: .zero, operation: .sourceOver, fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()
}

// Title — "Loomings" in italic serif.
let titleX = margin + iconSize + 48
let titleY = height - margin - 56

let titleFont =
    NSFont(name: "SourceSerif4-It", size: 120) ??
    NSFont(name: "HoeflerText-Italic", size: 120) ??
    NSFont(name: "Didot-Italic", size: 120) ??
    NSFontManager.shared.font(withFamily: "Georgia", traits: .italicFontMask, weight: 5, size: 120)!

let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: color(0xED, 0xE3, 0xCC),
]
let titleStr = NSAttributedString(string: "Loomings", attributes: titleAttrs)
let titleSize = titleStr.size()
titleStr.draw(at: NSPoint(x: titleX, y: titleY - titleSize.height))

// Tagline — "A markdown writing app." in regular serif.
let tagY = titleY - titleSize.height - 28
let tagFont =
    NSFont(name: "SourceSerif4-Regular", size: 38) ??
    NSFont(name: "HoeflerText-Regular", size: 38) ??
    NSFont(name: "Georgia", size: 38)!

let tagAttrs: [NSAttributedString.Key: Any] = [
    .font: tagFont,
    .foregroundColor: color(0xBD, 0xB2, 0x9B),
]
let tagStr = NSAttributedString(string: "A markdown writing app.", attributes: tagAttrs)
let tagSize = tagStr.size()
tagStr.draw(at: NSPoint(x: titleX, y: tagY - tagSize.height))

// Version pill — bottom-left.
let verFont =
    NSFont(name: "JetBrainsMono-Regular", size: 22) ??
    NSFont(name: "SFMono-Regular", size: 22) ??
    NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)

let verAttrs: [NSAttributedString.Key: Any] = [
    .font: verFont,
    .foregroundColor: color(0xD4, 0xA8, 0x82),
    .kern: 1.5,
]
let verStr = NSAttributedString(string: "v1.0.0", attributes: verAttrs)
verStr.draw(at: NSPoint(x: margin, y: margin))

// Tag URL — bottom-right.
let urlFont =
    NSFont(name: "JetBrainsMono-Regular", size: 20) ??
    NSFont(name: "SFMono-Regular", size: 20) ??
    NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)

let urlAttrs: [NSAttributedString.Key: Any] = [
    .font: urlFont,
    .foregroundColor: color(0x7E, 0x76, 0x60),
    .kern: 1.2,
]
let urlStr = NSAttributedString(string: "tiagojct.eu/loomings", attributes: urlAttrs)
let urlSize = urlStr.size()
urlStr.draw(at: NSPoint(x: width - margin - urlSize.width, y: margin))

// Thin amber rule above tag URL.
let rulePath = NSBezierPath()
rulePath.move(to: NSPoint(x: width - margin - 200, y: margin + urlSize.height + 16))
rulePath.line(to: NSPoint(x: width - margin,       y: margin + urlSize.height + 16))
color(0xD4, 0xA8, 0x82, 0.35).setStroke()
rulePath.lineWidth = 1
rulePath.stroke()

let _ = cgCtx

guard let data = rep.representation(using: .png, properties: [:]) else {
    print("encode failed"); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(Int(width))x\(Int(height))")
