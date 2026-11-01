import Foundation
import Testing
@testable import LoomingsTeaching

@Suite("Learner's checker")
struct MarkdownLintTests {
    struct Case: Decodable {
        let name: String
        let source: String
        let rules: [String]
        let fixed: String
        /// Where each note starts (UTF-16), when the case pins it.
        let starts: [Int]?
    }

    static func cases() throws -> [Case] {
        let url = try #require(Bundle.module.url(forResource: "lint-cases", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
    }

    /// Applies every fix, last first, so earlier ranges stay valid.
    static func applyingFixes(_ issues: [LintIssue], to source: String) -> String {
        let text = NSMutableString(string: source)
        for fix in issues.compactMap(\.fix).sorted(by: { $0.range.location > $1.range.location }) {
            text.replaceCharacters(in: fix.range, with: fix.replacement)
        }
        return text as String
    }

    @Test("Every shared case finds its rules and fixes to the expected text")
    func casesFromFixture() throws {
        let cases = try Self.cases()
        #expect(cases.count >= 25)
        for item in cases {
            let issues = MarkdownLint.lint(item.source)
            #expect(issues.map(\.rule) == item.rules, "\(item.name)")
            #expect(Self.applyingFixes(issues, to: item.source) == item.fixed, "\(item.name)")
            if let starts = item.starts {
                #expect(issues.map(\.range.location) == starts, "\(item.name): starts")
            }
            for issue in issues {
                #expect(!issue.message.isEmpty, "\(item.name)")
                #expect(NSMaxRange(issue.range) <= (item.source as NSString).length, "\(item.name)")
            }
        }
    }

    @Test("Fix ranges are UTF-16 and survive emoji and CRLF")
    func fixesWorkAfterEmojiAndCRLF() {
        let source = "😀 x\r\n#Title\r\n"
        let issues = MarkdownLint.lint(source)
        #expect(issues.map(\.rule) == ["heading-space"])
        #expect(Self.applyingFixes(issues, to: source) == "😀 x\r\n# Title\r\n")
    }

    @Test("Code blocks and inline code are never checked")
    func codeIsExempt() {
        #expect(MarkdownLint.lint("```\n#Title\n[a](b c)\n```\n").isEmpty)
        #expect(MarkdownLint.lint("Use `[a](b c)` as an example.\n").isEmpty)
        #expect(MarkdownLint.lint("    #Title\n").isEmpty)
    }

    @Test("Issues come sorted by position")
    func sortedByPosition() {
        let issues = MarkdownLint.lint("![](a.png)\n\n#One\n\n#Two\n")
        #expect(issues.map(\.range.location) == issues.map(\.range.location).sorted())
        #expect(issues.count == 3)
    }
}

@Suite("Checker on bundled material")
struct BundledMaterialLintTests {
    @Test("Lessons, example and cheatsheet raise no notes")
    func bundledMaterialIsClean() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources")
        let lessons = try FileManager.default.contentsOfDirectory(
            at: resources.appendingPathComponent("lessons"), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "md" }
        #expect(lessons.count == 6)
        for url in lessons + [resources.appendingPathComponent("example.md"), resources.appendingPathComponent("cheatsheet.md")] {
            let issues = MarkdownLint.lint(try String(contentsOf: url, encoding: .utf8))
            #expect(issues.isEmpty, "\(url.lastPathComponent): \(issues.map { "\($0.rule)@\($0.range.location)" })")
        }
    }
}
