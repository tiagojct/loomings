import CZlib
import Foundation

public enum ShareLinkError: LocalizedError, Equatable {
    case malformed
    case unknownFormat
    case tooLarge
    case compressionFailed
    case notShareLink

    public var errorDescription: String? {
        switch self {
        case .malformed:
            return "This share link is malformed."
        case .unknownFormat:
            return "This share link uses an unknown format."
        case .tooLarge:
            return "This share link is too large to open safely."
        case .compressionFailed:
            return "The document could not be compressed."
        case .notShareLink:
            return "This URL does not contain a Loomings share link."
        }
    }
}

public struct SharePayload: Sendable, Equatable {
    public let text: String
    public let family: String?
    public let mode: String?

    public init(text: String, family: String? = nil, mode: String? = nil) {
        self.text = text
        self.family = family
        self.mode = mode
    }
}

public enum ShareLink {
    public static let website = URL(string: "https://loomings.tiagojacinto.eu/app/")!
    /// Guard rails beyond the web app: a link cannot expand to an unbounded
    /// document in memory.
    public static let maximumPayloadLength = 4_000_000
    public static let maximumDecodedLength = 8_000_000

    public static func encode(_ text: String) throws -> String {
        guard let raw = text.data(using: .utf8) else {
            throw ShareLinkError.malformed
        }

        if let compressed = try? RawDeflate.deflate(raw) {
            let payload = "z." + base64URL(compressed)
            guard payload.utf8.count <= maximumPayloadLength else {
                throw ShareLinkError.tooLarge
            }
            return payload
        }

        let payload = "p." + base64URL(raw)
        guard payload.utf8.count <= maximumPayloadLength else {
            throw ShareLinkError.tooLarge
        }
        return payload
    }

    public static func decode(_ payload: String) throws -> String {
        guard payload.utf8.count <= maximumPayloadLength else {
            throw ShareLinkError.tooLarge
        }
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3, trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == "." else {
            throw ShareLinkError.malformed
        }
        let kind = trimmed.first
        let body = String(trimmed.dropFirst(2))
        guard let data = dataFromBase64URL(body) else {
            throw ShareLinkError.malformed
        }

        let decoded: Data
        switch kind {
        case "p":
            guard data.count <= maximumDecodedLength else {
                throw ShareLinkError.tooLarge
            }
            decoded = data
        case "z":
            decoded = try RawDeflate.inflate(data, maxOutput: maximumDecodedLength)
        default:
            throw ShareLinkError.unknownFormat
        }

        guard let text = String(data: decoded, encoding: .utf8) else {
            throw ShareLinkError.malformed
        }
        return text
    }

    public static func url(
        for text: String,
        family: String? = nil,
        mode: String? = nil
    ) throws -> URL {
        let payload = try encode(text)
        var queryItems: [URLQueryItem] = []
        if let family, !family.isEmpty {
            queryItems.append(URLQueryItem(name: "theme", value: family))
        }
        if let mode, !mode.isEmpty {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        var queryComponents = URLComponents()
        queryComponents.queryItems = queryItems.isEmpty ? nil : queryItems
        let query = queryComponents.percentEncodedQuery.map { "?\($0)" } ?? ""
        let value = website.absoluteString + query + "#d=\(payload)"
        guard let url = URL(string: value) else {
            throw ShareLinkError.malformed
        }
        return url
    }

    public static func parse(_ url: URL) throws -> SharePayload {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ShareLinkError.malformed
        }
        guard let fragment = components.fragment,
              let payload = payload(fromFragment: fragment) else {
            throw ShareLinkError.notShareLink
        }

        let text = try decode(payload)
        let family = components.queryItems?.first { $0.name == "theme" }?.value
        let mode = components.queryItems?.first { $0.name == "mode" }?.value
        return SharePayload(text: text, family: family, mode: mode)
    }

    /// Accepts both a full URL and a bare `d=…` fragment string.
    public static func parse(string: String) throws -> SharePayload {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return try parse(url)
        }
        if let payload = payload(fromFragment: trimmed) {
            return SharePayload(text: try decode(payload))
        }
        throw ShareLinkError.notShareLink
    }

    // MARK: - Encoding helpers

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func dataFromBase64URL(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }

    private static func payload(fromFragment fragment: String) -> String? {
        let value = fragment.hasPrefix("#") ? String(fragment.dropFirst()) : fragment
        for pair in value.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2, parts[0] == "d" {
                return String(parts[1])
            }
        }
        return nil
    }
}

private enum RawDeflate {
    static func deflate(_ data: Data) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status: Int32 = data.withUnsafeBytes { buffer in
            loomings_raw_deflate(
                buffer.bindMemory(to: UInt8.self).baseAddress,
                data.count,
                &output,
                &length
            )
        }
        guard status == 0, let output else {
            throw ShareLinkError.compressionFailed
        }
        defer { loomings_free(output) }
        return Data(bytes: output, count: length)
    }

    static func inflate(_ data: Data, maxOutput: Int) throws -> Data {
        var output: UnsafeMutablePointer<UInt8>?
        var length = 0
        let status: Int32 = data.withUnsafeBytes { buffer in
            loomings_raw_inflate(
                buffer.bindMemory(to: UInt8.self).baseAddress,
                data.count,
                &output,
                &length,
                maxOutput
            )
        }
        if status == -2 {
            throw ShareLinkError.tooLarge
        }
        guard status == 0, let output else {
            throw ShareLinkError.malformed
        }
        defer { loomings_free(output) }
        return Data(bytes: output, count: length)
    }
}
