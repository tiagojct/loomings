import Foundation
import LoomingsMarkdown
import Testing
@testable import LoomingsTeaching

@Suite("Section statistics")
struct SectionStatisticsTests {
    static let source = "# T\n\n## A\n\none two\n\n### A1\n\nthree four\n\n## B\n\nfive\n"

    static func sections(_ source: String, _ limits: [SectionLimit] = []) -> [SectionCount] {
        SectionStatistics.sections(source, outline: MarkdownParser.parse(source).outline, limits: limits)
    }

    @Test("A section counts its subsections and stops at the next heading of its level")
    func nestedSectionsIncludeSubsections() {
        let counts = Dictionary(uniqueKeysWithValues: Self.sections(Self.source).map { ($0.heading.title, $0.words) })
        #expect(counts["A"] == 5)   // one two, A1, three four
        #expect(counts["A1"] == 2)
        #expect(counts["B"] == 1)
        #expect(counts["T"] == 8)
    }

    @Test("A section's own heading is not counted")
    func wordsExcludeHeadingLine() {
        let sections = Self.sections("## Long heading with words\n\nbody\n")
        #expect(sections.first?.words == 1)
    }

    @Test("Limits match headings without regard to case or spaces")
    func limitMatchesCaseInsensitively() {
        let sections = Self.sections(Self.source, [SectionLimit(heading: "  a1 ", maxWords: 3), SectionLimit(heading: "b", maxWords: 10)])
        #expect(sections.first { $0.heading.title == "A1" }?.limit == 3)
        #expect(sections.first { $0.heading.title == "B" }?.limit == 10)
        #expect(sections.first { $0.heading.title == "A" }?.limit == nil)
    }

    @Test("Section ranges cover the heading and the body, ending where the next one starts")
    func rangesAreContiguous() {
        let text = Self.source as NSString
        let sections = Self.sections(Self.source)
        let a = try! #require(sections.first { $0.heading.title == "A" })
        #expect(text.substring(with: a.range).hasPrefix("## A"))
        #expect(NSMaxRange(a.range) == text.range(of: "## B").location)
    }

    @Test("The report carries sections only when the document sets a limit")
    func reportComputesSectionsForLimits() {
        let plain = TeachingReport.make(source: Self.source)
        #expect(plain.sections.isEmpty)
        let limited = TeachingReport.make(source: "---\nlimit: A 4\nlimit: 300\n---\n\n## A\n\none two three four five\n")
        #expect(limited.sections.first?.words == 5)
        #expect(limited.sections.first?.limit == 4)
        #expect(limited.directiveNotes.map(\.line) == [2])
    }

    @Test("The report counts only sections that have a limit")
    func reportKeepsOnlyLimitedSections() {
        let report = TeachingReport.make(source: "---\nlimit: A 4\n---\n\n## A\n\none two\n\n## B\n\nthree\n")
        #expect(report.sections.map(\.heading.title) == ["A"])
        #expect(TeachingReport.limits(in: "---\nlimit: A 4\nlimit: nope\n---\n").limits == [SectionLimit(heading: "A", maxWords: 4)])
    }

    struct OutlineCase: Decodable {
        struct Heading: Decodable, Equatable {
            let level: Int
            let title: String
        }
        let name: String
        let source: String
        let headings: [Heading]
    }

    @Test("The shared outline cases give the same levels and titles")
    func outlineCasesFromFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "outline-cases", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([OutlineCase].self, from: Data(contentsOf: url))
        #expect(cases.count >= 6)
        for item in cases {
            let outline = MarkdownParser.parse(item.source).outline.map { OutlineCase.Heading(level: $0.level, title: $0.title) }
            #expect(outline == item.headings, "\(item.name)")
        }
    }
}
