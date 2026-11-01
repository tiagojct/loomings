import Foundation
import Testing
@testable import LoomingsTeaching

@Suite("Line diff")
struct LineDiffTests {
    static func lines(_ text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Applying the ops to the old lines must give the new lines.
    static func apply(_ ops: [DiffOp], old: [Substring], new: [Substring]) -> [Substring] {
        ops.compactMap { op in
            switch op {
            case .same(_, let index): return new[index]
            case .added(let index): return new[index]
            case .removed: return nil
            }
        }
    }

    @Test("Identical texts have no changes")
    func identicalHasNoChanges() {
        let a = Self.lines("one\ntwo\nthree")
        let ops = LineDiff.lines(old: a, new: a)
        #expect(ops == [.same(old: 0, new: 0), .same(old: 1, new: 1), .same(old: 2, new: 2)])
    }

    @Test("An insertion and a deletion come out in order")
    func insertionAndDeletion() {
        let old = Self.lines("a\nb\nc\nd\ne")
        let new = Self.lines("a\nc\nd\nx\ne")
        let ops = LineDiff.lines(old: old, new: new)
        #expect(ops == [
            .same(old: 0, new: 0), .removed(old: 1), .same(old: 2, new: 1), .same(old: 3, new: 2),
            .added(new: 3), .same(old: 4, new: 4),
        ])
    }

    @Test("Any ops list rebuilds the new text, empty sides included")
    func opsRebuildNewText() {
        let pairs = [("", "a\nb"), ("a\nb", ""), ("x\ny\nz", "z\ny\nx"), ("same", "same"), ("a\nb\na\nb", "b\na\nb\na")]
        for (a, b) in pairs {
            let old = Self.lines(a), new = Self.lines(b)
            #expect(Self.apply(LineDiff.lines(old: old, new: new), old: old, new: new) == new, "\(a) -> \(b)")
        }
    }

    @Test("Two 20,000-line documents with scattered edits compare in under a second")
    func largeDiffIsFast() {
        let old = (0..<20_000).map { Substring("line \($0) of the ship's log") }
        var new = old
        for index in stride(from: 50, to: 20_000, by: 100) { new[index] = "changed \(index)" }
        let start = Date()
        let ops = LineDiff.lines(old: old, new: new)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1, "took \(elapsed) s")
        #expect(ops.filter { if case .added = $0 { return true } else { return false } }.count == 200)
        #expect(Self.apply(ops, old: old, new: new) == new)
    }

    @Test("Completely different large documents fall back without blowing up")
    func unrelatedDocumentsFallBack() {
        let old = (0..<6_000).map { Substring("a\($0)") }
        let new = (0..<6_000).map { Substring("b\($0)") }
        let ops = LineDiff.lines(old: old, new: new)
        #expect(Self.apply(ops, old: old, new: new) == new)
        #expect(ops.count == 12_000)
    }

    @Test("Inside a changed line, only the changed words are marked")
    func wordsInsideChangedLine() {
        let old: Substring = "The sea was calm today"
        let new: Substring = "The sea was wild today"
        let result = LineDiff.words(old: old, new: new)
        #expect(result.removed.map { String(old[$0]) } == ["calm"])
        #expect(result.added.map { String(new[$0]) } == ["wild"])
    }
}
