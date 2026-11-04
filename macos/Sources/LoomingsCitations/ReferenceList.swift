import Foundation

/// One row of the References view.
public struct ReferenceRow: Equatable, Sendable {
    public let key: String
    /// The authors and the year.
    public let byline: String
    public let title: String
    public let isCited: Bool
    /// The text cites this key, and the library has no entry for it.
    public let isMissing: Bool
}

/// The rows of the References view for one report. This is `renderLibrary`
/// and `filterLibrary` of `src/citations/panel.js`. The filter runs on each
/// key, so it does not go through the citation queue. The fixture `filters`
/// keeps the two the same.
public struct ReferenceList: Equatable, Sendable {
    private struct Item: Equatable, Sendable {
        let row: ReferenceRow
        let search: String
    }

    private let items: [Item]

    public init(report: CitationReport?) {
        let library = report?.library ?? []
        let known = Set(library.map(\.key))
        var seen = Set<String>()
        var missing: [String] = []
        for key in (report?.citations ?? []).flatMap(\.missing) where !known.contains(key) && seen.insert(key).inserted {
            missing.append(key)
        }
        items = missing.map {
            Item(
                row: ReferenceRow(key: $0, byline: "", title: "", isCited: true, isMissing: true),
                search: Self.fold($0)
            )
        } + library.map {
            Item(
                row: ReferenceRow(
                    key: $0.key,
                    byline: [$0.authors, $0.year].filter { !$0.isEmpty }.joined(separator: ", "),
                    title: $0.title,
                    isCited: $0.cited,
                    isMissing: false
                ),
                search: Self.fold("\($0.key) \($0.authors) \($0.year) \($0.title)")
            )
        }
    }

    public var isEmpty: Bool { items.isEmpty }

    /// The library has no entry: at most it has cited keys with no entry.
    public var hasNoEntries: Bool { items.allSatisfy(\.row.isMissing) }

    /// The rows with every word of `filter`. Accents and case do not count.
    public func rows(filter: String) -> [ReferenceRow] {
        let words = Self.fold(filter).split(whereSeparator: \.isWhitespace).map(String.init)
        if words.isEmpty { return items.map(\.row) }
        return items.filter { item in
            words.allSatisfy { item.search.range(of: $0, options: .literal) != nil }
        }.map(\.row)
    }

    /// `foldText` of `src/accents.js`.
    private static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.decomposedStringWithCanonicalMapping.unicodeScalars.filter {
            $0.properties.generalCategory != .nonspacingMark
        })
        return String(scalars).lowercased()
    }
}

/// The bundled styles and languages for the menu, from `styles.json`. The
/// export script writes this list from `src/citations/style.js`.
public struct CitationMenuChoices: Decodable, Sendable, Equatable {
    public struct Style: Decodable, Sendable, Equatable {
        public let id: String
        public let title: String
    }

    public struct Language: Decodable, Sendable, Equatable {
        public let id: String
        public let label: String
    }

    public let styles: [Style]
    public let languages: [Language]

    /// - Parameter resources: the folder that holds `styles.json`.
    public init(resources: URL) throws {
        let data = try Data(contentsOf: resources.appendingPathComponent("styles.json"))
        self = try JSONDecoder().decode(Self.self, from: data)
    }
}

/// The checked items of the References menu.
public struct CitationChoices: Decodable, Sendable, Equatable {
    /// A bundled style, or nil for a style file.
    public let style: String?
    public let language: String?

    public init(style: String?, language: String?) {
        self.style = style
        self.language = language
    }
}

/// The result of `insertCitation`: the text to insert at `from`.
public struct CitationInsertion: Decodable, Sendable, Equatable {
    public let insert: String
    public let from: Int

    public init(insert: String, from: Int) {
        self.insert = insert
        self.from = from
    }
}
