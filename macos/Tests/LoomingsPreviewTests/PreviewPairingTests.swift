import Foundation
import Testing
@testable import LoomingsPreview

/// Split view pairs a source position with the preview block made from it.
@Suite("Preview pairing")
struct PreviewPairingTests {
    private static let source = "# Title\n\nA paragraph.\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nLast.\n"

    @Test("A position inside a block finds that block")
    func insideBlock() {
        let document = PreviewRenderer(producesHTML: false).render(source: Self.source, documentURL: nil)
        let ns = Self.source as NSString
        let tableCell = ns.range(of: "| 1 |").location
        let index = document.blockIndex(containing: tableCell)
        #expect(index.map { document.blocks[$0].kind } == .table)
        #expect(document.blockIndex(containing: 0) == 0)
        #expect(document.blockIndex(containing: ns.range(of: "Last.").location + 5) == document.blocks.count - 1)
    }

    @Test("A blank line between blocks finds nothing")
    func blankLineFindsNothing() {
        let document = PreviewRenderer(producesHTML: false).render(source: Self.source, documentURL: nil)
        let blank = (Self.source as NSString).range(of: "\n\nA paragraph").location + 1
        #expect(document.blockIndex(containing: blank) == nil)
        #expect(document.blockIndex(containing: -1) == nil)
        #expect(document.blockIndex(containing: 10_000) == nil)
    }
}
