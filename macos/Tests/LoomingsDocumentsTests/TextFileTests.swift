import Foundation
import Testing
@testable import LoomingsDocuments

@Suite("Text file codec")
struct TextFileTests {
    @Test("UTF-8 round trip without a BOM")
    func utf8RoundTrip() throws {
        let original = TextFile(text: "Héading 🌊\n\nA line.\n")
        let data = try TextFileCodec.encode(original)
        let decoded = try TextFileCodec.decode(data)

        #expect(decoded == original)
        #expect(!decoded.hasBOM)
        #expect(decoded.lineEnding == .lf)
    }

    @Test("UTF-8 byte-order mark is preserved")
    func utf8BOM() throws {
        let original = TextFile(text: "# Title\n", encoding: .utf8, hasBOM: true)
        let data = try TextFileCodec.encode(original)
        #expect(Array(data.prefix(3)) == [0xEF, 0xBB, 0xBF])

        let decoded = try TextFileCodec.decode(data)
        #expect(decoded.hasBOM)
        #expect(decoded.text == "# Title\n")
        #expect(try TextFileCodec.encode(decoded) == data)
    }

    @Test("UTF-16 little and big endian round trip")
    func utf16RoundTrip() throws {
        for encoding in [TextFileEncoding.utf16LittleEndian, .utf16BigEndian] {
            let original = TextFile(text: "café 🌊\n", encoding: encoding, hasBOM: true)
            let data = try TextFileCodec.encode(original)
            let decoded = try TextFileCodec.decode(data)

            #expect(decoded.encoding == encoding)
            #expect(decoded.hasBOM)
            #expect(decoded.text == original.text)
            #expect(try TextFileCodec.encode(decoded) == data)
        }
    }

    @Test("CRLF and CR line endings survive editing")
    func lineEndingPreservation() throws {
        let crlf = try TextFileCodec.decode(Data("a\r\nb\r\n".utf8))
        #expect(crlf.text == "a\nb\n")
        #expect(crlf.lineEnding == .crlf)
        #expect(try TextFileCodec.encode(crlf) == Data("a\r\nb\r\n".utf8))

        let cr = try TextFileCodec.decode(Data("a\rb\r".utf8))
        #expect(cr.text == "a\nb\n")
        #expect(cr.lineEnding == .cr)
        #expect(try TextFileCodec.encode(cr) == Data("a\rb\r".utf8))
    }

    @Test("Mixed endings are written back in the detected style")
    func mixedEndingsNormalize() throws {
        let file = try TextFileCodec.decode(Data("a\r\nb\nc\r".utf8))
        #expect(file.text == "a\nb\nc\n")
        #expect(file.lineEnding == .crlf)
        #expect(try TextFileCodec.encode(file) == Data("a\r\nb\r\nc\r\n".utf8))
    }

    @Test("A non-UTF-8 file is refused, not guessed")
    func latin1IsRefused() {
        let latin1 = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])
        #expect(throws: TextFileError.unsupportedEncoding) {
            try TextFileCodec.decode(latin1)
        }
    }

    @Test("UTF-32 little-endian BOM is refused, not read as UTF-16")
    func utf32LittleEndianIsRefused() {
        let data = Data([0xFF, 0xFE, 0x00, 0x00, 0x61, 0x00, 0x00, 0x00])
        #expect(throws: TextFileError.unsupportedEncoding) {
            try TextFileCodec.decode(data)
        }
    }

    @Test("UTF-32 big-endian BOM is refused")
    func utf32BigEndianIsRefused() {
        let data = Data([0x00, 0x00, 0xFE, 0xFF, 0x00, 0x00, 0x00, 0x61])
        #expect(throws: TextFileError.unsupportedEncoding) {
            try TextFileCodec.decode(data)
        }
    }

    @Test("BOMless UTF-16 little-endian text is refused, not read as UTF-8")
    func bomlessUTF16LittleEndianIsRefused() {
        let data = Data([0x61, 0x00, 0x62, 0x00, 0x0A, 0x00])
        #expect(throws: TextFileError.unsupportedEncoding) {
            try TextFileCodec.decode(data)
        }
    }

    @Test("BOMless UTF-16 big-endian text is refused, not read as UTF-8")
    func bomlessUTF16BigEndianIsRefused() {
        let data = Data([0x00, 0x61, 0x00, 0x62, 0x00, 0x0A])
        #expect(throws: TextFileError.unsupportedEncoding) {
            try TextFileCodec.decode(data)
        }
    }

    @Test("BOMless UTF-8 without NUL bytes still opens")
    func bomlessUTF8StillOpens() throws {
        let file = try TextFileCodec.decode(Data("café\n".utf8))
        #expect(file.encoding == .utf8)
        #expect(!file.hasBOM)
        #expect(file.text == "café\n")
    }

    @Test("A UTF-8 BOM with invalid bytes is refused")
    func invalidBOMBodyIsRefused() {
        let data = Data([0xEF, 0xBB, 0xBF, 0xFF, 0xFE])
        #expect(throws: TextFileError.invalidText(.utf8)) {
            try TextFileCodec.decode(data)
        }
    }

    @Test("Text without a final newline keeps it that way")
    func trailingNewlinePreserved() throws {
        let original = TextFile(text: "no trailing newline")
        let decoded = try TextFileCodec.decode(try TextFileCodec.encode(original))
        #expect(decoded.text == "no trailing newline")
    }

    @Test("Mixed line endings are saved in the first style found")
    func mixedLineEndings() throws {
        // The editor addresses LF text, so a file that mixes styles can only
        // be written back in one. The first line ending decides which; this
        // pins that behaviour rather than leaving it to chance.
        let crlfFirst = try TextFileCodec.decode(Data("a\r\nb\nc\r\n".utf8))
        #expect(crlfFirst.lineEnding == .crlf)
        #expect(crlfFirst.text == "a\nb\nc\n")
        #expect(String(data: try TextFileCodec.encode(crlfFirst), encoding: .utf8) == "a\r\nb\r\nc\r\n")

        let lfFirst = try TextFileCodec.decode(Data("a\nb\r\nc\n".utf8))
        #expect(lfFirst.lineEnding == .lf)
        #expect(String(data: try TextFileCodec.encode(lfFirst), encoding: .utf8) == "a\nb\nc\n")
    }
}
