import Foundation

/// Finds the paragraph and sentence around the caret for focus mode. Pure so
/// the range rules can be tested without a text view.
public enum SentenceFocus {
    private static let sentence = try! NSRegularExpression(
        pattern: #"[^.!?\n]*[.!?]+|\S[^.!?\n]*$"#
    )

    public static func activeRange(in text: NSString, caret: Int) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let position = min(max(0, caret), text.length)

        let caretLine = text.lineRange(
            for: NSRange(location: min(position, text.length - 1), length: 0)
        )
        var paragraphStart = caretLine.location

        while paragraphStart > 0 {
            let previous = text.lineRange(
                for: NSRange(location: paragraphStart - 1, length: 0)
            )
            guard previous.location < paragraphStart else { break }
            if contentEnd(of: previous, in: text) == previous.location {
                break
            }
            paragraphStart = previous.location
        }

        var paragraphEnd = contentEnd(of: caretLine, in: text)
        while paragraphEnd < text.length {
            var nextStart = paragraphEnd
            if nextStart < text.length, text.character(at: nextStart) == 0x0D {
                nextStart += 1
            }
            if nextStart < text.length, text.character(at: nextStart) == 0x0A {
                nextStart += 1
            }
            guard nextStart < text.length else { break }

            let nextLine = text.lineRange(
                for: NSRange(location: nextStart, length: 0)
            )
            let nextContentEnd = contentEnd(of: nextLine, in: text)
            if nextContentEnd == nextLine.location {
                break
            }
            paragraphEnd = nextContentEnd
        }

        let paragraphRange = NSRange(
            location: paragraphStart,
            length: max(0, paragraphEnd - paragraphStart)
        )
        guard paragraphRange.length > 0 else { return paragraphRange }

        let paragraph = text.substring(with: paragraphRange)
        let offset = min(max(0, position - paragraphStart), (paragraph as NSString).length)

        let matches = sentence.matches(
            in: paragraph,
            range: NSRange(location: 0, length: (paragraph as NSString).length)
        )
        for match in matches {
            let range = match.range
            if offset >= range.location && offset <= range.location + range.length {
                return NSRange(
                    location: paragraphStart + range.location,
                    length: range.length
                )
            }
        }
        return paragraphRange
    }

    private static func contentEnd(of line: NSRange, in text: NSString) -> Int {
        var end = min(line.location + line.length, text.length)
        while end > line.location {
            let character = text.character(at: end - 1)
            if character == 0x0A || character == 0x0D {
                end -= 1
            } else {
                break
            }
        }
        return end
    }
}
