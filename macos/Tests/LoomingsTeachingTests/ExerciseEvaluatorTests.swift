import Foundation
import Testing
@testable import LoomingsTeaching

@Suite("Exercise checks")
struct ExerciseEvaluatorTests {
    struct Case: Decodable {
        let name: String
        let source: String
        let checks: [String]
        let passed: [Bool]
    }

    static func checks(_ values: [String]) -> [ExerciseCheck] {
        values.compactMap { try? ExerciseCheck.parse(Directive(key: "check", value: $0, line: 0)).get() }
    }

    static let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/lessons")

    @Test("Every shared case passes and fails as expected")
    func casesFromFixture() throws {
        let url = try #require(Bundle.module.url(forResource: "check-cases", withExtension: "json", subdirectory: "Fixtures"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        #expect(cases.count >= 15)
        for item in cases {
            let attached = AttachedChecks(checks: Self.checks(item.checks), after: nil)
            #expect(attached.checks.count == item.checks.count, "\(item.name): every check parses")
            let report = ExerciseEvaluator.evaluate(item.source, attached: attached)
            #expect(report.results.map(\.passed) == item.passed, "\(item.name)")
            #expect(report.results.allSatisfy { !$0.label.isEmpty }, "\(item.name)")
        }
    }

    @Test("Frontmatter checks and attached checks combine; malformed lines become notes")
    func frontmatterAndExtraCombine() {
        let source = "---\ncheck: quote\ncheck: banana\n---\n\n> said\n"
        let report = ExerciseEvaluator.evaluate(source, attached: AttachedChecks(checks: [.strong], after: nil))
        #expect(report.results.map(\.passed) == [true, false])
        #expect(report.notes.map(\.line) == [2])
    }

    @Test("Frontmatter is not counted as words or structure")
    func frontmatterIsNotContent() {
        let report = ExerciseEvaluator.evaluate("---\ncheck: words 3\ntitle: one two three four\n---\n\nHello there.\n")
        #expect(report.results.map(\.passed) == [false])
    }

    @Test("Attached checks look only after their anchor")
    func attachedChecksLookAfterAnchor() {
        let lesson = "# Lesson\n\n1. a\n2. b\n3. c\n\nDone.\n"
        let attached = AttachedChecks(checks: [.orderedList(items: 3)], after: lesson)
        #expect(ExerciseEvaluator.evaluate(lesson, attached: attached).results.map(\.passed) == [false])
        let answered = lesson + "\n1. x\n2. y\n3. z\n"
        #expect(ExerciseEvaluator.evaluate(answered, attached: attached).results.map(\.passed) == [true])
    }

    @Test("Every bundled lesson's checks parse, fail untouched, and pass with an answer")
    func lessonChecks() throws {
        let data = try Data(contentsOf: Self.resources.appendingPathComponent("checks.json"))
        let table = try JSONDecoder().decode([String: [String]].self, from: data)
        #expect(table.count == 6)
        let answers: [String: String] = [
            "01-basics.md": "\n## About me\n\nI teach health informatics in Porto. I like *long* walks by the **river** in the evening. My students write in Markdown.\n",
            "02-lists-quotes.md": "\n- Milk\n- Bread\n- Eggs\n- Rice\n- Tea\n\n1. Boil water.\n2. Add tea.\n3. Wait.\n\n> To be or not to be.\n> Shakespeare\n",
            "03-links-images.md": "\n[My school][fmup] and [the web](https://example.org).\n\n![A red boat on a calm sea](https://example.org/boat.png)\n\n[fmup]: https://sigarra.up.pt/fmup/\n",
            "04-code.md": "\nPress `Ctrl+S` to save `notes.md`.\n\n```python\nprint(1)\n```\n",
            "05-tables-rules.md": "\n| Course | Teacher | Day |\n| --- | --- | ---: |\n| A | B | Mon |\n| C | D | Tue |\n| E | F | Wed |\n",
            "06-frontmatter.md": "\n## One\n\n- a point\n\n> A saying.\n> Someone\n\n## Two\n\n[A link](https://example.org)\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n",
        ]
        for (file, values) in table {
            let checks = Self.checks(values)
            #expect(checks.count == values.count, "\(file): every check parses")
            let lesson = try String(contentsOf: Self.resources.appendingPathComponent(file), encoding: .utf8)
            let attached = AttachedChecks(checks: checks, after: lesson)
            let untouched = ExerciseEvaluator.evaluate(lesson, attached: attached).results
            #expect(untouched.allSatisfy { !$0.passed }, "\(file): an untouched lesson passes nothing")
            let trimmed = String(lesson.trimmingCharacters(in: .whitespacesAndNewlines).dropLast())
            let edited = ExerciseEvaluator.evaluate(trimmed, attached: attached).results
            #expect(edited.allSatisfy { !$0.passed }, "\(file): deleting the lesson's last character passes nothing")
            let answer = try #require(answers[file])
            let editedAnswered = ExerciseEvaluator.evaluate(trimmed + "\n" + answer, attached: attached).results
            let editedFailing = editedAnswered.filter { !$0.passed }.map(\.label)
            #expect(editedFailing.isEmpty, "\(file): an answer after an edited last line still counts: \(editedFailing)")
            let answered = ExerciseEvaluator.evaluate(lesson + answer, attached: attached).results
            let failing = answered.filter { !$0.passed }.map(\.label)
            #expect(failing.isEmpty, "\(file): \(failing)")
        }
    }
}
