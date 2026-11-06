import AppKit
import Foundation
import LoomingsCitations
import PDFKit

/// Draws the editor window to PNG files without screen-recording access, for
/// design review: `Loomings --snapshot <out-dir> <file.md>`. Theme and other
/// preferences can be overridden for one run with argument-domain defaults,
/// for example `-Loomings.Native.themeFamily pequod -Loomings.Native.themeMode dark`.
/// `-LoomingsSnapshotWidth 640` sets the window width;
/// `-LoomingsSnapshotPairLocation <n>` lights the pair at that source location in Split;
/// `-LoomingsSnapshotProjector YES` turns on projector mode with a sample caption;
/// `-LoomingsSnapshotCompareWith <file>` also writes compare.png;
/// `-LoomingsSnapshotReferences YES` also writes references.png, Split with the library.
/// `-LoomingsSnapshotSidebar <folder>` also writes sidebar.png, Split with the file sidebar on that folder.
/// The input file is the base for relative images and bibliographies. The
/// document stays untitled, so nothing writes to that file.
/// Writes write.png, split.png and preview.png, then exits.
@MainActor
enum Snapshot {
    static func run(arguments: [String]) -> Int32 {
        guard let flag = arguments.firstIndex(of: "--snapshot"),
              arguments.count > flag + 2 else {
            print("usage: Loomings --snapshot <out-dir> <file.md>")
            return 2
        }
        let output = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        let input = URL(fileURLWithPath: arguments[flag + 2])
        guard let text = try? String(contentsOf: input, encoding: .utf8) else {
            print("cannot read \(input.path)")
            return 1
        }
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        ThemeManager.shared.applyAppearance()
        let document = LoomingsDocument()
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        guard let controller = document.windowControllers.first as? EditorWindowController,
              let window = controller.window else {
            print("could not create the editor window")
            return 1
        }
        let width = UserDefaults.standard.double(forKey: "LoomingsSnapshotWidth")
        window.setContentSize(NSSize(width: width > 0 ? width : 1180, height: 760))
        controller.showWindow(nil)
        controller.applyPreferences()
        document.snapshotFileURL = input
        controller.editor.setText(text)
        settleCitations(controller, text: text)
        if UserDefaults.standard.bool(forKey: "LoomingsSnapshotProjector") {
            controller.toggleProjectorMode(nil)
            controller.editor.textView.setSelectedRange(NSRange(location: 2, length: 0))
        }

        for (name, mode) in [("write", EditorWindowController.ViewMode.write), ("split", .split), ("preview", .preview)] {
            controller.setViewMode(mode)
            settle(1.2)
            if controller.isProjectorMode { controller.showOverlayForSnapshot("Heading 2: ## ") }
            let pairLocation = UserDefaults.standard.integer(forKey: "LoomingsSnapshotPairLocation")
            if mode == .split, pairLocation > 0 {
                controller.pairBothForSnapshot(editorLocation: pairLocation)
                settle(0.3)
            }
            write(window, to: output.appendingPathComponent("\(name).png"))
        }
        if UserDefaults.standard.bool(forKey: "LoomingsSnapshotReferences") {
            controller.toggleReferences(nil)
            settle(1.2)
            write(window, to: output.appendingPathComponent("references.png"))
        }

        if let folder = UserDefaults.standard.string(forKey: "LoomingsSnapshotSidebar") {
            EditorPreferences.sidebarEnabled = true
            controller.setSidebarFolder(URL(fileURLWithPath: folder, isDirectory: true))
            NotificationCenter.default.post(name: .loomingsFeaturesChanged, object: nil)
            if !controller.isSidebarVisibleForTesting { controller.toggleSidebar(nil) }
            settle(1.2)
            write(window, to: output.appendingPathComponent("sidebar.png"))
        }

        // Compare With, against another file.
        if let other = UserDefaults.standard.string(forKey: "LoomingsSnapshotCompareWith"),
           let otherText = try? String(contentsOfFile: other, encoding: .utf8) {
            let compare = controller.compare(withText: otherText, title: "Exercise")
            settle(0.8)
            if let frame = compare.window?.contentView?.superview,
               let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                frame.cacheDisplay(in: frame.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("compare.png"))
            }
            compare.close()
        }

        // The handout, and its first and last pages as images.
        let pdf = controller.renderedPDFForTesting()
        try? pdf.write(to: output.appendingPathComponent("handout.pdf"))
        if let document = PDFDocument(data: pdf), document.pageCount > 0 {
            for (name, index) in [("handout-first", 0), ("handout-last", document.pageCount - 1)] {
                guard let page = document.page(at: index) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let image = page.thumbnail(of: NSSize(width: bounds.width * 1.5, height: bounds.height * 1.5), for: .mediaBox)
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: output.appendingPathComponent("\(name).png"))
                }
            }
        }
        controller.editor.setText("")
        window.close()
        return 0
    }

    private static func write(_ window: NSWindow, to url: URL) {
        guard let frame = window.contentView?.superview,
              let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
            print(url.path)
        }
    }

    /// The first report takes about 2 s. A shot must not show literal keys.
    private static func settleCitations(_ controller: EditorWindowController, text: String) {
        guard CitationGate.applies(to: text) else { return }
        let until = Date().addingTimeInterval(15)
        while controller.citations.report(for: text) == nil, Date() < until {
            settle(0.05)
        }
    }

    private static func settle(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}
