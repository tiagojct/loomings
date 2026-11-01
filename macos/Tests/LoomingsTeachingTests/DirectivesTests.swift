import Testing
@testable import LoomingsTeaching

@Suite("Frontmatter directives")
struct DirectivesTests {
    @Test("Only check and limit lines inside the frontmatter count")
    func readsOnlyFrontmatter() {
        let source = "---\ncheck: ordered-list 3\nlimit: Introduction 200\ntitle: x\n---\n\ncheck: heading\n"
        let directives = Directives.read(source)
        #expect(directives.map(\.key) == ["check", "limit"])
        #expect(directives.map(\.line) == [1, 2])
        #expect(Directives.read("check: heading\n").isEmpty)
    }

    @Test("Checks parse with their arguments and defaults")
    func parsesChecks() {
        #expect(ExerciseCheck.parse(.init(key: "check", value: "ordered-list 3", line: 1)) == .success(.orderedList(items: 3)))
        #expect(ExerciseCheck.parse(.init(key: "check", value: "bullet-list", line: 1)) == .success(.bulletList(items: 2)))
        #expect(ExerciseCheck.parse(.init(key: "check", value: "heading 2", line: 1)) == .success(.heading(level: 2, min: 1)))
        #expect(ExerciseCheck.parse(.init(key: "check", value: "heading", line: 1)) == .success(.heading(level: nil, min: 1)))
        #expect(ExerciseCheck.parse(.init(key: "check", value: "code-block python", line: 1)) == .success(.codeBlock(language: "python")))
        #expect(ExerciseCheck.parse(.init(key: "check", value: "words 50", line: 1)) == .success(.words(min: 50)))
        #expect(ExerciseCheck.parse(.init(key: "check", value: "Image-Alt", line: 1)) == .success(.imageAlt))
    }

    @Test("A limit keeps spaces in the heading title")
    func parsesLimitWithSpacesInTitle() {
        #expect(SectionLimit.parse(.init(key: "limit", value: "Methods and data 350", line: 2)) == .success(.init(heading: "Methods and data", maxWords: 350)))
    }

    @Test("Malformed directives become notes, not crashes")
    func malformedDirectives() {
        guard case .failure(let note) = ExerciseCheck.parse(.init(key: "check", value: "banana", line: 3)) else {
            Issue.record("banana parsed")
            return
        }
        #expect(note.line == 3)
        #expect(note.message.contains("banana"))
        guard case .failure = SectionLimit.parse(.init(key: "limit", value: "200", line: 4)) else {
            Issue.record("a limit with no heading parsed")
            return
        }
        guard case .failure = ExerciseCheck.parse(.init(key: "check", value: "words", line: 5)) else {
            Issue.record("words without a number parsed")
            return
        }
        guard case .failure = ExerciseCheck.parse(.init(key: "check", value: "heading 9", line: 6)) else {
            Issue.record("heading level 9 parsed")
            return
        }
    }
}
