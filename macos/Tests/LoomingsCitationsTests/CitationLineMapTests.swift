import Foundation
import Testing
@testable import LoomingsCitations

private func location(of text: String, in whole: String) -> Int {
    (whole as NSString).range(of: text).location
}

@Suite("Citation line map")
struct CitationLineMapTests {
    private let source = "# Title\n\nA claim [@key] here.\n\nNext line.\n"
    private let markdown = "# Title\n\nA claim (Silva 2020, with a long note) here.\n\nNext line.\n\nSilva, Ana. 2020.\n"

    @Test("A longer citation moves the later offsets, and pairing stays on the line")
    func longer() {
        let map = CitationLineMap(source: source, markdown: markdown)
        let next = location(of: "Next", in: source)
        #expect(map.markdownLocation(forSource: next) == location(of: "Next", in: markdown))
        let block = NSRange(location: location(of: "Next", in: markdown), length: 10)
        #expect(map.sourceRange(forMarkdown: block) == NSRange(location: next, length: 10))
    }

    @Test("A shorter citation also keeps the line")
    func shorter() {
        let long = "A [see @one; @two; @three, p. 12] b.\nNext.\n"
        let short = "A (1) b.\nNext.\n"
        let map = CitationLineMap(source: long, markdown: short)
        #expect(map.markdownLocation(forSource: location(of: "Next", in: long)) == location(of: "Next", in: short))
        // A column past the end of the shorter line stays inside that line.
        #expect(map.markdownLocation(forSource: 30) == 8)
    }

    @Test("A citation over two lines keeps the line numbers after it")
    func twoLines() {
        let split = "A [@one;\n@two] b.\nNext.\n"
        let joined = "A (1, 2)\n b.\nNext.\n"
        let map = CitationLineMap(source: split, markdown: joined)
        let next = location(of: "Next", in: split)
        #expect(map.markdownLocation(forSource: next) == location(of: "Next", in: joined))
        let block = NSRange(location: 0, length: location(of: "Next", in: joined) - 1)
        #expect(map.sourceRange(forMarkdown: block) == NSRange(location: 0, length: next - 1))
    }

    @Test("The reference list has no source")
    func referenceList() {
        let map = CitationLineMap(source: source, markdown: markdown)
        let entry = NSRange(location: location(of: "Silva, Ana", in: markdown), length: 17)
        #expect(map.sourceRange(forMarkdown: entry) == nil)
    }

    @Test("A source with no final line break")
    func noFinalBreak() {
        let bare = "One [@a]\n\nTwo"
        let formatted = "One (A 2020)\n\nTwo\n\nA. 2020."
        let map = CitationLineMap(source: bare, markdown: formatted)
        let two = location(of: "Two", in: bare)
        #expect(map.markdownLocation(forSource: two + 3) == location(of: "Two", in: formatted) + 3)
        let last = NSRange(location: location(of: "Two", in: formatted), length: 3)
        #expect(map.sourceRange(forMarkdown: last) == NSRange(location: two, length: 3))
        let entry = NSRange(location: location(of: "A. 2020.", in: formatted), length: 8)
        #expect(map.sourceRange(forMarkdown: entry) == nil)
    }

    @Test("Offsets count UTF-16 units")
    func utf16() {
        let emoji = "\u{1F30A} [@a]\nNext\n"
        let formatted = "\u{1F30A} (A 2020)\nNext\n"
        let map = CitationLineMap(source: emoji, markdown: formatted)
        #expect(map.markdownLocation(forSource: location(of: "Next", in: emoji)) == location(of: "Next", in: formatted))
    }

    @Test("An empty block at the start gives the first line")
    func emptyRange() {
        let map = CitationLineMap(source: "One\n", markdown: "One\n")
        #expect(map.sourceRange(forMarkdown: NSRange(location: 0, length: 0)) == NSRange(location: 0, length: 3))
    }
}
