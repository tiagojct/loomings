import AppKit
import LoomingsPreview
import LoomingsShare
import LoomingsTheme

/// The printed and PDF form of a document: paginated on A4 or Letter, in the
/// light colours of the current family on white paper, every page numbered,
/// and the share link as a QR code at the end so the sheet leads back to an
/// editable document.
@MainActor
enum Handout {
    static var paperSize: NSSize {
        Locale.current.measurementSystem == .us
            ? NSSize(width: 612, height: 792)
            : NSSize(width: 595, height: 842)
    }

    static let sideMargin: CGFloat = 54
    static let topMargin: CGFloat = 54
    static let bottomMargin: CGFloat = 64

    static func printInfo() -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = paperSize
        info.topMargin = topMargin
        info.bottomMargin = bottomMargin
        info.leftMargin = sideMargin
        info.rightMargin = sideMargin
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    static func view(source: String, documentURL: URL?, title: String) -> HandoutTextView {
        let manager = ThemeManager.shared
        let light = manager.library?.resolve(family: manager.family, mode: .light, systemIsDark: false)
        let theme = light.map { PreviewTheme.themed($0) } ?? .standard
        let rendered = PreviewRenderer(theme: theme, producesHTML: false).render(source: source, documentURL: documentURL)

        let content = NSMutableAttributedString(attributedString: rendered.attributed)
        content.append(qrBlock(source: source, theme: theme))

        let width = paperSize.width - sideMargin * 2
        let view = HandoutTextView(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        view.title = title
        view.footerColor = theme.secondaryTextColor
        view.footerFont = NSFont(name: "SourceSerif4-Regular", size: 9) ?? .systemFont(ofSize: 9)
        view.isEditable = false
        view.isSelectable = false
        view.drawsBackground = true
        view.backgroundColor = .white
        view.appearance = NSAppearance(named: .aqua)
        view.textContainerInset = .zero
        view.textStorage?.setAttributedString(content)
        if let container = view.textContainer, let layout = view.layoutManager {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container).height
            view.frame = NSRect(x: 0, y: 0, width: width, height: max(200, used))
        }
        return view
    }

    /// The share link as a QR code with a line saying what it is, or a line
    /// saying why there is none.
    private static func qrBlock(source: String, theme: PreviewTheme) -> NSAttributedString {
        let block = NSMutableAttributedString()
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 24
        let caption: [NSAttributedString.Key: Any] = [
            .font: theme.bodyFont.withSize(theme.bodyFont.pointSize * 0.7),
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: style,
        ]
        let manager = ThemeManager.shared
        if let url = try? ShareLink.url(for: source, family: manager.family, mode: manager.mode.rawValue),
           let side = ShareQRCode.printSide(for: url),
           let code = ShareQRCode.image(for: url, side: side * 4) {
            let attachment = NSTextAttachment()
            attachment.image = NSImage(cgImage: code, size: NSSize(width: side, height: side))
            attachment.bounds = NSRect(x: 0, y: 0, width: side, height: side)
            let image = NSMutableAttributedString(attachment: attachment)
            image.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: image.length))
            block.append(NSAttributedString(string: "\n"))
            block.append(image)
            // No newline after the last line: an empty final line fragment
            // would print a blank last page.
            block.append(NSAttributedString(string: "\nScan to open this document in Loomings.", attributes: caption))
        } else {
            block.append(NSAttributedString(
                string: "\nThis document is too long for a QR code; share it as a link.",
                attributes: caption
            ))
        }
        return block
    }

    /// Writes the handout as a PDF file. Returns false if printing failed.
    @discardableResult
    static func writePDF(_ view: HandoutTextView, to url: URL) -> Bool {
        let info = printInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        return operation.run()
    }
}

/// A text view that prints "title · page n of N" at the foot of every page.
final class HandoutTextView: NSTextView {
    var title = ""
    var footerColor: NSColor = .secondaryLabelColor
    var footerFont: NSFont = .systemFont(ofSize: 9)

    override func drawPageBorder(with borderSize: NSSize) {
        guard let operation = NSPrintOperation.current else { return }
        let saved = frame
        setFrameOrigin(.zero)
        setFrameSize(borderSize)
        lockFocus()
        let page = operation.currentPage
        let total = operation.pageRange.length
        let parts = [title, "page \(page) of \(total)"].filter { !$0.isEmpty }
        let footer = parts.joined(separator: " \u{00B7} ") as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: footerFont, .foregroundColor: footerColor]
        let size = footer.size(withAttributes: attributes)
        footer.draw(
            at: NSPoint(x: (borderSize.width - size.width) / 2, y: borderSize.height - Handout.bottomMargin / 2 - size.height / 2),
            withAttributes: attributes
        )
        unlockFocus()
        frame = saved
    }
}
