// Add transparent padding around icon — match macOS's actual squircle content
// ratio (0.805, i.e. ~824/1024; measured identically across System Settings,
// Notes, Mail, and Safari's own .icns — their icons additionally carry a
// soft drop-shadow that bleeds a few more px, which our flat-edged source
// doesn't have, so the shadow-inclusive bbox isn't the right target).
// Usage: ./pad-icon input.png output.png size scale
import Cocoa
guard CommandLine.arguments.count == 5 else { exit(1) }
let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let size = CGFloat(Int(CommandLine.arguments[3]) ?? 1024)
let scale = CGFloat(Double(CommandLine.arguments[4]) ?? 0.805)

guard let img = NSImage(contentsOfFile: inPath) else { exit(1) }
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0
)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
ctx.imageInterpolation = .high
let inner = size * scale
let offset = (size - inner) / 2
img.draw(in: NSRect(x: offset, y: offset, width: inner, height: inner),
         from: .zero, operation: .copy, fraction: 1.0)
let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) inner=\(Int(inner)) scale=\(scale)")
