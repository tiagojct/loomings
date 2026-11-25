import AppKit
import Foundation
import Testing
@testable import LoomingsPreview

@Suite("Preview image resolver")
struct PreviewImageResolverTests {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-resolver-\(UUID().uuidString)", isDirectory: true)
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

    @Test("Resolves local and data images and preserves blocked placeholders")
    func resolvesImagesAndPreservesPlaceholders() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let localFile = dir.appendingPathComponent("local.png")
        try pngData(width: 48, height: 24).write(to: localFile)

        let blockedFile = dir.appendingPathComponent("blocked.png")
        try pngData(width: 60, height: 30).write(to: blockedFile)

        let dataEncoded = pngData(width: 20, height: 10).base64EncodedString()
        let dataURI = "data:image/png;base64,\(dataEncoded)"

        let documentURL = dir.appendingPathComponent("doc.md")
        let markdown = """
        ![Local](./local.png)

        ![Data](\(dataURI))

        ![Blocked](\(blockedFile.path))
        """
        let rendered = PreviewRenderer(producesHTML: false).render(
            source: markdown,
            documentURL: documentURL
        )

        let resolved = PreviewImageResolver.resolve(
            rendered.attributed,
            documentURL: documentURL,
            allowImagePaths: true
        )

        let attachments = resolved.ranges(of: .attachment).compactMap { $0.1 as? NSTextAttachment }
        #expect(attachments.count == 3)
        #expect(attachments[0].image?.size == NSSize(width: 48, height: 24))
        #expect(attachments[0].bounds == NSRect(x: 0, y: -3, width: 16, height: 16))
        #expect(attachments[1].image?.size == NSSize(width: 20, height: 10))
        #expect(attachments[1].bounds == NSRect(x: 0, y: -3, width: 16, height: 16))
        #expect(attachments[2].image?.size == NSSize(width: 60, height: 30))
        #expect(attachments[2].bounds == NSRect(x: 0, y: -3, width: 16, height: 16))

        let untrustedResolved = PreviewImageResolver.resolve(
            rendered.attributed,
            documentURL: documentURL,
            allowImagePaths: false
        )
        let untrustedAttachments = untrustedResolved.ranges(of: .attachment).compactMap { $0.1 as? NSTextAttachment }
        #expect(untrustedAttachments.count == 3)
        #expect(untrustedAttachments[0].image?.size != NSSize(width: 48, height: 24))
        #expect(untrustedAttachments[0].bounds == NSRect(x: 0, y: -3, width: 16, height: 16))
        #expect(untrustedAttachments[1].image?.size == NSSize(width: 20, height: 10))
        #expect(untrustedAttachments[1].bounds == NSRect(x: 0, y: -3, width: 16, height: 16))
        #expect(untrustedAttachments[2].image?.size != NSSize(width: 60, height: 30))
        #expect(untrustedAttachments[2].bounds == NSRect(x: 0, y: -3, width: 16, height: 16))

        let originalAttachments = rendered.attributed.ranges(of: .attachment).compactMap { $0.1 as? NSTextAttachment }
        #expect(originalAttachments[0].image?.size != NSSize(width: 48, height: 24))
        #expect(originalAttachments[1].image?.size != NSSize(width: 20, height: 10))
    }

    @Test("PDF rendered from resolved attributed text contains image subtype and text-only PDF does not")
    @MainActor
    func pdfEmbedsResolvedImages() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let localFile = dir.appendingPathComponent("local.png")
        try pngData(width: 48, height: 24).write(to: localFile)
        let dataEncoded = pngData(width: 20, height: 10).base64EncodedString()
        let documentURL = dir.appendingPathComponent("doc.md")

        let imageMarkdown = """
        ![Local](./local.png)

        ![Data](data:image/png;base64,\(dataEncoded))
        """
        let rendered = PreviewRenderer(producesHTML: false).render(
            source: imageMarkdown,
            documentURL: documentURL
        )
        let resolved = PreviewImageResolver.resolve(
            rendered.attributed,
            documentURL: documentURL,
            allowImagePaths: true
        )

        let imagePDF = try printToPDF(resolved, in: dir.appendingPathComponent("images.pdf"))
        let textRendered = PreviewRenderer(producesHTML: false).render(
            source: "# Heading\n\nPlain paragraph.\n",
            documentURL: documentURL
        )
        let textResolved = PreviewImageResolver.resolve(
            textRendered.attributed,
            documentURL: documentURL,
            allowImagePaths: true
        )
        let textPDF = try printToPDF(textResolved, in: dir.appendingPathComponent("text.pdf"))

        let marker = Data("/Subtype /Image".utf8)
        #expect(imagePDF.range(of: marker) != nil)
        #expect(textPDF.range(of: marker) == nil)
    }

    @MainActor
    private func printToPDF(_ attributed: NSAttributedString, in url: URL) throws -> Data {
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
        view.textStorage?.setAttributedString(attributed)
        if let container = view.textContainer, let layout = view.layoutManager {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: 480, height: CGFloat.greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).height
            view.frame = NSRect(x: 0, y: 0, width: 480, height: max(200, used))
        }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        #expect(operation.run())
        return try Data(contentsOf: url)
    }
}
