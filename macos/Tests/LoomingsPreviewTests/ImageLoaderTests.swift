import AppKit
import Foundation
import Testing
@testable import LoomingsPreview

@Suite("Preview image loader")
struct ImageLoaderTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pngData(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        return rep.representation(using: .png, properties: [:])!
    }

    private func size(of result: PreviewImageResult) -> NSSize? {
        if case .image(let image) = result { return image.size }
        return nil
    }

    @Test("Remote sources are blocked, never fetched")
    func remoteIsBlocked() {
        for raw in ["https://example.com/a.png", "http://example.com/a.png", "HTTPS://example.com/a.png", "ftp://example.com/a.png"] {
            guard case .blocked = PreviewImageLoader.load(raw, baseURL: URL(fileURLWithPath: "/tmp")) else {
                Issue.record("\(raw) was not blocked")
                continue
            }
        }
    }

    @Test("A relative path resolves against the document directory")
    func relativePath() throws {
        let dir = try makeDirectory()
        try pngData(width: 40, height: 20).write(to: dir.appendingPathComponent("a.png"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)

        let found = PreviewImageLoader.load("a.png", baseURL: dir)
        #expect(size(of: found)?.width == 40)

        let viaParent = PreviewImageLoader.load("../a.png", baseURL: dir.appendingPathComponent("sub"))
        #expect(size(of: viaParent)?.width == 40)

        guard case .missing = PreviewImageLoader.load("nope.png", baseURL: dir) else {
            Issue.record("a missing file was not reported missing")
            return
        }
        guard case .missing = PreviewImageLoader.load("a.png", baseURL: nil) else {
            Issue.record("a relative path without a document was not reported missing")
            return
        }
    }

    @Test("Percent-encoded paths and colons in file names resolve")
    func encodedPaths() throws {
        let dir = try makeDirectory()
        try pngData(width: 10, height: 10).write(to: dir.appendingPathComponent("my image.png"))
        try pngData(width: 12, height: 10).write(to: dir.appendingPathComponent("photo:1.png"))
        #expect(size(of: PreviewImageLoader.load("my%20image.png", baseURL: dir))?.width == 10)
        #expect(size(of: PreviewImageLoader.load("photo:1.png", baseURL: dir))?.width == 12)
    }

    @Test("Oversized files are refused")
    func fileSizeCap() throws {
        let dir = try makeDirectory()
        try pngData(width: 200, height: 200).write(to: dir.appendingPathComponent("big.png"))
        guard case .missing = PreviewImageLoader.load("big.png", baseURL: dir, maximumFileBytes: 100) else {
            Issue.record("a file over the cap was loaded")
            return
        }
    }

    @Test("Wide images are decoded at preview width")
    func downsamples() throws {
        let dir = try makeDirectory()
        try pngData(width: 3000, height: 100).write(to: dir.appendingPathComponent("wide.png"))
        let width = size(of: PreviewImageLoader.load("wide.png", baseURL: dir))?.width ?? 0
        #expect(width > 0 && width <= CGFloat(PreviewImageLoader.maximumPixels))
    }

    @Test("data: URIs load, and oversized ones do not")
    func dataURIs() throws {
        let encoded = pngData(width: 8, height: 8).base64EncodedString()
        let uri = "data:image/png;base64,\(encoded)"
        #expect(size(of: PreviewImageLoader.load(uri, baseURL: nil))?.width == 8)
        guard case .missing = PreviewImageLoader.load(uri, baseURL: nil, maximumDataBytes: 16) else {
            Issue.record("an oversized data URI was decoded")
            return
        }
        guard case .missing = PreviewImageLoader.load("data:image/png;base64,@@@", baseURL: nil) else {
            Issue.record("a malformed data URI was decoded")
            return
        }
    }

    @Test("An image edited on disk gets a new cache key")
    func cacheKeyFollowsFile() throws {
        let dir = try makeDirectory()
        let file = dir.appendingPathComponent("a.png")
        try pngData(width: 4, height: 4).write(to: file)
        let first = PreviewImageLoader.cacheKey("a.png", baseURL: dir)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)],
            ofItemAtPath: file.path
        )
        let second = PreviewImageLoader.cacheKey("a.png", baseURL: dir)
        #expect(first != second)
        #expect(PreviewImageLoader.cacheKey("https://example.com/a.png", baseURL: dir) == "https://example.com/a.png")
    }
}
