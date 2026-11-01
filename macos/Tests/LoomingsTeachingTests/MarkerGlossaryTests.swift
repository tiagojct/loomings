import Foundation
import LoomingsMarkdown
import Testing
@testable import LoomingsTeaching

@Suite("Marker glossary")
struct MarkerGlossaryTests {
    @Test("The number of # signs names the heading level")
    func headingLevelFromHashes() {
        let explanation = MarkerGlossary.explain(kind: .headingMarker, marker: "###")
        #expect(explanation?.title == "Level-3 heading")
        #expect(explanation?.lesson == "01-basics.md")
        #expect(MarkerGlossary.explain(kind: .headingMarker, marker: "#")?.title == "Level-1 heading")
    }

    @Test("Setext underlines are explained as underlines")
    func setextUnderlines() {
        #expect(MarkerGlossary.explain(kind: .headingMarker, marker: "===")?.title == "Level-1 heading (underline)")
        #expect(MarkerGlossary.explain(kind: .headingMarker, marker: "---")?.title == "Level-2 heading (underline)")
    }

    @Test("List markers tell bullets, numbers and task boxes apart")
    func listMarkers() {
        #expect(MarkerGlossary.explain(kind: .listMarker, marker: "- ")?.title == "Bullet list item")
        #expect(MarkerGlossary.explain(kind: .listMarker, marker: "12. ")?.title == "Numbered list item")
        #expect(MarkerGlossary.explain(kind: .listMarker, marker: "[ ]")?.title.contains("Task") == true)
        #expect(MarkerGlossary.explain(kind: .listMarker, marker: "[x]")?.title.contains("Task") == true)
    }

    @Test("Emphasis and strong are told apart by their marks")
    func emphasisAndStrong() {
        #expect(MarkerGlossary.explain(kind: .emphasisMarker, marker: "_")?.title == "Emphasis")
        #expect(MarkerGlossary.explain(kind: .strongMarker, marker: "**")?.title == "Strong emphasis")
    }

    @Test("Every marker kind but code content is explained")
    func everyKindExplained() {
        let kinds: [MarkdownSyntaxKind] = [
            .headingMarker, .emphasisMarker, .strongMarker, .strikethroughMarker, .inlineCodeMarker,
            .fencedCodeDelimiter, .blockQuoteMarker, .listMarker, .linkPunctuation, .imagePunctuation,
            .thematicBreak, .rawHTML, .frontmatter,
        ]
        for kind in kinds {
            let explanation = MarkerGlossary.explain(kind: kind, marker: "x")
            #expect(explanation != nil, "\(kind)")
            #expect(explanation?.body.isEmpty == false, "\(kind)")
        }
        #expect(MarkerGlossary.explain(kind: .codeBlockContent, marker: "x") == nil)
    }

    struct Case: Decodable {
        let kind: String
        let marker: String
        let title: String
        let body: String
        let lesson: String?
    }

    @Test("The shared glossary cases match, word for word")
    func casesFromFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "glossary-cases", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        #expect(cases.count >= 20)
        for item in cases {
            let kind = try #require(MarkdownSyntaxKind(rawValue: item.kind), "\(item.kind)")
            let explanation = MarkerGlossary.explain(kind: kind, marker: item.marker)
            #expect(explanation == MarkerExplanation(title: item.title, body: item.body, lesson: item.lesson), "\(item.kind) \(item.marker)")
        }
    }

    @Test("Lessons named by the glossary exist")
    func lessonsExist() throws {
        let lessons = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/lessons")
        let kinds: [(MarkdownSyntaxKind, String)] = [
            (.headingMarker, "#"), (.emphasisMarker, "*"), (.inlineCodeMarker, "`"), (.blockQuoteMarker, ">"),
            (.listMarker, "-"), (.linkPunctuation, "["), (.imagePunctuation, "!["), (.thematicBreak, "---"),
            (.frontmatter, "---"),
        ]
        for (kind, marker) in kinds {
            let lesson = try #require(MarkerGlossary.explain(kind: kind, marker: marker)?.lesson, "\(kind)")
            #expect(FileManager.default.fileExists(atPath: lessons.appendingPathComponent(lesson).path), "\(lesson)")
        }
    }
}
