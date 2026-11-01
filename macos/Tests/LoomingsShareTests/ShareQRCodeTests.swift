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
}
