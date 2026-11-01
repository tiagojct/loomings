import AppKit

/// The editor's typeface. Stored as a preference by `rawValue`.
public enum EditorFontChoice: Equatable, Sendable {
    case jetBrainsMono
    case sourceSerif
    case sfMono
    case newYork
    case system
    /// Any installed font, by PostScript name (from the font panel).
    case custom(String)

    public static let builtIn: [EditorFontChoice] = [.jetBrainsMono, .sourceSerif, .sfMono, .newYork, .system]

    public var rawValue: String {
        switch self {
        case .jetBrainsMono: return "jetbrains-mono"
        case .sourceSerif: return "source-serif-4"
        case .sfMono: return "sf-mono"
        case .newYork: return "new-york"
        case .system: return "system"
        case .custom(let name): return "custom:\(name)"
        }
    }

    public init?(rawValue: String) {
        if rawValue.hasPrefix("custom:") {
            let name = String(rawValue.dropFirst("custom:".count))
            guard !name.isEmpty else { return nil }
            self = .custom(name)
            return
        }
        guard let match = Self.builtIn.first(where: { $0.rawValue == rawValue }) else { return nil }
        self = match
    }

    public var title: String {
        switch self {
        case .jetBrainsMono: return "JetBrains Mono"
        case .sourceSerif: return "Source Serif 4"
        case .sfMono: return "SF Mono"
        case .newYork: return "New York"
        case .system: return "System (SF Pro)"
        case .custom(let name): return NSFont(name: name, size: 12)?.displayName ?? name
        }
    }

    public func font(size: CGFloat) -> NSFont {
        let fallback = NSFont(name: "JetBrainsMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
        switch self {
        case .jetBrainsMono:
            return fallback
        case .sourceSerif:
            return NSFont(name: "SourceSerif4-Regular", size: size) ?? .systemFont(ofSize: size)
        case .sfMono:
            return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .newYork:
            let base = NSFont.systemFont(ofSize: size)
            return base.fontDescriptor.withDesign(.serif).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        case .system:
            return .systemFont(ofSize: size)
        case .custom(let name):
            return NSFont(name: name, size: size) ?? fallback
        }
    }
}

/// A face for styled text: a real bold or italic of the same family when
/// the font has one, else the regular face drawn heavier (stroke) or slanted
/// through a skewed font matrix. TextKit 2 ignores the obliqueness
/// attribute, so the slant has to live in the font.
public struct StyledFace {
    public let font: NSFont
    public let attributes: [NSAttributedString.Key: Any]

    static let drawnKeys: [NSAttributedString.Key] = [.strokeWidth]

    public static func make(base: NSFont, bold: Bool, italic: Bool) -> StyledFace {
        let manager = NSFontManager.shared
        func real(_ font: NSFont, _ trait: NSFontTraitMask, keeping kept: NSFontTraitMask = []) -> NSFont? {
            let converted = manager.convert(font, toHaveTrait: trait)
            let traits = manager.traits(of: converted)
            guard traits.contains(trait), traits.contains(kept), converted.familyName == base.familyName else { return nil }
            return converted
        }
        var font = base
        var attributes: [NSAttributedString.Key: Any] = [:]
        if bold {
            if let heavier = real(base, .boldFontMask) {
                font = heavier
            } else {
                attributes[.strokeWidth] = -3.0
            }
        }
        if italic {
            let keep: NSFontTraitMask = manager.traits(of: font).contains(.boldFontMask) ? .boldFontMask : []
            if let slanted = real(font, .italicFontMask, keeping: keep) {
                font = slanted
            } else {
                font = skewed(font)
            }
        }
        attributes[.font] = font
        return StyledFace(font: font, attributes: attributes)
    }

    /// The same face leaning about 11 degrees.
    static func skewed(_ font: NSFont) -> NSFont {
        let size = font.pointSize
        let matrix = AffineTransform(m11: size, m12: 0, m21: size * 0.2, m22: size, tX: 0, tY: 0)
        let descriptor = font.fontDescriptor.withMatrix(matrix)
        return NSFont(descriptor: descriptor, size: 0) ?? font
    }
}
