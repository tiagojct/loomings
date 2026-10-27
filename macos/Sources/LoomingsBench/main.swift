import AppKit
import Darwin
import Foundation
import LoomingsEditor
import LoomingsMarkdown
import LoomingsPreview
import LoomingsTheme

// Stage 1 measurements. Run in a release build:
//   swift run -c release --package-path macos LoomingsBench
// The app-owned handler is measured separately from the whole insert call so
// a slow AppKit layout is not mistaken for our work.

private struct Sample {
    let bytes: Int
    let lines: Int
    let parseP50: Double
    let parseP95: Double
    let spans: Int
    let nodes: Int
    let insertP50: Double
    let insertP95: Double
    let handlerP50: Double
    let handlerP95: Double
    let snapshot: Double
    let apply: Double
    let scrollCallP95: Double
    let scrollApplyP95: Double
    let footprintMB: Double
}

@MainActor
private func run() {
    print("Loomings native benchmark — Stage 1")
    print("machine: \(machineModel()) / \(architecture())")
    print("memory: \(ProcessInfo.processInfo.physicalMemory / 1_048_576) MB")
    print("os: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    if let screen = NSScreen.main {
        print("display: \(Int(screen.frame.width))x\(Int(screen.frame.height)) @ \(screen.maximumFramesPerSecond) Hz")
    }
    print("")

    let palette = benchPalette()
    let startupStart = DispatchTime.now().uptimeNanoseconds
    let startupHost = makeEditor(palette: palette)
    startupHost.controller.setText(makeCorpus(bytes: 10 * 1024, shape: "mixed"))
    waitForParse(startupHost.controller)
    let startupMs = Double(DispatchTime.now().uptimeNanoseconds - startupStart) / 1_000_000
    startupHost.window.close()
    print("editor startup (window + 10 KB + first styling): \(format(startupMs)) ms")
    print("")

    let sizes = [10 * 1024, 100 * 1024, 1 * 1024 * 1024, 10 * 1024 * 1024]
    print("theme: \(palette?.familyLabel ?? "system") \(palette?.modeLabel ?? "")")
    let editor = makeEditor(palette: palette)
    defer { editor.window.close() }

    var samples: [Sample] = []

    for size in sizes {
        for shape in ["mixed", "longline"] {
            let corpus = makeCorpus(bytes: size, shape: shape)
            let lineCount = corpus.utf8.reduce(into: 1) { count, byte in
                if byte == 0x0A { count += 1 }
            }

            let parseRuns = size >= 10 * 1024 * 1024 ? 3 : 5
            var parseTimes: [Double] = []
            var lastSpanCount = 0
            var lastNodeCount = 0

            for runIndex in 0..<parseRuns {
                let start = DispatchTime.now().uptimeNanoseconds
                let output = MarkdownParser.parse(corpus)
                let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                if runIndex > 0 {
                    parseTimes.append(elapsed)
                }
                lastSpanCount = output.spans.count
                lastNodeCount = output.nodeCount
            }

            if shape == "longline" {
                samples.append(
                    Sample(
                        bytes: size,
                        lines: lineCount,
                        parseP50: percentile(parseTimes, 0.50),
                        parseP95: percentile(parseTimes, 0.95),
                        spans: lastSpanCount,
                        nodes: lastNodeCount,
                        insertP50: 0,
                        insertP95: 0,
                        handlerP50: 0,
                        handlerP95: 0,
                        snapshot: 0,
                        apply: 0,
                        scrollCallP95: 0,
                        scrollApplyP95: 0,
                        footprintMB: footprintMB()
                    )
                )
                continue
            }

            let controller = editor.controller
            controller.setText(corpus)
            // Leave the parse running while the first insertions happen: this
            // is the typing-independence check, not a warm measurement.
            let typingSamples = size >= 10 * 1024 * 1024 ? 40 : 120
            var insertTimes: [Double] = []
            var handlerTimes: [Double] = []
            let textLength = (controller.source as NSString).length
            let focus = min(textLength / 2, 5_000)
            controller.textView.setSelectedRange(NSRange(location: focus, length: 0))
            controller.textView.scrollRangeToVisible(NSRange(location: focus, length: 0))

            for _ in 0..<typingSamples {
                let start = DispatchTime.now().uptimeNanoseconds
                controller.textView.insertText(
                    "x",
                    replacementRange: controller.textView.selectedRange()
                )
                insertTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
                handlerTimes.append(
                    Double(controller.lastEditHandlerNanoseconds) / 1_000_000
                )
            }

            waitForParse(controller)
            let snapshot = Double(controller.lastSnapshotNanoseconds) / 1_000_000
            let apply = Double(controller.lastApplyNanoseconds) / 1_000_000
            let scroll = measureScrolling(editor, steps: size >= 10 * 1024 * 1024 ? 12 : 24)
            let editFootprint = footprintMB()

            samples.append(
                Sample(
                    bytes: size,
                    lines: lineCount,
                    parseP50: percentile(parseTimes, 0.50),
                    parseP95: percentile(parseTimes, 0.95),
                    spans: lastSpanCount,
                    nodes: lastNodeCount,
                    insertP50: percentile(insertTimes, 0.50),
                    insertP95: percentile(insertTimes, 0.95),
                    handlerP50: percentile(handlerTimes, 0.50),
                    handlerP95: percentile(handlerTimes, 0.95),
                    snapshot: snapshot,
                    apply: apply,
                    scrollCallP95: scroll.call,
                    scrollApplyP95: scroll.apply,
                    footprintMB: editFootprint
                )
            )
        }
    }

    printTable(samples)
    print("")
    printPreviewTable(palette: palette)
    print("")
    print("parse columns: whole-document MarkdownParser.parse, ms (warm runs)")
    print("insert: NSTextView.insertText call, ms; handler: app-owned textDidChange, ms")
    print("snapshot: String(textView.string) on main; apply: visible-region styling, ms")
    print("scroll call: scrollRangeToVisible + layout; scroll apply: styling that followed, ms")
    print("footprint: process phys_footprint after the editor load")

    let large = samples.filter { $0.bytes >= 1_048_576 }
    let handlerP95 = large.map(\.handlerP95).max() ?? 0
    print("")
    print(handlerP95 < 8
        ? "Stage 1 handler target: PASS (max p95 \(format(handlerP95)) ms for ≥1 MB)"
        : "Stage 1 handler target: MISS (max p95 \(format(handlerP95)) ms for ≥1 MB)")
}

// MARK: - Editor host

@MainActor
private final class EditorHost {
    let controller = EditorController()
    let window: NSWindow
    let scrollView: NSScrollView

    init(palette: ResolvedPalette?) {
        controller.applyPalette(palette)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 960, height: 700))
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = controller.textView
        controller.textView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: scrollView.contentSize.width, height: 700)
        )
        window.contentView = scrollView
        controller.observeScrolling(in: scrollView)
        window.orderBack(nil)
    }
}

@MainActor
private func makeEditor(palette: ResolvedPalette?) -> EditorHost {
    EditorHost(palette: palette)
}

private func benchPalette() -> ResolvedPalette? {
    let macos = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // LoomingsBench
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // macos
    let url = macos.appendingPathComponent("Resources/palettes.json")
    guard let data = try? Data(contentsOf: url),
          let library = PaletteLibrary(data: data) else {
        return nil
    }
    return library.resolve(family: "pequod", mode: .dark, systemIsDark: true)
}

@MainActor
private func measureScrolling(_ host: EditorHost, steps: Int) -> (call: Double, apply: Double) {
    let textLength = (host.controller.source as NSString).length
    guard textLength > 0, steps > 1 else { return (0, 0) }

    var callTimes: [Double] = []
    var applyTimes: [Double] = []

    for step in 0..<steps {
        let location = min(textLength - 1, textLength * step / steps)
        let before = host.controller.stylingApplies

        let start = DispatchTime.now().uptimeNanoseconds
        host.controller.textView.scrollRangeToVisible(NSRange(location: location, length: 0))
        host.scrollView.layoutSubtreeIfNeeded()
        callTimes.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)

        let deadline = Date().addingTimeInterval(1)
        while host.controller.stylingApplies == before && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.002))
        }
        if host.controller.stylingApplies > before {
            applyTimes.append(Double(host.controller.lastApplyNanoseconds) / 1_000_000)
        }
    }

    return (percentile(callTimes, 0.95), percentile(applyTimes, 0.95))
}

@MainActor
private func waitForParse(_ controller: EditorController, timeout: TimeInterval = 60) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if controller.lastAppliedRevision == controller.revision {
            // A short grace period lets the debounce fire for the last edit.
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            if controller.lastAppliedRevision == controller.revision {
                return
            }
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.005))
    }
}

// MARK: - Corpus

private func makeCorpus(bytes: Int, shape: String) -> String {
    if shape == "longline" {
        let sentence = "The sea was *calm* and the sky was `wide`, and the ship held her course. "
        let header = "# A single long paragraph\n\n"
        let available = max(0, bytes - header.utf8.count - 1)
        let repeats = max(0, available / sentence.utf8.count)
        return header + String(repeating: sentence, count: repeats) + "\n"
    }

    let block = """
    # Chapter heading

    A short line of prose that wraps at the window edge.

    - one item
    - two items
    - three items

    > A quotation from the deck.

    ```swift
    let whale = "white"
    ```

    A paragraph with *emphasis*, **strong**, `inline code` and a [link](https://example.com).

    """
    let repeats = max(1, bytes / block.utf8.count)
    return String(String(repeating: block, count: repeats).prefix(bytes))
}

// MARK: - Reporting

private func printPreviewTable(palette: ResolvedPalette?) {
    print("preview render (parse + attributed string + HTML), ms")
    let header = ["bytes", "p50", "p95", "blocks", "html bytes"]
    var rows: [[String]] = []

    for size in [10 * 1024, 100 * 1024, 1 * 1024 * 1024, 10 * 1024 * 1024] {
        let source = makeCorpus(bytes: size, shape: "mixed")
        var times: [Double] = []
        var blockCount = 0
        var htmlBytes = 0

        for run in 0..<3 {
            let start = DispatchTime.now().uptimeNanoseconds
            let theme = palette.map { PreviewTheme.themed($0) } ?? .standard
            let rendered = PreviewRenderer(theme: theme).render(source: source, documentURL: nil)
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            if run > 0 {
                times.append(elapsed)
            }
            blockCount = rendered.blocks.count
            htmlBytes = rendered.html.utf8.count
        }

        rows.append([
            "\(size)",
            format(percentile(times, 0.50)),
            format(percentile(times, 0.95)),
            "\(blockCount)",
            "\(htmlBytes)",
        ])
    }

    let widths = header.enumerated().map { index, title in
        max(title.count, rows.map { $0[index].count }.max() ?? 0)
    }
    func line(_ values: [String]) -> String {
        values.enumerated().map { index, value in
            value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
    }
    print(line(header))
    print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
    for row in rows {
        print(line(row))
    }
    print("preview target: 150 ms after a typing pause through 1 MB")
}

private func printTable(_ samples: [Sample]) {
    let header = [
        "bytes", "lines", "parse p50", "parse p95", "spans", "nodes",
        "insert p50", "insert p95", "handler p50", "handler p95",
        "snapshot", "apply", "scroll call", "scroll apply", "footprint",
    ]
    let rows = samples.map { sample in
        [
            "\(sample.bytes)",
            "\(sample.lines)",
            format(sample.parseP50),
            format(sample.parseP95),
            "\(sample.spans)",
            "\(sample.nodes)",
            sample.insertP50 == 0 ? "—" : format(sample.insertP50),
            sample.insertP95 == 0 ? "—" : format(sample.insertP95),
            sample.handlerP50 == 0 ? "—" : format(sample.handlerP50),
            sample.handlerP95 == 0 ? "—" : format(sample.handlerP95),
            sample.snapshot == 0 ? "—" : format(sample.snapshot),
            sample.apply == 0 ? "—" : format(sample.apply),
            sample.scrollCallP95 == 0 ? "—" : format(sample.scrollCallP95),
            sample.scrollApplyP95 == 0 ? "—" : format(sample.scrollApplyP95),
            format(sample.footprintMB) + " MB",
        ]
    }

    let widths = header.enumerated().map { index, title in
        max(title.count, rows.map { $0[index].count }.max() ?? 0)
    }
    func line(_ values: [String]) -> String {
        values.enumerated().map { index, value in
            value.padding(toLength: widths[index], withPad: " ", startingAt: 0)
        }.joined(separator: "  ")
    }

    print(line(header))
    print(widths.map { String(repeating: "-", count: $0) }.joined(separator: "  "))
    for row in rows {
        print(line(row))
    }
}

private func format(_ value: Double) -> String {
    String(format: "%.2f", value)
}

private func percentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let index = max(0, min(sorted.count - 1, Int((Double(sorted.count) * fraction).rounded(.up)) - 1))
    return sorted[index]
}

private func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
        MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
        }
    }
    guard result == KERN_SUCCESS else { return 0 }
    return Double(info.phys_footprint) / 1_048_576
}

private func machineModel() -> String {
    var size = 0
    guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else {
        return "unknown"
    }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else {
        return "unknown"
    }
    return String(cString: buffer)
}

private func architecture() -> String {
    #if arch(arm64)
    return "arm64"
    #elseif arch(x86_64)
    return "x86_64"
    #else
    return "unknown"
    #endif
}

MainActor.assumeIsolated {
    NSApplication.shared.setActivationPolicy(.accessory)
    run()
}
