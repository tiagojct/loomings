import Foundation

/// The one output of the citation code: the field names of `CitationReport`
/// in `src/citations/session.js`. All offsets are UTF-16, as in `NSString`.
public struct CitationReport: Decodable, Sendable, Equatable {
    public struct Citation: Decodable, Sendable, Equatable {
        public let from: Int
        public let to: Int
        public let html: String
        public let markdown: String
        public let missing: [String]
    }

    public struct LibraryEntry: Decodable, Sendable, Equatable {
        public let key: String
        public let authors: String
        public let year: String
        public let title: String
        public let cited: Bool
    }

    /// A note about a file has `from` and `to` 0, `line` from 0, and `file`
    /// when a file is named.
    public struct Note: Decodable, Sendable, Equatable {
        public let from: Int
        public let to: Int
        public let message: String
        public let file: String?
        public let line: Int?
    }

    public let citations: [Citation]
    public let bibliography: [String]
    public let bibliographyMarkdown: String
    public let library: [LibraryEntry]
    public let notes: [Note]
    public let markdownSource: String
}

/// What `setSources` takes: the fields of `CitationSources` in
/// `src/citations/session.js`. A nil field stays out of the JSON.
public struct CitationSources: Encodable, Sendable {
    public struct Bib: Encodable, Sendable {
        public var name: String
        public var text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public var bibs: [Bib]
    public var styleXml: String?
    public var localeXml: String?
    public var fallbackLocaleXml: String?
    public var lang: String?
    public var missing: [String]?
    public var styleError: String?

    public init(
        bibs: [Bib] = [],
        styleXml: String? = nil,
        localeXml: String? = nil,
        fallbackLocaleXml: String? = nil,
        lang: String? = nil,
        missing: [String]? = nil,
        styleError: String? = nil
    ) {
        self.bibs = bibs
        self.styleXml = styleXml
        self.localeXml = localeXml
        self.fallbackLocaleXml = fallbackLocaleXml
        self.lang = lang
        self.missing = missing
        self.styleError = styleError
    }
}

/// The citation keys of the leading frontmatter (`readCitationMeta`).
public struct CitationMeta: Decodable, Sendable, Equatable {
    public let bibliography: [String]
    public let csl: String?
    public let lang: String?
    public let title: String?
    /// The count of usable entries in `references`. The session reads the
    /// entries from the text, so Swift does not hold them.
    public let referenceCount: Int
    /// The entries removed because they have no text id, or -1 when the
    /// value of `references` is not a JSON list.
    public let referencesDropped: Int

    private enum CodingKeys: String, CodingKey {
        case bibliography, csl, lang, title, references, referencesDropped
    }

    private struct AnyEntry: Decodable {
        init(from decoder: Decoder) throws {}
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bibliography = try container.decode([String].self, forKey: .bibliography)
        csl = try container.decodeIfPresent(String.self, forKey: .csl)
        lang = try container.decodeIfPresent(String.self, forKey: .lang)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        referenceCount = try container.decode([AnyEntry].self, forKey: .references).count
        referencesDropped = try container.decode(Int.self, forKey: .referencesDropped)
    }
}

/// The result of `checkStyle`. When `ok` is true, `title` holds the title.
/// When it is false, `reason` is "invalid" or "dependent", and `parent` can
/// name the parent style.
public struct CitationStyleCheck: Decodable, Sendable, Equatable {
    public let ok: Bool
    public let title: String?
    public let reason: String?
    public let parent: String?
}
