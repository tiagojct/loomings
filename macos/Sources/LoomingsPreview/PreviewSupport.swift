import AppKit
import Foundation
import LoomingsTheme

public enum PreviewBlockKind: String, Sendable {
    case heading
    case paragraph
    case list
    case quote
    case code
    case rule
    case table
    case html
}

public extension NSAttributedString.Key {
    /// Sanitised URL string for an image attachment.
    static let loomingsImageURL = NSAttributedString.Key("LoomingsImageURL")
    /// Original alt text for an image attachment.
    static let loomingsImageAlt = NSAttributedString.Key("LoomingsImageAlt")
}

public struct PreviewTheme: @unchecked Sendable {
    public var bodyFont: NSFont
    public var codeFont: NSFont
    public var textColor: NSColor
    public var secondaryTextColor: NSColor
    public var linkColor: NSColor
    public var codeColor: NSColor
    public var codeBackground: NSColor
    public var borderColor: NSColor
    public var quoteBorderColor: NSColor
    public var headingColor: NSColor
    public var emphasisColor: NSColor
    public var markerColor: NSColor
    public var background: NSColor

    public init(
        bodyFont: NSFont,
        codeFont: NSFont,
        textColor: NSColor,
        secondaryTextColor: NSColor,
        linkColor: NSColor,
        codeColor: NSColor,
        codeBackground: NSColor,
        borderColor: NSColor,
        quoteBorderColor: NSColor,
        headingColor: NSColor,
        emphasisColor: NSColor,
        markerColor: NSColor,
        background: NSColor
    ) {
        self.bodyFont = bodyFont
        self.codeFont = codeFont
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.linkColor = linkColor
        self.codeColor = codeColor
        self.codeBackground = codeBackground
        self.borderColor = borderColor
        self.quoteBorderColor = quoteBorderColor
        self.headingColor = headingColor
        self.emphasisColor = emphasisColor
        self.markerColor = markerColor
        self.background = background
    }

    public static let standard = PreviewTheme(
        bodyFont: NSFont.systemFont(ofSize: 17),
        codeFont: NSFont.monospacedSystemFont(ofSize: 15, weight: .regular),
        textColor: .labelColor,
        secondaryTextColor: .secondaryLabelColor,
        linkColor: .linkColor,
        codeColor: .secondaryLabelColor,
        codeBackground: .underPageBackgroundColor,
        borderColor: .separatorColor,
        quoteBorderColor: .controlAccentColor,
        headingColor: .labelColor,
        emphasisColor: .labelColor,
        markerColor: .controlAccentColor,
        background: .textBackgroundColor
    )

    public static func themed(
        _ palette: ResolvedPalette,
        bodySize: CGFloat = 17
    ) -> PreviewTheme {
        let colors = palette.colors
        let body = NSFont(name: "SourceSerif4-Regular", size: bodySize)
            ?? NSFont.systemFont(ofSize: bodySize)
        let code = NSFont(name: "JetBrainsMono-Regular", size: bodySize * 0.88)
            ?? NSFont.monospacedSystemFont(ofSize: bodySize * 0.88, weight: .regular)
        var heading = NSFont(name: "SourceSerif4-Bold", size: bodySize)
        if heading == nil {
            heading = NSFontManager.shared.convert(body, toHaveTrait: .boldFontMask)
        }
        return PreviewTheme(
            bodyFont: body,
            codeFont: code,
            textColor: colors.text,
            secondaryTextColor: colors.textDim,
            linkColor: colors.linkColor,
            codeColor: colors.codeColor,
            codeBackground: colors.backgroundDeep,
            borderColor: colors.borderColor,
            quoteBorderColor: colors.accentColor,
            headingColor: colors.headingColor,
            emphasisColor: colors.emphasisColor,
            markerColor: colors.markerColor,
            background: colors.background
        )
    }

    public func headingFont(level: Int) -> NSFont {
        let base = NSFont(name: "SourceSerif4-Bold", size: bodyFont.pointSize)
            ?? NSFontManager.shared.convert(bodyFont, toHaveTrait: .boldFontMask)
        let scale: CGFloat
        switch level {
        case 1: scale = 1.8
        case 2: scale = 1.4
        case 3: scale = 1.15
        case 4: scale = 1.05
        case 5: scale = 1.0
        default: scale = 0.95
        }
        return NSFontManager.shared.convert(
            base,
            toHaveTrait: []
        ).withSize(bodyFont.pointSize * scale)
    }
}

public struct PreviewBlock {
    public let kind: PreviewBlockKind
    /// UTF-16 range in the Markdown source.
    public let sourceRange: NSRange
    /// 0-based source line used by markdown-it's data-line.
    public let sourceLine: Int
    /// Independent of where the block sits in the source, so an unchanged
    /// block compares equal (and can be the same object) after edits above it.
    public let attributed: NSAttributedString
    private let baseHTML: String
    private let htmlLineShift: Int

    /// The block as markdown-it would emit it, `data-line` included.
    public var html: String {
        htmlLineShift == 0 ? baseHTML : Self.shiftingLines(in: baseHTML, by: htmlLineShift)
    }

    public init(
        kind: PreviewBlockKind,
        sourceRange: NSRange,
        sourceLine: Int,
        attributed: NSAttributedString,
        html: String
    ) {
        self.init(
            kind: kind,
            sourceRange: sourceRange,
            sourceLine: sourceLine,
            attributed: attributed,
            baseHTML: html,
            htmlLineShift: 0
        )
    }

    private init(
        kind: PreviewBlockKind,
        sourceRange: NSRange,
        sourceLine: Int,
        attributed: NSAttributedString,
        baseHTML: String,
        htmlLineShift: Int
    ) {
        self.kind = kind
        self.sourceRange = sourceRange
        self.sourceLine = sourceLine
        self.attributed = attributed
        self.baseHTML = baseHTML
        self.htmlLineShift = htmlLineShift
    }

    /// The same rendered block at a new place in the source. The attributed
    /// text is shared; the HTML's line numbers are rewritten when asked for.
    func moved(toLocation location: Int, line: Int) -> PreviewBlock {
        PreviewBlock(
            kind: kind,
            sourceRange: NSRange(location: location, length: sourceRange.length),
            sourceLine: line,
            attributed: attributed,
            baseHTML: baseHTML,
            htmlLineShift: htmlLineShift + (line - sourceLine)
        )
    }

    private static func shiftingLines(in html: String, by shift: Int) -> String {
        let marker = "data-line=\""
        var parts = html.components(separatedBy: marker)
        guard parts.count > 1 else { return html }
        for index in 1..<parts.count {
            let digits = parts[index].prefix { $0.isASCII && $0.isNumber }
            guard let value = Int(digits) else { continue }
            parts[index] = String(value + shift) + parts[index].dropFirst(digits.count)
        }
        return parts.joined(separator: marker)
    }
}

public struct PreviewDocument {
    public let blocks: [PreviewBlock]

    public init(blocks: [PreviewBlock]) {
        self.blocks = blocks
    }

    /// The block whose source contains `location` (UTF-16), counting the
    /// position just past its last character, so a caret at a line's end
    /// still pairs. Blank lines between blocks pair with nothing.
    public func blockIndex(containing location: Int) -> Int? {
        Self.blockIndex(in: blocks, containing: location)
    }

    public static func blockIndex(in blocks: [PreviewBlock], containing location: Int) -> Int? {
        var low = 0
        var high = blocks.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let range = blocks[mid].sourceRange
            if location < range.location {
                high = mid - 1
            } else if location > range.location + range.length {
                low = mid + 1
            } else {
                return mid
            }
        }
        return nil
    }

    /// Built on demand: it is only needed for export, not for every preview.
    public var html: String {
        blocks.map(\.html).joined()
    }

    public var attributed: NSAttributedString {
        let result = NSMutableAttributedString()
        for block in blocks {
            result.append(block.attributed)
        }
        return result
    }
}

public enum PreviewURL {
    private static let safe = try! NSRegularExpression(
        pattern: #"^(https?:|mailto:|#|/|\./|\.\./)"#,
        options: [.caseInsensitive]
    )

    public static func sanitizedLink(_ raw: String) -> String? {
        guard safe.firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) != nil else {
            return nil
        }
        return raw
    }

    public static func sanitizedImage(_ raw: String) -> String? {
        if raw.lowercased().hasPrefix("data:image/") {
            return raw
        }
        return sanitizedLink(raw)
    }

    /// markdown-it's link validator rejects these schemes before a link token
    /// is created, so the source stays literal instead of becoming `href="#"`.
    public static func markdownItRejects(_ raw: String, isImage: Bool) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("javascript:") || value.hasPrefix("vbscript:") || value.hasPrefix("file:") {
            return true
        }
        if value.hasPrefix("data:") {
            return !(isImage && value.hasPrefix("data:image/"))
        }
        return false
    }
}

public enum Typographer {
    /// markdown-it's typographer substitutions for text nodes. Order matters:
    /// three dashes before two, and ellipses before anything that could eat a dot.
    public static func transform(_ text: String) -> String {
        guard needsTransform(text) else { return text }
        var value = text
        value = value.replacingOccurrences(of: "...", with: "…")
        value = value.replacingOccurrences(of: "---", with: "—")
        value = value.replacingOccurrences(of: "--", with: "–")
        value = value.replacingOccurrences(of: "(c)", with: "©", options: .caseInsensitive)
        value = value.replacingOccurrences(of: "(r)", with: "®", options: .caseInsensitive)
        value = value.replacingOccurrences(of: "(tm)", with: "™", options: .caseInsensitive)
        value = value.replacingOccurrences(of: "+-", with: "±")
        return smartQuotes(value)
    }

    /// Every substitution needs one of `..`, `--`, `(`, `+-` or a straight
    /// quote; most text nodes have none, and skip the eight passes below.
    static func needsTransform(_ text: String) -> Bool {
        var previous: UInt8 = 0
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "("), UInt8(ascii: "\""), UInt8(ascii: "'"):
                return true
            case UInt8(ascii: "."):
                if previous == UInt8(ascii: ".") { return true }
            case UInt8(ascii: "-"):
                if previous == UInt8(ascii: "-") || previous == UInt8(ascii: "+") { return true }
            default:
                break
            }
            previous = byte
        }
        return false
    }

    private static func smartQuotes(_ text: String) -> String {
        let characters = Array(text)
        guard !characters.isEmpty else { return text }
        var result = ""
        result.reserveCapacity(characters.count)

        for (index, character) in characters.enumerated() {
            switch character {
            case "\"":
                result.append(opensQuote(characters, at: index) ? "“" : "”")
            case "'":
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                if let previous, let next, isWord(previous), isWord(next) {
                    result.append("’")
                } else {
                    result.append(opensQuote(characters, at: index) ? "‘" : "’")
                }
            default:
                result.append(character)
            }
        }
        return result
    }

    private static func opensQuote(_ characters: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = characters[index - 1]
        return previous.isWhitespace || "([{".contains(previous)
    }

    private static func isWord(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}

public struct LinkMatch: Equatable {
    public let range: NSRange
    public let url: String
    public let text: String
}

public enum Linkifier {
    private static let urlPattern = try! NSRegularExpression(
        pattern: #"\b(?:https?://|www\.)[^\s<>]+"#,
        options: [.caseInsensitive]
    )
    private static let emailPattern = try! NSRegularExpression(
        pattern: #"\b[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}\b"#
    )

    public static func matches(in text: String) -> [LinkMatch] {
        guard mightContainLink(text) else { return [] }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var matches: [LinkMatch] = []

        for match in urlPattern.matches(in: text, range: full) {
            guard let range = trimmed(match.range, in: ns) else { continue }
            let visible = ns.substring(with: range)
            let url = visible.lowercased().hasPrefix("www.") ? "http://" + visible : visible
            matches.append(LinkMatch(range: range, url: url, text: visible))
        }

        for match in emailPattern.matches(in: text, range: full) {
            guard let range = trimmed(match.range, in: ns) else { continue }
            let visible = ns.substring(with: range)
            matches.append(LinkMatch(range: range, url: "mailto:" + visible, text: visible))
        }

        return matches.sorted { $0.range.location < $1.range.location }
    }

    /// A URL match needs `://` or `www.` and an e-mail match needs `@`;
    /// without them the two regular expressions cannot match.
    static func mightContainLink(_ text: String) -> Bool {
        var colon = 0
        var slashes = 0
        var ws = 0
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "@"):
                return true
            case UInt8(ascii: ":"):
                colon = 1
                slashes = 0
                ws = 0
                continue
            case UInt8(ascii: "/"):
                if colon == 1 {
                    slashes += 1
                    if slashes == 2 { return true }
                    continue
                }
            case UInt8(ascii: "w"), UInt8(ascii: "W"):
                ws += 1
                colon = 0
                continue
            case UInt8(ascii: "."):
                if ws >= 3 { return true }
            default:
                break
            }
            colon = 0
            slashes = 0
            ws = 0
        }
        return false
    }

    private static func trimmed(_ range: NSRange, in text: NSString) -> NSRange? {
        var end = range.location + range.length
        let trailing = ".,;:!?'\""
        while end > range.location {
            let character = text.character(at: end - 1)
            guard let scalar = UnicodeScalar(character), trailing.contains(Character(scalar)) else {
                break
            }
            end -= 1
        }

        // Drop an unmatched closing bracket; keep balanced parentheses.
        while end > range.location {
            let character = text.character(at: end - 1)
            if character == 0x29 { // )
                let value = text.substring(with: NSRange(location: range.location, length: end - range.location))
                let opens = value.filter { $0 == "(" }.count
                let closes = value.filter { $0 == ")" }.count
                if closes > opens {
                    end -= 1
                    continue
                }
            }
            break
        }

        guard end > range.location else { return nil }
        return NSRange(location: range.location, length: end - range.location)
    }
}

public extension NSAttributedString {
    func ranges(of attribute: NSAttributedString.Key) -> [(NSRange, Any)] {
        var result: [(NSRange, Any)] = []
        enumerateAttribute(attribute, in: NSRange(location: 0, length: length)) { value, range, _ in
            if let value {
                result.append((range, value))
            }
        }
        return result
    }
}
