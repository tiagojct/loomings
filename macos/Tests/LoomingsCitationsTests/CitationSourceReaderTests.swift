import Foundation
import LoomingsDocuments
import Testing
@testable import LoomingsCitations

private let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/Citations")

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("loomings-reader-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let bib = "@article{a2020, author = {Ana, Rui}, title = {T}, journal = {J}, year = {2020}}\n"

private func request(
    bibliography: [String] = [],
    csl: String? = nil,
    lang: String? = nil
) -> CitationSourceRequest {
    CitationSourceRequest(bibliography: bibliography, csl: csl, lang: lang)
}

/// One engine for each test keeps the bundle load out of the other suites.
private func load(_ request: CitationSourceRequest, folder: URL?) throws -> CitationLoad {
    let engine = try CitationEngine(resources: resources)
    return try CitationSourceReader.load(request, folder: folder, engine: engine)
}

@Suite("Citation gate")
struct CitationGateTests {
    @Test("Says yes only for a key near the start of a frontmatter")
    func gate() {
        #expect(CitationGate.applies(to: "---\nbibliography: refs.bib\n---\n"))
        #expect(CitationGate.applies(to: "---\ntitle: T\nreferences: []\n---\n"))
        #expect(!CitationGate.applies(to: ""))
        #expect(!CitationGate.applies(to: "bibliography: refs.bib\n"))
        #expect(!CitationGate.applies(to: "# Title\n\n---\nbibliography: refs.bib\n---\n"))
        #expect(!CitationGate.applies(to: "---\n  bibliography: refs.bib\n---\n"))
        #expect(!CitationGate.applies(to: "---\ntitle: T\n---\nA line [@key].\n"))
    }

    @Test("Looks at the first 50 lines only")
    func limit() {
        let filler = String(repeating: "a: b\n", count: 48)
        #expect(CitationGate.applies(to: "---\n\(filler)bibliography: x\n---\n"))
        #expect(!CitationGate.applies(to: "---\n\(filler)a: b\nbibliography: x\n---\n"))
    }

    @Test("Handles a line ending in CRLF and text with no line ending")
    func lineEndings() {
        #expect(CitationGate.applies(to: "---\r\nbibliography: x\r\n---\r\n"))
        #expect(CitationGate.applies(to: "---\nreferences: []"))
        #expect(!CitationGate.applies(to: "---"))
    }
}

@Suite("Citation source reader")
struct CitationSourceReaderTests {
    @Test("Reads a bibliography next to the document, and uses the default style")
    func relative() throws {
        let folder = try temporaryFolder()
        try bib.write(to: folder.appendingPathComponent("refs.bib"), atomically: true, encoding: .utf8)
        let result = try load(request(bibliography: ["refs.bib"]), folder: folder)
        #expect(result.sources.bibs.map(\.name) == ["refs.bib"])
        #expect(result.sources.bibs.first?.text == bib)
        #expect(result.sources.styleXml?.contains("chicago") == true)
        #expect(result.sources.lang == "en-US")
        #expect(result.sources.localeXml != nil && result.sources.fallbackLocaleXml != nil)
        #expect(result.sources.missing == [])
    }

    @Test("Reads an absolute path with no folder")
    func absolute() throws {
        let folder = try temporaryFolder()
        let file = folder.appendingPathComponent("refs.bib")
        try bib.write(to: file, atomically: true, encoding: .utf8)
        let result = try load(request(bibliography: [file.path]), folder: nil)
        #expect(result.sources.bibs.first?.text == bib)
        #expect(result.sources.missing == [])
    }

    @Test("A relative name in a document with no folder is missing, and the note says why")
    func noFolder() throws {
        let result = try load(request(bibliography: ["refs.bib"]), folder: nil)
        #expect(result.sources.bibs.isEmpty)
        #expect(result.sources.missing == ["refs.bib"])
        #expect(result.sources.missingNotes?["refs.bib"]?.contains("no folder") == true)
        #expect(result.files.isEmpty)
    }

    @Test("Follows a link to a file, and stamps the target")
    func symbolicLink() throws {
        let folder = try temporaryFolder()
        let target = folder.appendingPathComponent("target.bib")
        try bib.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("refs.bib"),
            withDestinationURL: target
        )
        let result = try load(request(bibliography: ["refs.bib"]), folder: folder)
        #expect(result.sources.bibs.first?.text == bib)
        #expect(result.files.keys.map(\.lastPathComponent) == ["target.bib"])
    }

    @Test("A file that is not text gives its own note, and a device is not read")
    func unreadable() throws {
        let folder = try temporaryFolder()
        try Data([0x66, 0xE9, 0x66]).write(to: folder.appendingPathComponent("latin.bib"))
        let result = try load(request(bibliography: ["latin.bib", "/dev/zero"]), folder: folder)
        #expect(result.sources.missing == ["latin.bib", "/dev/zero"])
        #expect(result.sources.missingNotes?["latin.bib"] == "The file latin.bib could not be read as text.")
    }

    @Test("A style file next to the document wins over the bundled style")
    func styleFile() throws {
        let folder = try temporaryFolder()
        let own = try String(contentsOf: resources.appendingPathComponent("styles/ieee.csl"), encoding: .utf8)
        try own.write(to: folder.appendingPathComponent("apa.csl"), atomically: true, encoding: .utf8)
        #expect(try load(request(csl: "apa"), folder: folder).sources.styleXml == own)
        let bundled = try load(request(csl: "apa"), folder: nil).sources.styleXml
        #expect(bundled?.contains("American Psychological") == true)
    }

    @Test("Reads the parent of a dependent style, in a second round")
    func dependentParent() throws {
        let folder = try temporaryFolder()
        let dependent = """
        <?xml version="1.0" encoding="utf-8"?>
        <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0"><info><title>D</title>\
        <link href="http://www.zotero.org/styles/own-parent" rel="independent-parent"/></info></style>
        """
        let parent = try String(contentsOf: resources.appendingPathComponent("styles/ieee.csl"), encoding: .utf8)
        try dependent.write(to: folder.appendingPathComponent("dep.csl"), atomically: true, encoding: .utf8)
        try parent.write(to: folder.appendingPathComponent("own-parent.csl"), atomically: true, encoding: .utf8)
        let result = try load(request(csl: "dep.csl"), folder: folder)
        #expect(result.sources.styleXml == parent)
        #expect(result.sources.styleError == nil)
    }

    @Test("Uses the bundled style for an alias of a dependent parent")
    func dependentAlias() throws {
        let folder = try temporaryFolder()
        let dependent = """
        <style xmlns="http://purl.org/net/xbiblio/csl" version="1.0"><info><title>D</title>\
        <link href="http://www.zotero.org/styles/nlm-citation-sequence" rel="independent-parent"/></info></style>
        """
        try dependent.write(to: folder.appendingPathComponent("dep.csl"), atomically: true, encoding: .utf8)
        let result = try load(request(csl: "dep.csl"), folder: folder)
        #expect(result.sources.styleXml?.contains("Vancouver") == true)
        #expect(result.sources.styleError == nil)
    }

    @Test("Passes the style error of the plan, with the default style")
    func styleError() throws {
        let result = try load(request(csl: "nope.csl"), folder: nil)
        #expect(result.sources.styleError?.contains("nope.csl") == true)
        #expect(result.sources.styleXml?.contains("chicago") == true)
    }

    @Test("Chooses the locale with the plan")
    func locale() throws {
        let result = try load(request(lang: "pt"), folder: nil)
        #expect(result.sources.lang == "pt-PT")
        #expect(result.sources.localeXml?.contains("pt-PT") == true)
        #expect(result.sources.fallbackLocaleXml?.contains("en-US") == true)
    }

    @Test("Keeps a stamp for a file that is absent, so a new file is seen")
    func stamps() throws {
        let folder = try temporaryFolder()
        let result = try load(request(bibliography: ["refs.bib"]), folder: folder)
        let file = try #require(result.files.keys.first)
        #expect(result.files[file]?.exists == false)
        try bib.write(to: file, atomically: true, encoding: .utf8)
        #expect(result.changedFiles())
    }

    @Test("A report from the request gives the same notes as the sources say")
    func endToEnd() throws {
        let folder = try temporaryFolder()
        try bib.write(to: folder.appendingPathComponent("refs.bib"), atomically: true, encoding: .utf8)
        let engine = try CitationEngine(resources: resources)
        let source = "---\nbibliography: [refs.bib, gone.bib]\n---\nText [@a2020].\n"
        let meta = try engine.readMeta(source)
        engine.setSources(try CitationSourceReader.load(meta.sourceRequest, folder: folder, engine: engine).sources)
        let report = engine.analyse(source)
        #expect(report.markdownSource.contains("Ana"))
        #expect(report.notes.map(\.message) == ["The file gone.bib is missing."])
    }
}
