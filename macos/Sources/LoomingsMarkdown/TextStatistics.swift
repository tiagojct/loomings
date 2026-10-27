import Foundation

/// Word and reading-time rules shared by the editor status bar. These mirror
/// the web app's `src/stats.js`: Markdown structure is not prose, link
/// destinations are not words, and bare URLs count once.
public enum TextStatistics {
    private static let linkDestination = try! NSRegularExpression(
        pattern: #"\]\([^()\s]*\)"#
    )
    private static let bareURL = try! NSRegularExpression(
        pattern: #"\bhttps?://\S+"#,
        options: [.caseInsensitive]
    )
    private static let listMarker = try! NSRegularExpression(
        pattern: #"^[ \t]{0,3}(?:[-*+]|\d+[.)])[ \t]+"#,
        options: [.anchorsMatchLines]
    )
    private static let word = try! NSRegularExpression(
        pattern: #"\p{L}[\p{L}\p{N}'’\-]*|\p{N}+"#
    )

    public static func countWords(_ text: String) -> Int {
        guard !text.isEmpty else { return 0 }

        var prose = text
        prose = linkDestination.stringByReplacingMatches(
            in: prose,
            range: NSRange(location: 0, length: prose.utf16.count),
            withTemplate: ""
        )
        prose = bareURL.stringByReplacingMatches(
            in: prose,
            range: NSRange(location: 0, length: prose.utf16.count),
            withTemplate: "url"
        )
        prose = listMarker.stringByReplacingMatches(
            in: prose,
            range: NSRange(location: 0, length: prose.utf16.count),
            withTemplate: ""
        )

        return word.numberOfMatches(
            in: prose,
            range: NSRange(location: 0, length: prose.utf16.count)
        )
    }

    public static func readingMinutes(_ words: Int, wordsPerMinute: Int = 200) -> Int {
        guard words > 0 else { return 0 }
        return max(1, Int(ceil(Double(words) / Double(wordsPerMinute))))
    }

    public static func readingTime(_ words: Int, wordsPerMinute: Int = 200) -> String {
        let minutes = readingMinutes(words, wordsPerMinute: wordsPerMinute)
        return minutes > 0 ? "~\(minutes) min" : ""
    }
}
