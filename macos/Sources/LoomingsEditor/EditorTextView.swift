import AppKit

/// A transient mark drawn behind or under the text: the paired source in
/// Split view, a checker note, the current line in projector mode. These
/// are drawn here from TextKit 2's text segments, because rendering
/// attributes cannot change text that is already laid out.
public struct EditorDecoration: Equatable {
    public enum Style: Equatable {
        /// Whole lines, edge to edge of the text column.
        case lineFill(NSColor)
        /// A wavy line under the characters.
        case squiggle(NSColor)
    }

    public let range: NSRange
    public let style: Style

    public init(range: NSRange, style: Style) {
        self.range = range
        self.style = style
    }
}

public final class EditorTextView: NSTextView {
    /// Option-click asks what is under the pointer instead of placing the
    /// caret (an option-drag still makes a rectangular selection).
    var onOptionClick: ((Int) -> Void)?

    public override func mouseDown(with event: NSEvent) {
        if let onOptionClick, event.modifierFlags.contains(.option), event.clickCount == 1,
           !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift) {
            let point = convert(event.locationInWindow, from: nil)
            let next = window?.nextEvent(matching: [.leftMouseUp, .leftMouseDragged], until: .distantFuture, inMode: .eventTracking, dequeue: false)
            if next?.type == .leftMouseUp {
                onOptionClick(characterIndexForInsertion(at: point))
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Decorations by owner ("pair", "notes", "line"), so each feature
    /// replaces only its own.
    private var layers: [String: [EditorDecoration]] = [:]

    public func setDecorations(_ decorations: [EditorDecoration], for owner: String) {
        guard layers[owner] != decorations else { return }
        layers[owner] = decorations.isEmpty ? nil : decorations
        needsDisplay = true
    }

    public func decorations(for owner: String) -> [EditorDecoration] {
        layers[owner] ?? []
    }

    /// The decorations that can touch `rect`: its character range is found
    /// from the layout fragments at its top and bottom, then decorations are
    /// filtered by range before any frame is asked of TextKit.
    public func decorations(intersecting rect: NSRect) -> [EditorDecoration] {
        let all = layers.values.joined()
        guard !all.isEmpty, let visible = characterRange(of: rect) else { return [] }
        return all.filter { decoration in
            decoration.range.location <= NSMaxRange(visible)
                && NSMaxRange(decoration.range) >= visible.location
        }
    }

    /// The characters laid out within `rect` (view coordinates), or nil when
    /// that part of the text has no layout yet.
    private func characterRange(of rect: NSRect) -> NSRange? {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager else { return nil }
        let origin = textContainerOrigin
        let documentStart = contentManager.documentRange.location
        let top = CGPoint(x: 0, y: max(0, rect.minY - origin.y))
        let bottom = CGPoint(x: 0, y: max(0, rect.maxY - origin.y))
        guard let first = layoutManager.textLayoutFragment(for: top)
                ?? layoutManager.textViewportLayoutController.viewportRange.flatMap({ layoutManager.textLayoutFragment(for: $0.location) }) else {
            return nil
        }
        let last = layoutManager.textLayoutFragment(for: bottom)
        let start = contentManager.offset(from: documentStart, to: first.rangeInElement.location)
        let endLocation = last?.rangeInElement.endLocation
            ?? layoutManager.textViewportLayoutController.viewportRange?.endLocation
            ?? contentManager.documentRange.endLocation
        let end = contentManager.offset(from: documentStart, to: endLocation)
        return NSRange(location: start, length: max(0, end - start))
    }

    /// Frames of `range` in view coordinates, one per line segment.
    public func segmentFrames(for range: NSRange) -> [NSRect] {
        guard let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(contentManager.documentRange.location, offsetBy: range.location),
              let end = contentManager.location(start, offsetBy: max(0, range.length)),
              let textRange = NSTextRange(location: start, end: end) else {
            return []
        }
        let origin = textContainerOrigin
        var frames: [NSRect] = []
        layoutManager.enumerateTextSegments(in: textRange, type: .highlight, options: [.rangeNotRequired]) { _, frame, _, _ in
            frames.append(frame.offsetBy(dx: origin.x, dy: origin.y))
            return true
        }
        return frames
    }

    /// Line fills sit behind the text.
    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        for decoration in decorations(intersecting: rect) {
            guard case .lineFill(let color) = decoration.style else { continue }
            color.setFill()
            for line in lineRects(for: decoration.range) where line.intersects(rect) {
                line.fill(using: .sourceOver)
            }
        }
    }

    /// Squiggles sit under the characters, drawn after them.
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for decoration in decorations(intersecting: dirtyRect) {
            guard case .squiggle(let color) = decoration.style else { continue }
            for frame in segmentFrames(for: decoration.range) where frame.insetBy(dx: 0, dy: -3).intersects(dirtyRect) {
                drawSquiggle(under: frame, color: color)
            }
        }
    }

    /// Whole-line rectangles across the text column for `range`.
    public func lineRects(for range: NSRange) -> [NSRect] {
        let containerWidth = textContainer?.size.width ?? bounds.width
        let originX = textContainerOrigin.x
        return segmentFrames(for: range).map {
            NSRect(x: originX - 6, y: $0.minY, width: containerWidth + 12, height: $0.height)
        }
    }

    private func drawSquiggle(under frame: NSRect, color: NSColor) {
        let path = NSBezierPath()
        let y = frame.maxY - 2
        var x = frame.minX
        path.move(to: NSPoint(x: x, y: y))
        var up = true
        while x < frame.maxX {
            x = min(frame.maxX, x + 2)
            path.line(to: NSPoint(x: x, y: up ? y - 1.5 : y))
            up.toggle()
        }
        color.setStroke()
        path.lineWidth = 1.2
        path.stroke()
    }
}
