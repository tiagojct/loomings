import CZlib
import Foundation

/// A minimal ZIP container for the DOCX package. Each entry is deflated
/// (raw DEFLATE through zlib) when that is smaller, else stored.
struct ZipWriter {
    private struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let size: UInt32
        let offset: UInt32
    }

    private var data = Data()
    private var entries: [Entry] = []

    mutating func add(_ name: String, _ content: Data) {
        let crc = Self.crc32(content)
        var method: UInt16 = 0
        var payload = content
        if let deflated = Self.deflate(content), deflated.count < content.count {
            method = 8
            payload = deflated
        }
        let nameBytes = Data(name.utf8)
        let offset = UInt32(data.count)
        append32(0x04034b50)
        append16(20)
        append16(0x0800) // UTF-8 names
        append16(method)
        append16(Self.dosTime)
        append16(Self.dosDate)
        append32(crc)
        append32(UInt32(payload.count))
        append32(UInt32(content.count))
        append16(UInt16(nameBytes.count))
        append16(0)
        data.append(nameBytes)
        data.append(payload)
        entries.append(Entry(
            name: name, method: method, crc: crc,
            compressedSize: UInt32(payload.count), size: UInt32(content.count), offset: offset
        ))
    }

    mutating func finish() -> Data {
        let directoryStart = UInt32(data.count)
        for entry in entries {
            let nameBytes = Data(entry.name.utf8)
            append32(0x02014b50)
            append16(20)
            append16(20)
            append16(0x0800)
            append16(entry.method)
            append16(Self.dosTime)
            append16(Self.dosDate)
            append32(entry.crc)
            append32(entry.compressedSize)
            append32(entry.size)
            append16(UInt16(nameBytes.count))
            append16(0)
            append16(0)
            append16(0)
            append16(0)
            append32(0)
            append32(entry.offset)
            data.append(nameBytes)
        }
        let directorySize = UInt32(data.count) - directoryStart
        append32(0x06054b50)
        append16(0)
        append16(0)
        append16(UInt16(entries.count))
        append16(UInt16(entries.count))
        append32(directorySize)
        append32(directoryStart)
        append16(0)
        return data
    }

    // 2024-01-01 00:00, so the file does not change from run to run.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = ((2024 - 1980) << 9) | (1 << 5) | 1

    private mutating func append16(_ value: UInt16) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8(value >> 8))
    }

    private mutating func append32(_ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) {
            data.append(UInt8((value >> UInt32(shift)) & 0xff))
        }
    }

    private static let table: [UInt32] = (0..<256).map { index in
        var c = UInt32(index)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: Data) -> UInt32 {
        var c: UInt32 = 0xffffffff
        for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xff)] ^ (c >> 8) }
        return c ^ 0xffffffff
    }

    private static func deflate(_ bytes: Data) -> Data? {
        guard !bytes.isEmpty else { return nil }
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status = bytes.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return loomings_raw_deflate(base, bytes.count, &output, &length)
        }
        guard status == 0, let output else { return nil }
        defer { loomings_free(output) }
        return Data(bytes: output, count: length)
    }
}
