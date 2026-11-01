import AppKit
import Foundation

/// Draws the editor window to PNG files without screen-recording access, for
/// design review: `Loomings --snapshot <out-dir> <file.md>`. Theme and other
/// preferences can be overridden for one run with argument-domain defaults,
/// for example `-Loomings.Native.themeFamily pequod -Loomings.Native.themeMode dark`.
/// `-LoomingsSnapshotWidth 640` sets the window width;
/// `-LoomingsSnapshotPairLocation <n>` lights the pair at that source location in Split.
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
        controller.editor.setText(text)

        for (name, mode) in [("write", EditorWindowController.ViewMode.write), ("split", .split), ("preview", .preview)] {
            controller.setViewMode(mode)
            settle(1.2)
            let pairLocation = UserDefaults.standard.integer(forKey: "LoomingsSnapshotPairLocation")
            if mode == .split, pairLocation > 0 {
                controller.pairBothForSnapshot(editorLocation: pairLocation)
                settle(0.3)
            }
            guard let frame = window.contentView?.superview else { continue }
            guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { continue }
            frame.cacheDisplay(in: frame.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: output.appendingPathComponent("\(name).png"))
                print(output.appendingPathComponent("\(name).png").path)
            }
        }
        controller.editor.setText("")
        window.close()
        return 0
    }

    private static func settle(_ seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        while Date() < until {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
}
