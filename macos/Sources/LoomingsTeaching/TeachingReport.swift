import Foundation
import LoomingsMarkdown

/// Everything the teaching features learn from one snapshot of a document.
/// Built off the main thread with each parse.
public struct TeachingReport: Sendable, Equatable {
    public let lintIssues: [LintIssue]
    public let checkResults: [CheckResult]
    /// Frontmatter directives that could not be understood.
    public let directiveNotes: [DirectiveNote]
    /// The sections that have a limit, counted.
    public let sections: [SectionCount]

    public init(
        lintIssues: [LintIssue],
        checkResults: [CheckResult] = [],
        directiveNotes: [DirectiveNote] = [],
        sections: [SectionCount] = []
    ) {
        self.lintIssues = lintIssues
        self.checkResults = checkResults
        self.directiveNotes = directiveNotes
        self.sections = sections
    }

    /// The `limit:` directives of the frontmatter, and notes for any that
    /// cannot be read. Cheap: it reads the frontmatter only.
    public static func limits(in source: String) -> (limits: [SectionLimit], notes: [DirectiveNote]) {
        var limits: [SectionLimit] = []
        var notes: [DirectiveNote] = []
        for directive in Directives.read(source) where directive.key == "limit" {
            switch SectionLimit.parse(directive) {
            case .success(let limit): limits.append(limit)
            case .failure(let note): notes.append(note)
            }
        }
        return (limits, notes)
    }

    public static func make(source: String, attached: AttachedChecks? = nil) -> TeachingReport {
        // One parse serves the checker, the checks and the outline.
        let parsed = ParsedMarkdown(source)
        let checks = ExerciseEvaluator.evaluate(parsed, attached: attached)
        let (limits, limitNotes) = Self.limits(in: source)
        let notes = checks.notes + limitNotes
        let sections = limits.isEmpty
            ? []
            : SectionStatistics.sections(source, outline: MarkdownParser.outline(parsed), limits: limits, onlyLimited: true)
        return TeachingReport(
            lintIssues: source.isEmpty ? [] : MarkdownLint.lint(parsed),
            checkResults: checks.results,
            directiveNotes: notes.sorted { $0.line < $1.line },
            sections: sections
        )
    }
}
