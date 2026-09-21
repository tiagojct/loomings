// Loomings social share card renderer (Open Graph / Twitter Card).
// "Publisher's cloth": the same red field, gilt life-buoy device and
// gilt caps wordmark as docs/index.html, reduced to a single fixed card
// (OG images have no light/dark or system-follow concept).
// Output: 1200x630 PNG.
// Compile: swiftc -O -o render-og render-og.swift
// Usage:   ./render-og output.png vX.Y.Z

import Cocoa

guard CommandLine.arguments.count == 3 else {
    print("usage: render-og output.png vX.Y.Z"); exit(1)
}
let outPath = CommandLine.arguments[1]
let versionArg = CommandLine.arguments[2]

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

let field = color(0x55, 0x17, 0x13)   // aged red cloth, not fresh
let gilt  = color(0xA0, 0x82, 0x46)   // worn gilt, not shiny gold
let giltDim = color(0x6B, 0x57, 0x30)
let cream = color(0xDF, 0xD3, 0xB8)
let creamDim = color(0x9C, 0x8A, 0x6C)

// Field.
field.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()

// Blind-stamping is pressed, not inked — a hairline double rule reads
// closer to that than one bold stroke does, matching docs/style.css.
let margin: CGFloat = 40
let frame = NSRect(x: margin, y: margin, width: width - margin * 2, height: height - margin * 2)
let framePath = NSBezierPath(rect: frame)
framePath.lineWidth = 1
giltDim.setStroke()
framePath.stroke()
let innerMargin: CGFloat = margin + 8
let innerFrame = NSRect(x: innerMargin, y: innerMargin, width: width - innerMargin * 2, height: height - innerMargin * 2)
let innerFramePath = NSBezierPath(rect: innerFrame)
innerFramePath.lineWidth = 1
giltDim.setStroke()
innerFramePath.stroke()

// Life-buoy device — a gilt ring on the field, quartered by two straps,
// exactly as docs/index.html's inline SVG (same construction, drawn here
// with paths instead of markup): outer disc, two field-coloured straps,
// then a field-coloured hole punched through the middle.
let buoyCenter = NSPoint(x: margin + 150, y: height / 2)
let outerR: CGFloat = 92
let innerR: CGFloat = 56
let strapW: CGFloat = 32

func circlePath(center: NSPoint, radius: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    p.appendOval(in: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    return p
}

gilt.setFill()
circlePath(center: buoyCenter, radius: outerR).fill()

field.setFill()
NSRect(x: buoyCenter.x - outerR - 4, y: buoyCenter.y - strapW / 2, width: (outerR + 4) * 2, height: strapW).fill()
NSRect(x: buoyCenter.x - strapW / 2, y: buoyCenter.y - outerR - 4, width: strapW, height: (outerR + 4) * 2).fill()
circlePath(center: buoyCenter, radius: innerR).fill()

// Wordmark — bold gilt caps, the same treatment as the page's <h1>.
let textX = buoyCenter.x + outerR + 56
let titleFont = NSFont(name: "Georgia-Bold", size: 78) ?? NSFontManager.shared.font(withFamily: "Georgia", traits: .boldFontMask, weight: 9, size: 78)!
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: gilt,
    .kern: 3.0,
]
let titleStr = NSAttributedString(string: "LOOMINGS", attributes: titleAttrs)
let titleY = height / 2 + 18
titleStr.draw(at: NSPoint(x: textX, y: titleY))

// Tagline.
let tagFont = NSFont(name: "Georgia-Italic", size: 30) ?? NSFont(name: "Georgia", size: 30)!
let tagAttrs: [NSAttributedString.Key: Any] = [
    .font: tagFont,
    .foregroundColor: creamDim,
]
let tagStr = NSAttributedString(string: "A markdown editor, for writing and teaching.", attributes: tagAttrs)
tagStr.draw(at: NSPoint(x: textX, y: titleY - 52))

// Version — bottom-left, inside the frame.
let verFont = NSFont.monospacedSystemFont(ofSize: 22, weight: .regular)
let verAttrs: [NSAttributedString.Key: Any] = [.font: verFont, .foregroundColor: giltDim, .kern: 1.5]
let verStr = NSAttributedString(string: versionArg, attributes: verAttrs)
verStr.draw(at: NSPoint(x: margin + 32, y: margin + 28))

// Domain — bottom-right.
let urlFont = NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)
let urlAttrs: [NSAttributedString.Key: Any] = [.font: urlFont, .foregroundColor: creamDim, .kern: 1.2]
let urlStr = NSAttributedString(string: "loomings.tiagojacinto.eu", attributes: urlAttrs)
let urlSize = urlStr.size()
urlStr.draw(at: NSPoint(x: width - margin - 32 - urlSize.width, y: margin + 28))

let _ = cgCtx

guard let data = rep.representation(using: .png, properties: [:]) else {
    print("encode failed"); exit(1)
}
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(Int(width))x\(Int(height))")
