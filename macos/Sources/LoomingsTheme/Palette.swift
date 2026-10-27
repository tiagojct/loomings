import AppKit
import Foundation

public struct PaletteColors: Codable, Sendable, Equatable {
    public let bg: String
    public let bgElev: String
    public let bgDeep: String
    public let fg: String
    public let fgDim: String
    public let fgGhost: String
    public let accent: String
    public let accentLight: String
    public let accentDim: String
    public let border: String
    public let selection: String
    public let onAccent: String
    public let heading: String
    public let emphasis: String
    public let code: String
    public let marker: String

    public func color(_ hex: String) -> NSColor {
        NSColor(hex: hex) ?? .labelColor
    }

    public var background: NSColor { color(bg) }
    public var backgroundElevated: NSColor { color(bgElev) }
    public var backgroundDeep: NSColor { color(bgDeep) }
    public var text: NSColor { color(fg) }
    public var textDim: NSColor { color(fgDim) }
    public var textGhost: NSColor { color(fgGhost) }
    public var accentColor: NSColor { color(accent) }
    public var linkColor: NSColor { color(accentLight) }
    public var borderColor: NSColor { color(border) }
    public var selectionColor: NSColor { color(selection) }
    public var headingColor: NSColor { color(heading) }
    public var emphasisColor: NSColor { color(emphasis) }
    public var codeColor: NSColor { color(code) }
    public var markerColor: NSColor { color(marker) }
    public var onAccentColor: NSColor { color(onAccent) }
}

public struct PaletteFamily: Codable, Sendable {
    public let label: String
    public let modes: [String: String]
    public let dark: PaletteColors
    public let light: PaletteColors
}

public struct PaletteLibrary: Sendable {
    public let defaultFamily: String
    public let familyOrder: [String]
    public let families: [String: PaletteFamily]

    public init?(data: Data) {
        guard let decoded = try? JSONDecoder().decode(Stored.self, from: data) else {
            return nil
        }
        defaultFamily = decoded.defaultFamily
        familyOrder = decoded.familyOrder
        families = decoded.families
    }

    public var familyLabels: [(id: String, label: String)] {
        familyOrder.compactMap { id in
            families[id].map { (id, $0.label) }
        }
    }

    public func resolve(
        family: String,
        mode: ThemeMode,
        systemIsDark: Bool
    ) -> ResolvedPalette? {
        let familyID = families[family] != nil ? family : defaultFamily
        guard let entry = families[familyID] else { return nil }
        let effective: ThemeMode
        switch mode {
        case .system: effective = systemIsDark ? .dark : .light
        case .light, .dark: effective = mode
        }
        let colors = effective == .dark ? entry.dark : entry.light
        let modeKey = effective == .dark ? "dark" : "light"
        return ResolvedPalette(
            family: familyID,
            familyLabel: entry.label,
            mode: effective,
            modeLabel: entry.modes[modeKey] ?? effective.rawValue.capitalized,
            colors: colors,
            isDark: effective == .dark
        )
    }

    private struct Stored: Decodable {
        let defaultFamily: String
        let familyOrder: [String]
        let families: [String: PaletteFamily]
    }
}

public struct ResolvedPalette: Sendable, Equatable {
    public let family: String
    public let familyLabel: String
    public let mode: ThemeMode
    public let modeLabel: String
    public let colors: PaletteColors
    public let isDark: Bool

    public init(
        family: String,
        familyLabel: String,
        mode: ThemeMode,
        modeLabel: String,
        colors: PaletteColors,
        isDark: Bool
    ) {
        self.family = family
        self.familyLabel = familyLabel
        self.mode = mode
        self.modeLabel = modeLabel
        self.colors = colors
        self.isDark = isDark
    }
}

public enum ThemeMode: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public extension NSColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else {
            return nil
        }
        self.init(
            srgbRed: CGFloat((number >> 16) & 0xFF) / 255,
            green: CGFloat((number >> 8) & 0xFF) / 255,
            blue: CGFloat(number & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// WCAG 2 relative luminance, kept in Swift so the exported palettes can be
/// checked without the web test runner.
public enum PaletteContrast {
    public static func ratio(_ a: String, _ b: String) -> Double {
        let first = luminance(a)
        let second = luminance(b)
        let high = max(first, second)
        let low = min(first, second)
        return (high + 0.05) / (low + 0.05)
    }

    private static func luminance(_ hex: String) -> Double {
        var value = hex
        if value.hasPrefix("#") { value.removeFirst() }
        guard let number = UInt32(value, radix: 16) else { return 0 }
        let channels = [
            (number >> 16) & 0xFF,
            (number >> 8) & 0xFF,
            number & 0xFF,
        ].map { component -> Double in
            let value = Double(component) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
}
