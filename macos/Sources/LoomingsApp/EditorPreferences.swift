import AppKit

enum ColumnWidth: String, CaseIterable {
    case wide
    case normal
    case narrow

    var maxWidth: CGFloat {
        switch self {
        case .wide: return 900
        case .normal: return 660
        case .narrow: return 500
        }
    }

    var label: String {
        rawValue.capitalized
    }
}

/// Persisted preferences for the native editor. Keys are namespaced so they
/// cannot collide with the web app or another native build.
enum EditorPreferences {
    private static let defaults = UserDefaults.standard

    static let minimumFontSize: CGFloat = 11
    static let maximumFontSize: CGFloat = 24
    static let wordGoals = [0, 250, 500, 750, 1000, 2000, 5000]

    private static func key(_ name: String) -> String {
        "Loomings.Native.\(name)"
    }

    static var fontSize: CGFloat {
        get {
            let stored = defaults.double(forKey: key("fontSize"))
            return stored == 0 ? 15 : min(maximumFontSize, max(minimumFontSize, stored))
        }
        set {
            defaults.set(
                min(maximumFontSize, max(minimumFontSize, newValue)),
                forKey: key("fontSize")
            )
        }
    }

    static var columnWidth: ColumnWidth {
        get {
            let raw = defaults.string(forKey: key("columnWidth")) ?? ""
            return ColumnWidth(rawValue: raw) ?? .normal
        }
        set {
            defaults.set(newValue.rawValue, forKey: key("columnWidth"))
        }
    }

    static var showLineNumbers: Bool {
        get { defaults.bool(forKey: key("showLineNumbers")) }
        set { defaults.set(newValue, forKey: key("showLineNumbers")) }
    }

    static var showStats: Bool {
        get {
            if defaults.object(forKey: key("showStats")) == nil {
                return true
            }
            return defaults.bool(forKey: key("showStats"))
        }
        set { defaults.set(newValue, forKey: key("showStats")) }
    }

    static var smartTypography: Bool {
        get {
            if defaults.object(forKey: key("smartTypography")) == nil {
                return true
            }
            return defaults.bool(forKey: key("smartTypography"))
        }
        set { defaults.set(newValue, forKey: key("smartTypography")) }
    }

    static var typewriter: Bool {
        get { defaults.bool(forKey: key("typewriter")) }
        set { defaults.set(newValue, forKey: key("typewriter")) }
    }

    static var themeFamily: String {
        get { defaults.string(forKey: key("themeFamily")) ?? "pequod" }
        set { defaults.set(newValue, forKey: key("themeFamily")) }
    }

    static var themeMode: String {
        get { defaults.string(forKey: key("themeMode")) ?? "system" }
        set { defaults.set(newValue, forKey: key("themeMode")) }
    }

    static var wordGoal: Int {
        get {
            let value = defaults.integer(forKey: key("wordGoal"))
            return wordGoals.contains(value) ? value : 0
        }
        set { defaults.set(newValue, forKey: key("wordGoal")) }
    }

    static func nextFontSize(after current: CGFloat, delta: CGFloat) -> CGFloat {
        min(maximumFontSize, max(minimumFontSize, current + delta))
    }

    static func nextColumnWidth(after width: ColumnWidth) -> ColumnWidth {
        let all = ColumnWidth.allCases
        guard let index = all.firstIndex(of: width) else { return .normal }
        return all[(index + 1) % all.count]
    }

    static func nextWordGoal(after goal: Int) -> Int {
        guard let index = wordGoals.firstIndex(of: goal) else { return 250 }
        return wordGoals[(index + 1) % wordGoals.count]
    }
}
