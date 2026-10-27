import Testing
@testable import LoomingsMarkdown

@Suite("Text statistics")
struct TextStatisticsTests {
    @Test("Plain prose")
    func plainProse() {
        #expect(TextStatistics.countWords("Hello world") == 2)
        #expect(TextStatistics.countWords("") == 0)
        #expect(TextStatistics.countWords("café naïve") == 2)
        #expect(TextStatistics.countWords("don’t stop") == 2)
    }

    @Test("Markdown structure is not prose")
    func markdownStructure() {
        #expect(TextStatistics.countWords("# Heading") == 1)
        #expect(TextStatistics.countWords("- one\n- two") == 2)
        #expect(TextStatistics.countWords("1. first") == 1)
        #expect(TextStatistics.countWords("[a link](https://example.com)") == 2)
        #expect(TextStatistics.countWords("https://example.com") == 1)
    }

    @Test("Reading time rounds up and ignores an empty document")
    func readingTime() {
        #expect(TextStatistics.readingTime(0) == "")
        #expect(TextStatistics.readingTime(1) == "~1 min")
        #expect(TextStatistics.readingTime(200) == "~1 min")
        #expect(TextStatistics.readingTime(201) == "~2 min")
    }
}
