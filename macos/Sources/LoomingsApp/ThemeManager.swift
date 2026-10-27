import AppKit
import Foundation
import LoomingsTheme

@MainActor
final class ThemeManager {
    static let shared = ThemeManager()

    let library: PaletteLibrary?
    var onChange: (() -> Void)?

    private init() {
        if let url = Bundle.main.url(forResource: "palettes", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            library = PaletteLibrary(data: data)
        } else {
            library = nil
        }
    }

    var family: String {
        get {
            let stored = EditorPreferences.themeFamily
            if library?.families[stored] != nil {
                return stored
            }
            return library?.defaultFamily ?? stored
        }
        set {
            EditorPreferences.themeFamily = newValue
        }
    }

    var mode: ThemeMode {
        get { ThemeMode(rawValue: EditorPreferences.themeMode) ?? .system }
        set { EditorPreferences.themeMode = newValue.rawValue }
    }

    func resolved() -> ResolvedPalette? {
        library?.resolve(
            family: family,
            mode: mode,
            systemIsDark: systemIsDark
        )
    }

    func applyAppearance() {
        switch mode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func refreshForSystemAppearance() {
        guard mode == .system else { return }
        onChange?()
    }

    private var systemIsDark: Bool {
        let match = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .darkAqua
    }
}
