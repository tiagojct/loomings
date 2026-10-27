import Foundation

/// The YAML frontmatter block the editor dims and the preview omits. The web
/// renderer strips the same shape: a first line of exactly `---`, a closing
/// line of exactly `---` within fifty lines, and nothing else.
public enum MarkdownFrontmatter {
    public static func range(in string: String) -> NSRange? {
        range(in: string as NSString)
    }

    public static func range(in text: NSString) -> NSRange? {
        guard text.length >= 3 else { return nil }
        let firstLine = text.lineRange(for: NSRange(location: 0, length: 0))
        guard lineText(firstLine, text: text) == "---" else { return nil }

        var lineStart = firstLine.location + firstLine.length
        var lineNumber = 2
        while lineStart < text.length, lineNumber <= 50 {
            let line = text.lineRange(for: NSRange(location: lineStart, length: 0))
            if lineText(line, text: text) == "---" {
                var end = min(line.location + line.length, text.length)
                while end > line.location, isNewline(text.character(at: end - 1)) {
                    end -= 1
                }
                return NSRange(location: 0, length: end)
            }
            let next = line.location + line.length
            guard next > lineStart else { break }
            lineStart = next
            lineNumber += 1
        }
        return nil
    }

    private static func lineText(_ line: NSRange, text: NSString) -> String {
        var end = min(line.location + line.length, text.length)
        while end > line.location, isNewline(text.character(at: end - 1)) {
            end -= 1
        }
        return text.substring(with: NSRange(location: line.location, length: end - line.location))
    }

    private static func isNewline(_ character: unichar) -> Bool {
        character == 0x0A || character == 0x0D
    }
}
