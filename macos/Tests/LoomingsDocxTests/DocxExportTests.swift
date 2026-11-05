import Foundation
import Testing
@testable import LoomingsDocx

private struct Package {
    let url: URL

    init(_ data: Data) throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("docx-test-\(UUID().uuidString).docx")
        try data.write(to: url)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }

    /// Runs /usr/bin/unzip. `-t` also checks each CRC.
    func unzip(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments + [url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func part(_ name: String) -> String {
        // unzip reads the pattern as a glob: brackets need a backslash.
        let escaped = name.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, escaped]
        let pipe = Pipe()
        process.standardOutput = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

private func export(_ markdown: String, bibliography: String = "") throws -> Package {
    try Package(DocxExport.data(markdown: markdown, bibliographyMarkdown: bibliography, documentURL: nil, paper: .a4))
}

@Suite struct DocxExportTests {
    @Test func packageIsValidZip() throws {
        let package = try export("# Title\n\nText with **bold** and *italic*.\n")
        defer { package.remove() }
        let result = package.unzip(["-t"])
        #expect(result.status == 0, "\(result.output)")
        #expect(result.output.contains("word/document.xml"))
        #expect(result.output.contains("word/styles.xml"))
    }

    @Test func usesWordStyleIds() throws {
        let package = try export("# One\n\n> quoted\n\n```\ncode\n```\n")
        defer { package.remove() }
        let document = package.part("word/document.xml")
        #expect(document.contains("w:pStyle w:val=\"Heading1\""))
        #expect(document.contains("w:pStyle w:val=\"Quote\""))
        #expect(document.contains("w:pStyle w:val=\"SourceCode\""))
        let styles = package.part("word/styles.xml")
        for id in ["Title", "Heading1", "Heading6", "Quote", "Bibliography", "SourceCode", "Hyperlink", "TableGrid"] {
            #expect(styles.contains("w:styleId=\"\(id)\""), "\(id)")
        }
    }

    @Test func listsRestartAndNest() throws {
        let package = try export("1. a\n2. b\n\ntext\n\n3. c\n\n- x\n  - y\n")
        defer { package.remove() }
        let document = package.part("word/document.xml")
        let regex = try NSRegularExpression(pattern: "<w:numId w:val=\"(\\d+)\"")
        let ns = document as NSString
        let ids = Set(regex.matches(in: document, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
        #expect(ids.count == 3)
        #expect(document.contains("<w:ilvl w:val=\"1\"/>"))
        #expect(package.part("word/numbering.xml").contains("<w:start w:val=\"3\"/>"))
    }

    @Test func linksTablesAndEscaping() throws {
        let package = try export("[site](https://example.org) and `a<b` & more\n\n| a | b |\n|---|--:|\n| 1 | 2 |\n")
        defer { package.remove() }
        let document = package.part("word/document.xml")
        #expect(document.contains("<w:hyperlink r:id="))
        #expect(package.part("word/_rels/document.xml.rels").contains("https://example.org"))
        #expect(document.contains("a&lt;b"))
        #expect(document.contains("&amp; more"))
        #expect(document.contains("<w:tbl>"))
        #expect(document.contains("<w:tblHeader/>"))
        #expect(document.contains("<w:jc w:val=\"right\"/>"))
    }

    @Test func unsafeLinkIsText() throws {
        let package = try export("[bad](javascript:alert(1))\n")
        defer { package.remove() }
        #expect(!package.part("word/_rels/document.xml.rels").contains("javascript"))
        #expect(package.part("word/document.xml").contains("bad"))
    }

    @Test func frontmatterGivesTitleAndLanguage() throws {
        let package = try export("---\ntitle: My paper\nlang: pt-PT\n---\n\n# Intro\n")
        defer { package.remove() }
        #expect(package.part("word/document.xml").contains("w:pStyle w:val=\"Title\""))
        #expect(package.part("word/styles.xml").contains("w:val=\"pt-PT\""))
        #expect(package.part("docProps/core.xml").contains("My paper"))
        #expect(!package.part("word/document.xml").contains("lang: pt-PT"))
    }

    @Test func titleIsNotRepeatedByTheSameHeading() throws {
        let package = try export("---\ntitle: My paper\n---\n\n# My paper\n")
        defer { package.remove() }
        #expect(!package.part("word/document.xml").contains("w:pStyle w:val=\"Title\""))
    }

    @Test func referenceListUsesBibliographyStyle() throws {
        let bibliography = "Miller M. *Spirometry*. 2005.\n\nWest J. *Physiology*. 2012."
        let package = try export("Text [1].\n\n## References\n\n" + bibliography, bibliography: bibliography)
        defer { package.remove() }
        let document = package.part("word/document.xml")
        #expect(document.components(separatedBy: "w:pStyle w:val=\"Bibliography\"").count - 1 == 2)
        #expect(document.contains("Miller M."))
        #expect(document.contains("w:pStyle w:val=\"Heading2\""))
    }

    @Test func missingImageFallsBackToText() throws {
        let package = try export("![a dot](nothing.png)\n")
        defer { package.remove() }
        #expect(package.part("word/document.xml").contains("[image: a dot]"))
    }

    @Test func embedsALocalImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("docx-img-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        try png.write(to: folder.appendingPathComponent("dot.png"))
        let data = DocxExport.data(markdown: "![dot](dot.png)\n", documentURL: folder.appendingPathComponent("doc.md"), paper: .letter)
        let package = try Package(data)
        defer { package.remove() }
        #expect(package.unzip(["-l"]).output.contains("word/media/image1.png"))
        let document = package.part("word/document.xml")
        #expect(document.contains("<w:drawing>"))
        #expect(document.contains("w:w=\"12240\""))
    }

    @Test func largeTextSurvivesDeflate() throws {
        let line = "Spirometry is standardised by joint guidelines. "
        let package = try export(String(repeating: line + "\n\n", count: 2000))
        defer { package.remove() }
        #expect(package.unzip(["-t"]).status == 0)
    }
}
