import Foundation

/// Everything the teaching features learn from one snapshot of a document.
/// Built off the main thread with each parse.
public struct TeachingReport: Sendable, Equatable {
    public let lintIssues: [LintIssue]

    public init(lintIssues: [LintIssue]) {
        self.lintIssues = lintIssues
    }

    public static func make(source: String) -> TeachingReport {
        TeachingReport(lintIssues: MarkdownLint.lint(source))
    }
}
