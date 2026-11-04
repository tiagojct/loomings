import Foundation
import Testing
@testable import LoomingsCitations

/// `citation-fixtures.json` comes from the web code in Node
/// (`macos/scripts/render-citation-fixtures.mjs`). These tests run the same
/// input in JavaScriptCore and expect the same output.
private struct Fixtures: Decodable {
    struct Sources: Decodable {
        let bibs: [Bib]
        let style: String?
        let styleXml: String?
        let locale: String
        let missing: [String]?
        let styleError: String?
    }

    struct Bib: Decodable {
        let name: String
        let text: String
    }

    struct Report: Decodable {
        let name: String
        let source: String
        let sources: Sources
        let report: CitationReport
    }

    struct Meta: Decodable {
        let source: String
        let meta: CitationMeta
    }

    struct Edit: Decodable {
        let source: String
        let key: String
        let value: String?
        let result: String
    }

    struct Style: Decodable {
        let xml: String
        let result: CitationStyleCheck
    }

    let reports: [Report]
    let meta: [Meta]
    let edits: [Edit]
    let styles: [Style]

    static func load() throws -> Fixtures {
        let url = try #require(Bundle.module.url(forResource: "citation-fixtures", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }
}

/// `Bundle.main` does not hold the resources in `swift test`.
private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Citations")

/// A resources folder with only a bundle in it, to give the engine a script
/// that fails in a known way.
private func folder(bundle: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("loomings-citations-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try bundle.write(to: url.appendingPathComponent("citations.js"), atomically: true, encoding: .utf8)
    return url
}

private let emptyReportJSON = #"{"citations":[],"bibliography":[],"bibliographyMarkdown":"","library":[],"notes":[],"markdownSource":"from the script"}"#

private func expectEqual(_ actual: CitationReport, _ expected: CitationReport, _ name: String) {
    let comment = Comment(rawValue: name)
    #expect(actual.citations == expected.citations, comment)
    #expect(actual.bibliography == expected.bibliography, comment)
    #expect(actual.bibliographyMarkdown == expected.bibliographyMarkdown, comment)
    #expect(actual.library == expected.library, comment)
    #expect(actual.notes == expected.notes, comment)
    #expect(actual.markdownSource == expected.markdownSource, comment)
}

@Suite("Citation engine")
struct CitationEngineTests {
    @Test("Gives the report of the web code for each fixture")
    func reportsMatchTheWeb() throws {
        let fixtures = try Fixtures.load()
        // One engine for all cases: a change of sources must not leave a trace.
        let engine = try CitationEngine(resources: resources)
        for fixture in fixtures.reports {
            let bundled = fixture.sources.style.flatMap(engine.bundledStyle)
            let styleXml = try #require(fixture.sources.styleXml ?? bundled)
            let locale = engine.bundledLocale(fixture.sources.locale)
            let fallback = engine.bundledLocale("en-US")
            #expect(locale != nil && fallback != nil)
            engine.setSources(CitationSources(
                bibs: fixture.sources.bibs.map { CitationSources.Bib(name: $0.name, text: $0.text) },
                styleXml: styleXml,
                localeXml: locale,
                fallbackLocaleXml: fallback,
                lang: fixture.sources.locale,
                missing: fixture.sources.missing,
                styleError: fixture.sources.styleError
            ))
            expectEqual(engine.analyse(fixture.source), fixture.report, fixture.name)
        }
    }

    @Test("The fixture holds what the citation code must give")
    func fixtureHasContent() throws {
        let fixtures = try Fixtures.load()
        let apa = try #require(fixtures.reports.first { $0.name == "apa-en-US" }).report
        #expect(apa.citations.first?.html == "(Jácome et al., 2020)")
        let portuguese = try #require(fixtures.reports.first { $0.name == "vancouver-pt-PT" }).report
        #expect(portuguese.bibliography.first?.contains("Em: Costa R, editor.") == true)
        let broken = try #require(fixtures.reports.first { $0.name == "broken-entry" }).report
        let note = try #require(broken.notes.first)
        #expect(note.file == "broken.bib")
        #expect(note.line == 6)
        #expect(broken.notes.last?.file == nil)
        #expect(broken.notes.last?.line == nil)
    }

    @Test("Offsets count UTF-16 units, as in NSString")
    func offsetsAreUTF16() throws {
        let fixtures = try Fixtures.load()
        let fixture = try #require(fixtures.reports.first { $0.name == "apa-en-US" })
        let source = fixture.source as NSString
        let first = try #require(fixture.report.citations.first)
        #expect(source.substring(with: NSRange(location: first.from, length: first.to - first.from)) == "[@jacome2020]")
    }

    @Test("Reads and changes the frontmatter, and checks a style, as the web code does")
    func helpersMatchTheWeb() throws {
        let fixtures = try Fixtures.load()
        let engine = try CitationEngine(resources: resources)
        for fixture in fixtures.meta {
            #expect(try engine.readMeta(fixture.source) == fixture.meta)
        }
        for fixture in fixtures.edits {
            #expect(try engine.setMeta(fixture.source, key: fixture.key, value: fixture.value) == fixture.result)
        }
        for fixture in fixtures.styles {
            #expect(try engine.checkStyle(fixture.xml) == fixture.result)
        }
    }

    @Test("Decodes the fields of the frontmatter")
    func metaFields() throws {
        let fixtures = try Fixtures.load()
        let meta = fixtures.meta[2].meta
        #expect(meta.bibliography == ["a.bib", "b.bib"])
        #expect(meta.referenceCount == 1)
        #expect(meta.referencesDropped == 1)
    }

    @Test("A value that setCitationMeta refuses is an error and the engine goes on")
    func setMetaRefusesALineBreak() throws {
        let engine = try CitationEngine(resources: resources)
        #expect(throws: CitationEngineError.self) {
            try engine.setMeta("Body.\n", key: "csl", value: "a\nb")
        }
        #expect(try engine.setMeta("---\ncsl: apa\n---\n", key: "csl", value: nil) == "---\n---\n")
    }

    @Test("A folder with no bundle is an error at init")
    func missingBundle() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-citations-\(UUID().uuidString)")
        #expect(throws: CitationEngineError.self) {
            _ = try CitationEngine(resources: empty)
        }
    }

    @Test("The bundle loads on the first use, not at init")
    func loadsLazily() throws {
        let url = try folder(bundle: "this is not JavaScript (")
        let engine = try CitationEngine(resources: url)
        // A loaded bundle would be the broken one.
        try """
        var LoomingsCitations = { analyse() { return JSON.stringify(\(emptyReportJSON)); } };
        """.write(to: url.appendingPathComponent("citations.js"), atomically: true, encoding: .utf8)
        let report = engine.analyse("Text.\n")
        #expect(report.notes.isEmpty)
        #expect(report.markdownSource == "from the script")
    }

    @Test("A JavaScript exception gives an empty report with a note, and the context survives")
    func exceptionGivesANote() throws {
        let url = try folder(bundle: """
        var calls = 0;
        var LoomingsCitations = {
          analyse() {
            calls += 1;
            if (calls === 1) throw new Error('the first call fails');
            return JSON.stringify(\(emptyReportJSON));
          },
        };
        """)
        let engine = try CitationEngine(resources: url)

        let failed = engine.analyse("Text [@a].\n")
        #expect(failed.citations.isEmpty)
        #expect(failed.bibliography.isEmpty)
        #expect(failed.markdownSource == "Text [@a].\n")
        #expect(failed.notes.count == 1)
        #expect(failed.notes.first?.message.contains("the first call fails") == true)

        let next = engine.analyse("Text [@a].\n")
        #expect(next.notes.isEmpty)
        #expect(next.markdownSource == "from the script")
    }

    @Test("A script error in setSources gives the note until the next good setSources")
    func setSourcesFailure() throws {
        let url = try folder(bundle: """
        var calls = 0;
        var LoomingsCitations = {
          setSources() {
            calls += 1;
            if (calls === 1) throw new Error('bad sources');
          },
          analyse() { return JSON.stringify(\(emptyReportJSON)); },
        };
        """)
        let engine = try CitationEngine(resources: url)
        engine.setSources(CitationSources())
        #expect(engine.analyse("Text.\n").notes.first?.message.contains("bad sources") == true)
        engine.setSources(CitationSources())
        #expect(engine.analyse("Text.\n").notes.isEmpty)
    }

    @Test("Output that is not a report gives a note")
    func badOutput() throws {
        let url = try folder(bundle: """
        var LoomingsCitations = { analyse(source) { return source === 'a' ? 'not json' : undefined; } };
        """)
        let engine = try CitationEngine(resources: url)
        #expect(engine.analyse("a").notes.count == 1)
        #expect(engine.analyse("b").notes.count == 1)
    }

    @Test("A bundle that does not evaluate gives the note on each call")
    func bundleFailure() throws {
        let url = try folder(bundle: "this is not JavaScript (")
        let engine = try CitationEngine(resources: url)
        engine.setSources(CitationSources())
        for source in ["One [@a].\n", "Two [@b].\n"] {
            let report = engine.analyse(source)
            #expect(report.citations.isEmpty)
            #expect(report.markdownSource == source)
            #expect(report.notes.count == 1)
            #expect(report.notes.first?.message.isEmpty == false)
        }
        #expect(throws: CitationEngineError.self) { try engine.readMeta("Text.\n") }
        #expect(throws: CitationEngineError.self) { try engine.setMeta("Text.\n", key: "csl", value: "apa") }
        #expect(throws: CitationEngineError.self) { try engine.checkStyle("<style/>") }
    }

    @Test("A bundle with no LoomingsCitations gives the note")
    func bundleWithoutTheGlobal() throws {
        let engine = try CitationEngine(resources: try folder(bundle: "var other = 1;"))
        #expect(engine.analyse("Text.\n").notes.count == 1)
    }

    @Test("Calls from many threads stay in one context")
    func callsFromManyThreads() throws {
        let url = try folder(bundle: """
        var depth = 0;
        var LoomingsCitations = {
          analyse(source) {
            depth += 1;
            var seen = depth;
            for (var i = 0; i < 100000; i++) { if (depth !== seen) throw new Error('two calls at once'); }
            depth -= 1;
            return JSON.stringify({citations: [], bibliography: [], bibliographyMarkdown: '', library: [], notes: [], markdownSource: source});
          },
        };
        """)
        let engine = try CitationEngine(resources: url)
        DispatchQueue.concurrentPerform(iterations: 32) { index in
            let source = "Text \(index)"
            let report = engine.analyse(source)
            #expect(report.notes.isEmpty)
            #expect(report.markdownSource == source)
        }
    }

    @Test("A long bibliography works on the stack of a background thread")
    func longBibliography() throws {
        let engine = try CitationEngine(resources: resources)
        let bib = (0..<200).map {
            "@article{key\($0),\n  author = {Author\($0), Ana and Other, Rui},\n"
                + "  title = {Entry number \($0)},\n  journal = {Journal},\n  year = {\(1900 + $0)}\n}"
        }.joined(separator: "\n")
        let cited = (0..<60).map { "A sentence [@key\($0 * 3)]." }.joined(separator: "\n\n")
        let source = "---\nbibliography: long.bib\n---\n\(cited)\n"
        let style = try #require(engine.bundledStyle("apa"))
        let locale = try #require(engine.bundledLocale("en-US"))
        let box = ReportBox()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            engine.setSources(CitationSources(
                bibs: [.init(name: "long.bib", text: bib)],
                styleXml: style,
                localeXml: locale,
                fallbackLocaleXml: locale,
                lang: "en-US"
            ))
            box.report = engine.analyse(source)
            done.signal()
        }
        done.wait()
        let report = try #require(box.report)
        #expect(report.notes.isEmpty)
        #expect(report.library.count == 200)
        #expect(report.citations.count == 60)
        #expect(report.citations.allSatisfy { $0.markdown.contains("Author") })
    }

    @Test("Gives nil for a bundled file that does not exist")
    func unknownBundledFile() throws {
        let engine = try CitationEngine(resources: resources)
        #expect(engine.bundledStyle("nowhere") == nil)
        #expect(engine.bundledLocale("xx-XX") == nil)
        #expect(engine.bundledStyle("../citations") == nil)
    }
}

private final class ReportBox: @unchecked Sendable {
    var report: CitationReport?
}
