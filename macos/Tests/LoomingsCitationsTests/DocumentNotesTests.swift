import Foundation
import LoomingsTeaching
import Testing
@testable import LoomingsCitations

@Suite("Document notes")
struct DocumentNotesTests {
    private func report(_ notes: [CitationReport.Note]) -> CitationReport {
        CitationReport(citations: [], bibliography: [], bibliographyMarkdown: "", library: [], notes: notes, markdownSource: "")
    }

    private func lint(_ location: Int, _ rule: String = "rule") -> LintIssue {
        LintIssue(rule: rule, range: NSRange(location: location, length: 1), message: "Lint at \(location).", fix: nil)
    }

    @Test("A note with a place keeps its range")
    func placed() {
        let notes = report([.init(from: 4, to: 9, message: "No entry.", file: nil, line: nil)]).documentNotes
        #expect(notes == [DocumentNote(range: NSRange(location: 4, length: 5), message: "No entry.")])
    }

    @Test("A note about a file has no range, and names the file and the line")
    func fileLevel() {
        let notes = report([
            .init(from: 0, to: 0, message: "Bad entry.", file: "refs.bib", line: 3),
            .init(from: 0, to: 0, message: "Bad file.", file: "refs.bib", line: 0),
            .init(from: 0, to: 0, message: "The code failed.", file: nil, line: 0),
            .init(from: 0, to: 0, message: "Empty name.", file: "", line: 0),
        ]).documentNotes
        #expect(notes.map(\.message) == ["refs.bib, line 4: Bad entry.", "refs.bib: Bad file.", "The code failed.", "Empty name."])
        #expect(notes.allSatisfy { $0.range == nil && $0.missingFile == nil })
    }

    @Test("A missing file names the file to choose")
    func missing() {
        let notes = report([
            .init(from: 0, to: 0, message: "The file refs.bib is missing.", file: "refs.bib", line: 0),
            .init(from: 0, to: 0, message: "The file refs.bib is missing. This document has no folder. Save the document, or use an absolute path.", file: "refs.bib", line: 0),
            .init(from: 0, to: 0, message: "The file refs.bib could not be read as text.", file: "refs.bib", line: 0),
        ]).documentNotes
        #expect(notes.map(\.missingFile) == ["refs.bib", "refs.bib", nil])
        #expect(notes[0].message == "The file refs.bib is missing.")
    }

    @Test("Notes about files come first, then all notes by place")
    func merged() {
        let citation = [
            DocumentNote(range: NSRange(location: 20, length: 2), message: "Late key."),
            DocumentNote(range: nil, message: "A file."),
            DocumentNote(range: NSRange(location: 5, length: 2), message: "Early key."),
        ]
        let notes = DocumentNote.merged(lint: [lint(30), lint(5), lint(10)], citation: citation)
        #expect(notes.map(\.message) == ["A file.", "Lint at 5.", "Early key.", "Lint at 10.", "Late key.", "Lint at 30."])
    }

    @Test("A note from the checker keeps its issue")
    func issue() {
        let notes = DocumentNote.merged(lint: [lint(2)], citation: [])
        #expect(notes.first?.issue == lint(2))
        #expect(notes.first?.range == NSRange(location: 2, length: 1))
    }

    @Test("Either list can be late: the other stays, and the order is the same")
    func eitherLate() {
        let citation = [DocumentNote(range: NSRange(location: 5, length: 2), message: "Key.")]
        #expect(DocumentNote.merged(lint: [], citation: citation) == citation)
        #expect(DocumentNote.merged(lint: [lint(5)], citation: []).count == 1)
        let both = DocumentNote.merged(lint: [lint(5)], citation: citation)
        #expect(both == DocumentNote.merged(lint: [lint(5)], citation: citation))
        #expect(both.map(\.message) == ["Lint at 5.", "Key."])
    }
}

@Suite("File name in the frontmatter")
struct CitationFileNameTests {
    private let folder = URL(fileURLWithPath: "/Users/a/paper", isDirectory: true)

    @Test("A file in the folder gets a relative name")
    func relative() {
        #expect(CitationFileName.value(for: URL(fileURLWithPath: "/Users/a/paper/refs.bib"), folder: folder) == "refs.bib")
        #expect(CitationFileName.value(for: URL(fileURLWithPath: "/Users/a/paper/data/refs.bib"), folder: folder) == "data/refs.bib")
    }

    @Test("A file outside the folder, or no folder, gives an absolute path")
    func absolute() {
        #expect(CitationFileName.value(for: URL(fileURLWithPath: "/Users/a/other/refs.bib"), folder: folder) == "/Users/a/other/refs.bib")
        #expect(CitationFileName.value(for: URL(fileURLWithPath: "/Users/a/paper2/refs.bib"), folder: folder) == "/Users/a/paper2/refs.bib")
        #expect(CitationFileName.value(for: URL(fileURLWithPath: "/Users/a/paper/refs.bib"), folder: nil) == "/Users/a/paper/refs.bib")
    }
}
