import Foundation
import Testing
@testable import LoomingsCitations

/// `filters` in `citation-fixtures.json` comes from `filterLibrary` in
/// `src/citations/panel.js`.
private struct FilterFixtures: Decodable {
    struct Entry: Decodable {
        let key: String
        let authors: String
        let year: String
        let title: String
    }

    struct Case: Decodable {
        let query: String
        let keys: [String]
    }

    struct Filters: Decodable {
        let library: [Entry]
        let cases: [Case]
    }

    let filters: Filters

    static func load() throws -> Filters {
        let url = try #require(Bundle.module.url(forResource: "citation-fixtures", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(FilterFixtures.self, from: Data(contentsOf: url)).filters
    }
}

private func entry(_ key: String, authors: String = "", year: String = "", title: String = "", cited: Bool = false) -> CitationReport.LibraryEntry {
    CitationReport.LibraryEntry(key: key, authors: authors, year: year, title: title, cited: cited)
}

private func report(library: [CitationReport.LibraryEntry], missing: [[String]] = []) -> CitationReport {
    CitationReport(
        citations: missing.map { CitationReport.Citation(from: 0, to: 0, html: "", markdown: "", missing: $0) },
        bibliography: [],
        bibliographyMarkdown: "",
        library: library,
        notes: [],
        markdownSource: ""
    )
}

@Suite("The list of the References view")
struct ReferenceListTests {
    @Test("Gives the keys of the web filter for each fixture")
    func webFilter() throws {
        let filters = try FilterFixtures.load()
        let list = ReferenceList(report: report(library: filters.library.map {
            entry($0.key, authors: $0.authors, year: $0.year, title: $0.title)
        }))
        #expect(!filters.cases.isEmpty)
        for fixture in filters.cases {
            #expect(list.rows(filter: fixture.query).map(\.key) == fixture.keys, "query: \(fixture.query)")
        }
    }

    @Test("A cited key with no entry goes first, once, in the order of the text")
    func missingFirst() {
        let list = ReferenceList(report: report(
            library: [entry("smith2019", authors: "Smith", year: "2019", title: "A book", cited: true)],
            missing: [["zeta"], ["alpha", "zeta"], ["smith2019"]]
        ))
        let rows = list.rows(filter: "")
        #expect(rows.map(\.key) == ["zeta", "alpha", "smith2019"])
        #expect(rows.map(\.isMissing) == [true, true, false])
        #expect(rows[2].byline == "Smith, 2019")
        #expect(rows[2].title == "A book")
        #expect(rows[2].isCited)
    }

    @Test("The filter also looks at a missing key")
    func filterMissing() {
        let list = ReferenceList(report: report(library: [entry("smith2019")], missing: [["alpha"]]))
        #expect(list.rows(filter: "ALPHA").map(\.key) == ["alpha"])
    }

    @Test("A byline holds only the parts it has")
    func byline() {
        let list = ReferenceList(report: report(library: [entry("a", year: "2001"), entry("b", authors: "Silva"), entry("c")]))
        #expect(list.rows(filter: "").map(\.byline) == ["2001", "Silva", ""])
    }

    @Test("No report gives an empty list")
    func noReport() {
        let list = ReferenceList(report: nil)
        #expect(list.isEmpty)
        #expect(list.rows(filter: "x").isEmpty)
    }
}

/// `Bundle.main` does not hold the resources in `swift test`.
private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Citations")

@Suite("The bundled choices of the References menu")
struct CitationMenuChoicesTests {
    @Test("The list from the web code names the files of the bundle")
    func list() throws {
        let choices = try CitationMenuChoices(resources: resources)
        #expect(choices.styles.first?.title == "Chicago (author-date)")
        #expect(choices.languages.map(\.id) == ["en-US", "en-GB", "pt-PT", "es-ES"])
        #expect(choices.languages.map(\.label).contains("Português (Portugal)"))
        let engine = try CitationEngine(resources: resources)
        for style in choices.styles {
            #expect(engine.bundledStyle(style.id) != nil, "style: \(style.id)")
        }
        for language in choices.languages {
            #expect(engine.bundledLocale(language.id) != nil, "language: \(language.id)")
        }
    }

    @Test("A folder with no list is an error")
    func noList() {
        #expect(throws: (any Error).self) {
            try CitationMenuChoices(resources: URL(fileURLWithPath: "/nonexistent"))
        }
    }
}

@Suite("The edits of the References menu")
struct ReferenceEditTests {
    @Test("The first file makes the frontmatter, and a second file gives a flow list")
    func addBibliography() throws {
        let engine = try CitationEngine(resources: resources)
        let first = try engine.addBibliography("Body.\n", path: "refs.bib")
        #expect(first == "---\nbibliography: refs.bib\n---\nBody.\n")
        let second = try engine.addBibliography(first, path: "../shared/more.bib")
        #expect(second == "---\nbibliography: [refs.bib, ../shared/more.bib]\n---\nBody.\n")
        #expect(try engine.readMeta(second).bibliography == ["refs.bib", "../shared/more.bib"])
    }

    @Test("A file that is in the list changes nothing")
    func sameFile() throws {
        let engine = try CitationEngine(resources: resources)
        let text = "---\nbibliography:\n  - refs.bib\n---\nBody.\n"
        #expect(try engine.addBibliography(text, path: "refs.bib") == text)
    }

    @Test("The checked items follow the frontmatter")
    func choices() throws {
        let engine = try CitationEngine(resources: resources)
        #expect(try engine.referenceChoices("Body.\n") == CitationChoices(style: "chicago-author-date", language: "en-US"))
        #expect(try engine.referenceChoices("---\ncsl: apa\nlang: pt\n---\n") == CitationChoices(style: "apa", language: "pt-PT"))
        #expect(try engine.referenceChoices("---\ncsl: journal.csl\n---\n") == CitationChoices(style: nil, language: "en-US"))
    }

    @Test("Inserts by the rule of the web")
    func insertion() throws {
        let engine = try CitationEngine(resources: resources)
        #expect(try engine.insertCitation("Text.", position: 4, key: "a") == CitationInsertion(insert: "[@a]", from: 4))
        #expect(try engine.insertCitation("See [@b] here.", position: 6, key: "a") == CitationInsertion(insert: "; @a", from: 7))
        #expect(try engine.insertCitation("---\nbibliography: r.bib\n---\nBody.\n", position: 0, key: "a") == CitationInsertion(insert: "[@a]\n\n", from: 28))
    }

    @Test("Positions count UTF-16 units")
    func utf16() throws {
        let engine = try CitationEngine(resources: resources)
        let text = "🫁 See [@b] here."
        let position = (text as NSString).range(of: "@b").location
        #expect(try engine.insertCitation(text, position: position + 1, key: "a") == CitationInsertion(insert: "; @a", from: position + 2))
    }

    @Test("A refused edit gives its reason, in plain words")
    func refused() throws {
        let engine = try CitationEngine(resources: resources)
        let text = "---\n" + String(repeating: "x: 1\n", count: 48) + "---\n"
        #expect(throws: CitationEngineError.refused("A new key would move the closing --- past line 50.")) {
            try engine.setMeta(text, key: "csl", value: "a.csl")
        }
    }
}
