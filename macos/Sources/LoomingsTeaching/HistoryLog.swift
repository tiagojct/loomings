import Darwin
import Foundation

/// One step of a document's writing history: what changed, in UTF-16, and
/// when. Every 200th entry also carries the whole text as a keyframe, so a
/// replay never reads more than 200 steps to rebuild any moment.
public struct HistoryEntry: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let location: Int
    public let deleted: Int
    public let inserted: String
    public let keyframe: String?

    public init(time: TimeInterval, location: Int, deleted: Int, inserted: String, keyframe: String? = nil) {
        self.time = time
        self.location = location
        self.deleted = deleted
        self.inserted = inserted
        self.keyframe = keyframe
    }
}

public enum HistoryLog {
    public static let keyframeInterval = 200

    /// The change from `old` to `new` as one replacement between their
    /// common prefix and suffix, or nil when they are equal. Boundaries never
    /// fall inside a surrogate pair.
    public static func entry(from old: String, to new: String, at time: TimeInterval) -> HistoryEntry? {
        guard old != new else { return nil }
        let a = Array(old.utf16)
        let b = Array(new.utf16)
        var prefix = 0
        while prefix < a.count, prefix < b.count, a[prefix] == b[prefix] { prefix += 1 }
        while prefix > 0, isLowSurrogate(b.indices.contains(prefix) ? b[prefix] : (a.indices.contains(prefix) ? a[prefix] : 0)) {
            prefix -= 1
        }
        var suffix = 0
        while suffix < a.count - prefix, suffix < b.count - prefix,
              a[a.count - 1 - suffix] == b[b.count - 1 - suffix] {
            suffix += 1
        }
        while suffix > 0, isLowSurrogate(b[b.count - suffix]) {
            suffix -= 1
        }
        let inserted = String(decoding: b[prefix..<(b.count - suffix)], as: UTF16.self)
        return HistoryEntry(time: time, location: prefix, deleted: a.count - suffix - prefix, inserted: inserted)
    }

    /// The text after entry `index`, rebuilt from the nearest keyframe.
    public static func reconstruct(_ entries: [HistoryEntry], upTo index: Int) -> String {
        guard !entries.isEmpty else { return "" }
        let last = min(max(0, index), entries.count - 1)
        var start = last
        while start > 0, entries[start].keyframe == nil { start -= 1 }
        let text = NSMutableString(string: entries[start].keyframe ?? "")
        var position = entries[start].keyframe == nil ? start : start + 1
        while position <= last {
            let entry = entries[position]
            let location = min(entry.location, text.length)
            let length = min(entry.deleted, text.length - location)
            text.replaceCharacters(in: NSRange(location: location, length: length), with: entry.inserted)
            position += 1
        }
        return text as String
    }

    private static func isLowSurrogate(_ unit: UInt16) -> Bool {
        unit >= 0xDC00 && unit <= 0xDFFF
    }
}

/// Where writing histories live: one JSON Lines file per document in
/// `~/Library/Application Support/Loomings/History/`, never next to the
/// document and never in a share link. A document is known by an identifier
/// kept in an extended attribute of its file, so it survives renames and
/// moves.
public final class HistoryStore: @unchecked Sendable {
    public static var defaultRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Loomings/History", isDirectory: true)
    }

    static let attributeName = "eu.tiagojacinto.loomings.history-id"

    public let root: URL
    private let lock = NSLock()
    private var lastText: [String: String] = [:]
    private var counts: [String: Int] = [:]

    public init(root: URL = HistoryStore.defaultRoot) {
        self.root = root
    }

    // MARK: Identity

    /// The file's identifier if it has one; never writes to the file.
    public func existingIdentifier(for file: URL) -> String? {
        Self.readAttribute(file)
    }

    public func identifier(for file: URL) throws -> String {
        if let existing = Self.readAttribute(file) { return existing }
        let id = UUID().uuidString
        try Self.writeAttribute(id, to: file)
        return id
    }

    private static func readAttribute(_ file: URL) -> String? {
        let size = getxattr(file.path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(file.path, attributeName, &buffer, size, 0, 0)
        guard read == size else { return nil }
        let value = String(decoding: buffer, as: UTF8.self)
        return UUID(uuidString: value) == nil ? nil : value
    }

    private static func writeAttribute(_ value: String, to file: URL) throws {
        let bytes = Array(value.utf8)
        guard setxattr(file.path, attributeName, bytes, bytes.count, 0, 0) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
    }

    // MARK: Recording switch

    private var switchesURL: URL { root.appendingPathComponent("recording.json") }

    private func switches() -> Set<String> {
        guard let data = try? Data(contentsOf: switchesURL),
              let ids = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return Set(ids)
    }

    public func isRecording(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return switches().contains(id)
    }

    public func setRecording(_ id: String, _ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        var ids = switches()
        if on { ids.insert(id) } else { ids.remove(id) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(ids.sorted()) {
            try? data.write(to: switchesURL, options: .atomic)
        }
    }

    // MARK: Entries

    private func fileURL(_ id: String) -> URL { root.appendingPathComponent("\(id).jsonl") }

    public func entries(for id: String) throws -> [HistoryEntry] {
        lock.lock(); defer { lock.unlock() }
        return try readEntries(id)
    }

    private func readEntries(_ id: String) throws -> [HistoryEntry] {
        let url = fileURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { try decoder.decode(HistoryEntry.self, from: Data($0.utf8)) }
    }

    /// Records `text` as the next step, if it changed since the last one.
    public func record(text: String, at time: TimeInterval, for id: String) throws {
        lock.lock(); defer { lock.unlock() }
        if counts[id] == nil {
            let existing = try readEntries(id)
            counts[id] = existing.count
            lastText[id] = HistoryLog.reconstruct(existing, upTo: existing.count - 1)
        }
        let count = counts[id] ?? 0
        let previous = lastText[id] ?? ""
        guard count == 0 || previous != text else { return }

        let entry: HistoryEntry
        if count % HistoryLog.keyframeInterval == 0 {
            entry = HistoryEntry(time: time, location: 0, deleted: (previous as NSString).length, inserted: text, keyframe: text)
        } else if let delta = HistoryLog.entry(from: previous, to: text, at: time) {
            entry = delta
        } else {
            return
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var line = try JSONEncoder().encode(entry)
        line.append(0x0A)
        let url = fileURL(id)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url, options: .atomic)
        }
        counts[id] = count + 1
        lastText[id] = text
    }

    public func delete(_ id: String) throws {
        lock.lock()
        let url = fileURL(id)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        counts[id] = nil
        lastText[id] = nil
        lock.unlock()
        setRecording(id, false)
    }
}
