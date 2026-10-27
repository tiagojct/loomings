import Foundation

/// Pure editing rules from the web editor: what Enter does inside a list or
/// quotation, and how Tab indents a block.
public enum MarkdownEditing {
    public struct Continuation: Equatable {
        /// When the item is empty, the line is replaced by this indent.
        public let replacementLine: String?
        /// Otherwise this text is inserted at the caret.
        public let insertion: String?
    }

    private static let unordered = try! NSRegularExpression(
        pattern: #"^(\s*)([-*+])(\s+)(.*)$"#
    )
    private static let ordered = try! NSRegularExpression(
        pattern: #"^(\s*)(\d+)([.)])(\s+)(.*)$"#
    )
    private static let quote = try! NSRegularExpression(
        pattern: #"^(\s*)>\s*(.*)$"#
    )

    public static func continuation(forLine line: String) -> Continuation? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        if let match = unordered.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: match.range(at: 1))
            let marker = ns.substring(with: match.range(at: 2))
            let spacing = ns.substring(with: match.range(at: 3))
            let content = ns.substring(with: match.range(at: 4))
            if content.isEmpty {
                return Continuation(replacementLine: indent, insertion: nil)
            }
            return Continuation(
                replacementLine: nil,
                insertion: "\n\(indent)\(marker)\(spacing)"
            )
        }

        if let match = ordered.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: match.range(at: 1))
            let number = Int(ns.substring(with: match.range(at: 2))) ?? 1
            let delimiter = ns.substring(with: match.range(at: 3))
            let spacing = ns.substring(with: match.range(at: 4))
            let content = ns.substring(with: match.range(at: 5))
            if content.isEmpty {
                return Continuation(replacementLine: indent, insertion: nil)
            }
            return Continuation(
                replacementLine: nil,
                insertion: "\n\(indent)\(number + 1)\(delimiter)\(spacing)"
            )
        }

        if let match = quote.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: match.range(at: 1))
            let content = ns.substring(with: match.range(at: 2))
            if content.isEmpty {
                return Continuation(replacementLine: indent, insertion: nil)
            }
            return Continuation(replacementLine: nil, insertion: "\n\(indent)> ")
        }

        return nil
    }

    /// Adds `spaces` leading spaces to every non-empty line.
    public static func indent(_ block: String, spaces: Int = 2) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? String($0) : prefix + $0 }
            .joined(separator: "\n")
    }

    /// Removes up to `spaces` leading spaces from every line.
    public static func outdent(_ block: String, spaces: Int = 2) -> String {
        return block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var remaining = spaces
                var result = Substring(line)
                while remaining > 0, result.first == " " {
                    result = result.dropFirst()
                    remaining -= 1
                }
                return String(result)
            }
            .joined(separator: "\n")
    }
}

/// The web editor's smart typography: curly quotes, em dashes and ellipses.
public enum SmartTypography {
    public struct Replacement: Equatable {
        public let text: String
        /// Range in the current text to replace, including the typed
        /// character's position and any preceding characters it combines with.
        public let range: NSRange
    }

    public static func replacement(
        for character: Character,
        at location: Int,
        in text: NSString
    ) -> Replacement? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return nil
        }

        switch scalar.value {
        case 0x22: // "
            let opens = opensQuote(at: location, in: text)
            return Replacement(
                text: opens ? "“" : "”",
                range: NSRange(location: location, length: 0)
            )
        case 0x27: // '
            let opens = opensQuote(at: location, in: text)
            return Replacement(
                text: opens ? "‘" : "’",
                range: NSRange(location: location, length: 0)
            )
        case 0x2D: // -
            guard location > 0, text.character(at: location - 1) == 0x2D else {
                return nil
            }
            return Replacement(
                text: "—",
                range: NSRange(location: location - 1, length: 1)
            )
        case 0x2E: // .
            guard location >= 2,
                  text.character(at: location - 1) == 0x2E,
                  text.character(at: location - 2) == 0x2E else {
                return nil
            }
            return Replacement(
                text: "…",
                range: NSRange(location: location - 2, length: 2)
            )
        default:
            return nil
        }
    }

    private static func opensQuote(at location: Int, in text: NSString) -> Bool {
        guard location > 0 else { return true }
        let previous = text.character(at: location - 1)
        switch previous {
        case 0x20, 0x09, 0x0A, 0x0D, 0x28, 0x5B, 0x7B:
            return true
        default:
            return false
        }
    }
}
