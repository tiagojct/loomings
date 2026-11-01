import Foundation

/// Everything the teaching features learn from one snapshot of a document.
/// Built off the main thread with each parse.
public struct TeachingReport: Sendable, Equatable {
    public let lintIssues: [LintIssue]
    public let checkResults: [CheckResult]
    /// Frontmatter directives that could not be understood.
    public let directiveNotes: [DirectiveNote]

    public init(lintIssues: [LintIssue], checkResults: [CheckResult] = [], directiveNotes: [DirectiveNote] = []) {
        self.lintIssues = lintIssues
        self.checkResults = checkResults
        self.directiveNotes = directiveNotes
    }

    public static func make(source: String, attached: AttachedChecks? = nil) -> TeachingReport {
        let checks = ExerciseEvaluator.evaluate(source, attached: attached)
        return TeachingReport(
            lintIssues: MarkdownLint.lint(source),
            checkResults: checks.results,
            directiveNotes: checks.notes
        )
    }
}
