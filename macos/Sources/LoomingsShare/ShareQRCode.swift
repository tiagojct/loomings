import CoreImage
import Foundation

/// A share link as a QR code, for handouts and the screen. A QR code holds
/// about 2,950 bytes at the lowest error correction; links above
/// `maximumBytes` are refused rather than cut short.
public enum ShareQRCode {
    public static let maximumBytes = 2_900

    public static func fits(_ url: URL) -> Bool {
        url.absoluteString.utf8.count <= maximumBytes
    }

    /// Modules per side, quiet zone included, or nil when the link is too long.
    public static func moduleCount(for url: URL) -> Int? {
        code(for: url).map { Int($0.extent.width) }
    }

    /// The side to print at: at least 1.6 points per module so a phone can
    /// read it from paper, never below 72 or above 300 points.
    public static func printSide(for url: URL) -> CGFloat? {
        guard let modules = moduleCount(for: url) else { return nil }
        return min(300, max(72, CGFloat(modules) * 1.6))
    }

    private static func code(for url: URL) -> CIImage? {
        guard fits(url), let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(url.absoluteString.utf8), forKey: "inputMessage")
        filter.setValue("L", forKey: "inputCorrectionLevel")
        return filter.outputImage
    }

    /// A crisp, square image at least `side` points wide, or nil when the
    /// link is too long.
    public static func image(for url: URL, side: CGFloat) -> CGImage? {
        guard let code = code(for: url) else { return nil }
        let scale = max(1, (side / code.extent.width).rounded(.up))
        let scaled = code.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext(options: [.useSoftwareRenderer: false]).createCGImage(scaled, from: scaled.extent)
    }
}
