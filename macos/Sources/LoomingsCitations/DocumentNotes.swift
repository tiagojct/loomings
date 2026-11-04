import Foundation
import LoomingsTeaching

/// One row of the notes list: a note of the learner's checker or of the
/// citation report.
public struct DocumentNote: Equatable, Sendable {
    /// The place in the text. A note about a file has no place.
    public var range: NSRange?
    public let message: String
    /// The checker's note, which can have a fix.
    public let issue: LintIssue?
    /// The name in the frontmatter of a file that is missing.
    public let missingFile: String?

    public init(range: NSRange?, message: String, missingFile: String? = nil) {
        self.range = range
        self.message = message
        self.issue = nil
        self.missingFile = missingFile
    }

    public init(issue: LintIssue) {
        range = issue.range
        message = issue.message
        self.issue = issue
        missingFile = nil
    }

    /// The list comes from both inputs only, so it does not change with the
    /// order in which they arrive. Notes about files come first, in report
    /// order. Then all notes go by place, and the checker goes first in a tie.
    public static func merged(lint: [LintIssue], citation: [DocumentNote]) -> [DocumentNote] {
        let notes = lint.map(DocumentNote.init(issue:)) + citation
        return notes.enumerated().sorted { left, right in
            let places = (left.element.range?.location ?? -1, right.element.range?.location ?? -1)
            return places.0 == places.1 ? left.offset < right.offset : places.0 < places.1
        }.map(\.element)
    }
}

extension CitationReport {
    /// The notes for the list, as `citationNotes` in `src/citations/editor.js`
    /// makes them. The ranges are for the text of this report.
    public var documentNotes: [DocumentNote] {
        notes.map { note in
            if note.from != 0 || note.to != 0 {
                return DocumentNote(range: NSRange(location: note.from, length: note.to - note.from), message: note.message)
            }
            guard let file = note.file, !file.isEmpty else {
                return DocumentNote(range: nil, message: note.message)
            }
            if note.message.hasPrefix("The file \(file) is missing.") {
                return DocumentNote(range: nil, message: note.message, missingFile: file)
            }
            let line = (note.line ?? 0) > 0 ? ", line \((note.line ?? 0) + 1)" : ""
            return DocumentNote(range: nil, message: "\(file)\(line): \(note.message)")
        }
    }
}

/// The name of a chosen file for the frontmatter.
public enum CitationFileName {
    /// A name from `folder` when the file is in it, else the absolute path.
    public static func value(for file: URL, folder: URL?) -> String {
        let path = file.standardizedFileURL.path
        guard let folder else { return path }
        let base = folder.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}
