import CoreImage
import Foundation
import Testing
@testable import LoomingsShare

@Suite("Share QR code")
struct ShareQRCodeTests {
    @Test("A short share link becomes a square QR code that decodes back to the link")
    func qrEncodesShortLink() throws {
        let url = try ShareLink.url(for: "# Hello\n\nA short note.\n", family: "pequod", mode: "light")
        let image = try #require(ShareQRCode.image(for: url, side: 240))
        #expect(image.width == image.height)
        #expect(image.width >= 240)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
        let found = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(found == [url.absoluteString])
    }

    @Test("A link over the QR limit is refused, not truncated")
    func qrRefusesLongLinks() throws {
        let long = try #require(URL(string: "https://loomings.tiagojacinto.eu/app/#d=p." + String(repeating: "a", count: 3_000)))
        #expect(ShareQRCode.image(for: long, side: 240) == nil)
        #expect(!ShareQRCode.fits(long))
        #expect(ShareQRCode.maximumBytes == 2_900)
    }

    @Test("The printed size gives every module at least 1.5 points")
    func printSideScalesWithDensity() throws {
        let short = try ShareLink.url(for: "Hi\n", family: nil, mode: nil)
        let dense = try #require(URL(string: "https://loomings.tiagojacinto.eu/app/#d=p." + String(repeating: "x", count: 2_700)))
        let shortSide = try #require(ShareQRCode.printSide(for: short))
        let denseSide = try #require(ShareQRCode.printSide(for: dense))
        let modules = try #require(ShareQRCode.moduleCount(for: dense))
        #expect(shortSide >= 72)
        #expect(denseSide >= CGFloat(modules) * 1.5)
        #expect(denseSide <= 300)
        #expect(ShareQRCode.printSide(for: URL(string: "https://x.example/" + String(repeating: "y", count: 3_000))!) == nil)
    }

    struct WebMatrix: Decodable {
        let name: String
        let text: String
        let rows: [String]
    }

    /// Draws a matrix black on white, with a four-module quiet zone.
    static func render(_ rows: [String], scale: Int) -> CGImage? {
        let size = rows.count + 8
        let side = size * scale
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        for (y, row) in rows.enumerated() {
            for (x, cell) in row.enumerated() where cell == "1" {
                // CoreGraphics counts rows from the bottom.
                context.fill(CGRect(x: (x + 4) * scale, y: (size - 1 - (y + 4)) * scale, width: scale, height: scale))
            }
        }
        return context.makeImage()
    }

    @Test("Every QR code the web encoder draws decodes back to its text")
    func webMatricesDecode() throws {
        let url = try #require(Bundle.module.url(forResource: "qr-matrices", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([WebMatrix].self, from: Data(contentsOf: url))
        #expect(cases.count >= 8)
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for item in cases {
            #expect(item.rows.allSatisfy { $0.count == item.rows.count }, "\(item.name): square")
            let image = try #require(Self.render(item.rows, scale: 6), "\(item.name)")
            let found = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            #expect(found == [item.text], "\(item.name)")
        }
    }
}
