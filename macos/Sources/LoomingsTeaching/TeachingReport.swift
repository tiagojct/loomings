import Foundation
import LoomingsMarkdown

/// Everything the teaching features learn from one snapshot of a document.
/// Built off the main thread with each parse.
public struct TeachingReport: Sendable, Equatable {
    public let lintIssues: [LintIssue]
    public let checkResults: [CheckResult]
    /// Frontmatter directives that could not be understood.
    public let directiveNotes: [DirectiveNote]
    /// Every section, counted, but only when the document sets a limit.
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

    public static func make(source: String, attached: AttachedChecks? = nil) -> TeachingReport {
        let checks = ExerciseEvaluator.evaluate(source, attached: attached)
        var limits: [SectionLimit] = []
        var notes = checks.notes
        for directive in Directives.read(source) where directive.key == "limit" {
            switch SectionLimit.parse(directive) {
            case .success(let limit): limits.append(limit)
            case .failure(let note): notes.append(note)
            }
        }
        let sections = limits.isEmpty
            ? []
            : SectionStatistics.sections(source, outline: MarkdownParser.parse(source).outline, limits: limits)
        return TeachingReport(
            lintIssues: MarkdownLint.lint(source),
            checkResults: checks.results,
            directiveNotes: notes.sorted { $0.line < $1.line },
            sections: sections
        )
    }
}
