import AppKit
import LoomingsEditor

/// Catches files dropped anywhere over the editor. NSTextView does not
/// register for file URLs, so the scroll view sees them and opens documents
/// instead of inserting their names as text. Dropped images become links in
/// the document.
final class DocumentScrollView: NSScrollView {
    var onOpenFiles: (([URL]) -> Void)?
    /// The images and the drop point in window coordinates.
    var onInsertImages: (([URL], NSPoint) -> Void)?

    convenience init() {
        self.init(frame: .zero)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DocumentScrollView is created in code")
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        supportedFileURLs(from: sender).isEmpty ? super.draggingEntered(sender) : .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        supportedFileURLs(from: sender).isEmpty ? super.draggingUpdated(sender) : .copy
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = supportedFileURLs(from: sender)
        guard !urls.isEmpty, let onOpenFiles, let onInsertImages else {
            return super.performDragOperation(sender)
        }
        let images = urls.filter(ImageLink.isImage)
        let documents = urls.filter { !ImageLink.isImage($0) }
        if !images.isEmpty { onInsertImages(images, sender.draggingLocation) }
        if !documents.isEmpty { onOpenFiles(documents) }
        return true
    }

    private func supportedFileURLs(from info: any NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []
        let allowed: Set<String> = ["md", "markdown", "txt", "text"]
        return objects
            .map { $0 as URL }
            .filter { allowed.contains($0.pathExtension.lowercased()) || ImageLink.isImage($0) }
    }
}
