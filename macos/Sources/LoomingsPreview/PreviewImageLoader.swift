import AppKit
import Foundation
import ImageIO

public enum PreviewImageResult {
    case image(NSImage)
    /// A remote (or otherwise non-local) source. Never fetched.
    case blocked
    case missing
}

/// Loads images for the native preview.
///
/// The web app's CSP is `img-src 'self' data:`, so a document can never make
/// the browser call out. The native preview keeps the same promise: only
/// `data:` URIs and local files are read. A remote URL in a document (or in a
/// shared link) would otherwise leak the reader's IP address the moment the
/// preview opened. Files and data URIs are size-capped and decoded through
/// ImageIO at preview width, so a huge image cannot take the app's memory.
public enum PreviewImageLoader {
    public static let maximumFileBytes = 25 * 1_048_576
    public static let maximumDataBytes = 8 * 1_048_576
    /// Twice the preview's 620 pt column, for Retina.
    public static let maximumPixels = 1240

    public static func load(
        _ raw: String,
        baseURL: URL?,
        maximumFileBytes: Int = PreviewImageLoader.maximumFileBytes,
        maximumDataBytes: Int = PreviewImageLoader.maximumDataBytes
    ) -> PreviewImageResult {
        if raw.lowercased().hasPrefix("data:image/") {
            guard let comma = raw.firstIndex(of: ",") else { return .missing }
            let encoded = raw[raw.index(after: comma)...]
            // Base64 is 4/3 the size of what it encodes; check before decoding.
            guard encoded.utf8.count <= maximumDataBytes / 3 * 4 + 4,
                  let data = Data(base64Encoded: String(encoded)) else {
                return .missing
            }
            return decode(CGImageSourceCreateWithData(data as CFData, nil))
        }

        if isRemote(raw) { return .blocked }

        guard let url = localURL(raw, baseURL: baseURL) else { return .missing }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        guard let size, size <= maximumFileBytes else { return .missing }
        return decode(CGImageSourceCreateWithURL(url as CFURL, nil))
    }

    /// The cache key for a source. For a local file it includes the
    /// modification date and size, so an image edited on disk is read again.
    public static func cacheKey(_ raw: String, baseURL: URL?) -> String {
        guard !isRemote(raw),
              !raw.lowercased().hasPrefix("data:"),
              let url = localURL(raw, baseURL: baseURL),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return raw
        }
        let stamp = values.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(stamp)|\(values.fileSize ?? 0)"
    }

    // MARK: - Helpers

    /// Anything with a scheme and `//` (http, https, ftp, ...) except `file`.
    /// A bare `name:1.png` is a file name, not a URL.
    private static func isRemote(_ raw: String) -> Bool {
        guard let scheme = scheme(of: raw), scheme != "file" else { return false }
        return raw.contains("://")
    }

    private static func scheme(of raw: String) -> String? {
        guard let colon = raw.firstIndex(of: ":"),
              let first = raw.first, first.isLetter,
              raw[..<colon].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else {
            return nil
        }
        return raw[..<colon].lowercased()
    }

    private static func localURL(_ raw: String, baseURL: URL?) -> URL? {
        var path = raw
        if path.lowercased().hasPrefix("file://") {
            path = String(path.dropFirst("file://".count))
        }
        path = path.removingPercentEncoding ?? path
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).standardizedFileURL
        }
        guard let baseURL else { return nil }
        return URL(fileURLWithPath: path, relativeTo: baseURL).standardizedFileURL
    }

    private static func decode(_ source: CGImageSource?) -> PreviewImageResult {
        guard let source, CGImageSourceGetCount(source) > 0 else { return .missing }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return .missing
        }
        // Point size follows the image's own density, as NSImage(contentsOf:)
        // did: a 144 dpi screenshot is half as wide in points as in pixels.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = (properties?[kCGImagePropertyDPIWidth] as? Double) ?? 72
        let scale = dpi > 0 ? 72 / dpi : 1
        let image = NSImage(
            cgImage: cg,
            size: NSSize(width: Double(cg.width) * scale, height: Double(cg.height) * scale)
        )
        return .image(image)
    }
}
