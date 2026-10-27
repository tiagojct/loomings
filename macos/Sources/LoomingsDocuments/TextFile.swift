import Foundation

public enum TextFileEncoding: String, Sendable, Codable, Equatable {
    case utf8
    case utf16LittleEndian
    case utf16BigEndian

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf16BigEndian: return .utf16BigEndian
        }
    }

    var byteOrderMark: [UInt8]? {
        switch self {
        case .utf8: return [0xEF, 0xBB, 0xBF]
        case .utf16LittleEndian: return [0xFF, 0xFE]
        case .utf16BigEndian: return [0xFE, 0xFF]
        }
    }
}

public enum LineEnding: String, Sendable, Codable, Equatable {
    case lf
    case crlf
    case cr
}

public struct TextFile: Sendable, Equatable {
    /// Text with every line ending normalised to `\n`, which is what
    /// NSTextView and the parser address.
    public var text: String
    public var encoding: TextFileEncoding
    public var hasBOM: Bool
    public var lineEnding: LineEnding

    public init(
        text: String,
        encoding: TextFileEncoding = .utf8,
        hasBOM: Bool = false,
        lineEnding: LineEnding = .lf
    ) {
        self.text = text
        self.encoding = encoding
        self.hasBOM = hasBOM
        self.lineEnding = lineEnding
    }
}

public enum TextFileError: LocalizedError, Equatable {
    /// Valid text in some encoding this app does not support (Latin-1,
    /// Windows-1252, Shift-JIS and so on).
    case unsupportedEncoding
    /// A byte-order mark declared UTF-8/UTF-16, but the payload was invalid.
    case invalidText(TextFileEncoding)

    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "Loomings opens UTF-8 and UTF-16 text only. This file uses another encoding; convert it to UTF-8 first."
        case .invalidText(let encoding):
            return "The file declares \(encoding.rawValue) but contains invalid byte sequences. It was not opened, so it cannot be overwritten."
        }
    }
}

public enum TextFileCodec {
    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
    private static let utf16LEBOM: [UInt8] = [0xFF, 0xFE]
    private static let utf16BEBOM: [UInt8] = [0xFE, 0xFF]

    public static func decode(_ data: Data) throws -> TextFile {
        if data.starts(with: utf8BOM) {
            guard let text = String(data: data.dropFirst(utf8BOM.count), encoding: .utf8) else {
                throw TextFileError.invalidText(.utf8)
            }
            return TextFile(
                text: normalizeLineEndings(text),
                encoding: .utf8,
                hasBOM: true,
                lineEnding: detectLineEnding(text)
            )
        }

        if data.starts(with: utf16LEBOM) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw TextFileError.invalidText(.utf16LittleEndian)
            }
            return TextFile(
                text: normalizeLineEndings(text),
                encoding: .utf16LittleEndian,
                hasBOM: true,
                lineEnding: detectLineEnding(text)
            )
        }

        if data.starts(with: utf16BEBOM) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw TextFileError.invalidText(.utf16BigEndian)
            }
            return TextFile(
                text: normalizeLineEndings(text),
                encoding: .utf16BigEndian,
                hasBOM: true,
                lineEnding: detectLineEnding(text)
            )
        }

        // No byte-order mark: only valid UTF-8 is accepted. Falling back to a
        // single-byte encoding would let the app save over text it could not
        // faithfully read.
        guard let text = String(data: data, encoding: .utf8) else {
            throw TextFileError.unsupportedEncoding
        }
        return TextFile(
            text: normalizeLineEndings(text),
            encoding: .utf8,
            hasBOM: false,
            lineEnding: detectLineEnding(text)
        )
    }

    public static func encode(_ file: TextFile) throws -> Data {
        let normalized = normalizeLineEndings(file.text)
        let body: String
        switch file.lineEnding {
        case .lf:
            body = normalized
        case .crlf:
            body = normalized.replacingOccurrences(of: "\n", with: "\r\n")
        case .cr:
            body = normalized.replacingOccurrences(of: "\n", with: "\r")
        }

        guard var data = body.data(using: file.encoding.stringEncoding) else {
            throw TextFileError.invalidText(file.encoding)
        }
        if file.hasBOM, let bom = file.encoding.byteOrderMark {
            data.insert(contentsOf: bom, at: 0)
        }
        return data
    }

    public static func normalizeLineEndings(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func detectLineEnding(_ text: String) -> LineEnding {
        // Character iteration folds CRLF into one grapheme cluster, so scan
        // UTF-8 bytes instead.
        var sawCarriageReturn = false
        for byte in text.utf8 {
            switch byte {
            case 0x0D:
                sawCarriageReturn = true
            case 0x0A:
                return sawCarriageReturn ? .crlf : .lf
            default:
                if sawCarriageReturn {
                    return .cr
                }
            }
        }
        return sawCarriageReturn ? .cr : .lf
    }
}
