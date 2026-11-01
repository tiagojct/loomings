import Foundation

/// Converts the parser's line/column source locations into UTF-16 offsets.
///
/// cmark reports columns as 1-based UTF-8 byte offsets inside a line. AppKit
/// addresses text in UTF-16 code units, so a non-ASCII line before a span
/// would otherwise shift every range after it. Line starts are kept as two
/// parallel arrays; offsets inside a long line are resolved from a checkpoint
/// every 128 bytes, so a 100 KB paragraph does not turn every span into a
/// scan from the line's first byte.
public struct SourceMap {
    public let utf8Count: Int
    public let utf16Count: Int

    private let source: String
    private let lineStartsUTF8: [Int]
    private let lineStartsUTF16: [Int]
    private let checkpointBytes: [Int]
    private let checkpointUTF16: [Int]
    private let checkpointIndices: [String.Index]

    private static let checkpointStride = 128

    public init(_ source: String) {
        self.source = source

        var starts8: [Int] = [0]
        var starts16: [Int] = [0]
        var checkpointsB: [Int] = [0]
        var checkpointsC: [Int] = [0]
        var checkpointsI: [String.Index] = [source.utf8.startIndex]

        let utf8 = source.utf8
        var index = utf8.startIndex
        var byteOffset = 0
        var unitOffset = 0
        var nextCheckpoint = Self.checkpointStride

        for scalar in source.unicodeScalars {
            let byteWidth: Int
            switch scalar.value {
            case 0..<0x80: byteWidth = 1
            case 0x80..<0x800: byteWidth = 2
            case 0x800..<0x10000: byteWidth = 3
            default: byteWidth = 4
            }
            index = utf8.index(index, offsetBy: byteWidth)
            byteOffset += byteWidth
            unitOffset += scalar.value > 0xFFFF ? 2 : 1

            if byteOffset >= nextCheckpoint {
                checkpointsB.append(byteOffset)
                checkpointsC.append(unitOffset)
                checkpointsI.append(index)
                nextCheckpoint = (byteOffset / Self.checkpointStride + 1) * Self.checkpointStride
            }
            if scalar.value == 0x0A {
                starts8.append(byteOffset)
                starts16.append(unitOffset)
            }
        }

        self.utf8Count = byteOffset
        self.utf16Count = unitOffset
        self.lineStartsUTF8 = starts8
        self.lineStartsUTF16 = starts16
        self.checkpointBytes = checkpointsB
        self.checkpointUTF16 = checkpointsC
        self.checkpointIndices = checkpointsI
    }

    /// The UTF-16 range for a parser range, or nil when the parser points
    /// outside the source (which happens for some synthetic nodes).
    public var lineStarts: [Int] { lineStartsUTF16 }
    public var characterCount: Int { utf16Count }

    public func nsRange(for range: MarkdownSourceRange?) -> NSRange? {
        guard let range else { return nil }
        return nsRange(
            startLine: range.startLine, startColumn: range.startColumn,
            endLine: range.endLine, endColumn: range.endColumn
        )
    }

    public func nsRange(for node: MarkdownNode) -> NSRange? {
        nsRange(for: node.range)
    }

    private func nsRange(startLine: Int, startColumn: Int, endLine: Int, endColumn: Int) -> NSRange? {
        guard let start = utf16Offset(line: startLine, column: startColumn),
              let end = utf16Offset(line: endLine, column: endColumn),
              end >= start else {
            return nil
        }
        return NSRange(location: start, length: end - start)
    }

    private func utf16Offset(line: Int, column: Int) -> Int? {
        guard line >= 1, column >= 1 else { return nil }
        let index = line - 1
        guard index < lineStartsUTF8.count else { return nil }

        let byteOffset = lineStartsUTF8[index] + column - 1
        guard byteOffset <= utf8Count else { return nil }
        return utf16Offset(utf8Offset: byteOffset)
    }

    private func utf16Offset(utf8Offset: Int) -> Int? {
        guard utf8Offset >= 0, utf8Offset <= utf8Count else { return nil }

        let checkpoint = checkpointIndex(atOrBefore: utf8Offset)
        var units = checkpointUTF16[checkpoint]
        let startIndex = checkpointIndices[checkpoint]
        let bytes = source.utf8
        var index = startIndex
        var remaining = utf8Offset - checkpointBytes[checkpoint]
        while remaining > 0 {
            let value = bytes[index]
            if value & 0xC0 != 0x80 {
                units += value >= 0xF0 ? 2 : 1
            }
            index = bytes.index(after: index)
            remaining -= 1
        }
        return units
    }

    private func checkpointIndex(atOrBefore offset: Int) -> Int {
        var low = 0
        var high = checkpointBytes.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if checkpointBytes[mid] <= offset {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }
}
