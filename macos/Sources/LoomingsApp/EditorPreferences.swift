import LoomingsEditor
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

    /// `EditorFontChoice.rawValue`.
    static var editorFont: String {
        get { defaults.string(forKey: key("editorFont")) ?? EditorFontChoice.jetBrainsMono.rawValue }
        set { defaults.set(newValue, forKey: key("editorFont")) }
    }

    static var styledMarkdown: Bool {
        get {
            if defaults.object(forKey: key("styledMarkdown")) == nil {
                return true
            }
            return defaults.bool(forKey: key("styledMarkdown"))
        }
        set { defaults.set(newValue, forKey: key("styledMarkdown")) }
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

    // MARK: Features

    /// The References menu, the References tab and the citation engine. On by
    /// default. Off: a document with `[@key]` shows the text as typed.
    static var referencesEnabled: Bool {
        get {
            if defaults.object(forKey: key("referencesEnabled")) == nil { return true }
            return defaults.bool(forKey: key("referencesEnabled"))
        }
        set { defaults.set(newValue, forKey: key("referencesEnabled")) }
    }

    /// The file sidebar. Off by default.
    static var sidebarEnabled: Bool {
        get { defaults.bool(forKey: key("sidebarEnabled")) }
        set { defaults.set(newValue, forKey: key("sidebarEnabled")) }
    }

    /// The sidebar is a quick switcher: new windows start with it hidden. This
    /// key is for tests and snapshots; the window toggle does not write it.
    static var sidebarVisible: Bool {
        get { defaults.bool(forKey: key("sidebarVisible")) }
        set { defaults.set(newValue, forKey: key("sidebarVisible")) }
    }

    /// One folder for every window (true), or one for each window (false).
    static var sidebarSharedFolder: Bool {
        get { defaults.bool(forKey: key("sidebarSharedFolder")) }
        set { defaults.set(newValue, forKey: key("sidebarSharedFolder")) }
    }

    /// The folder of the shared sidebar, and the starting folder of a window
    /// that has no document file.
    static var sidebarFolder: URL? {
        get { defaults.string(forKey: key("sidebarFolder")).map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue?.path, forKey: key("sidebarFolder")) }
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

extension Notification.Name {
    /// A feature switch or the sidebar's folder rule changed in Settings.
    static let loomingsFeaturesChanged = Notification.Name("eu.tiagojacinto.loomings.featuresChanged")
}

/// The folder a sidebar was showing when it opened a file, so that the window
/// of that file starts on the same folder and the writer can keep browsing.
enum SidebarHandoff {
    private static var folders: [URL: URL] = [:]

    static func remember(folder: URL?, for file: URL) {
        guard let folder else { return }
        folders[file.standardizedFileURL] = folder
    }

    static func take(for file: URL?) -> URL? {
        guard let file else { return nil }
        return folders.removeValue(forKey: file.standardizedFileURL)
    }
}
