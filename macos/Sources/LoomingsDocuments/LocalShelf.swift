import Foundation

public struct ShelfEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public var title: String
    public let createdAt: Date
    public var modifiedAt: Date
    public let contentFilename: String

    public init(
        id: UUID,
        title: String,
        createdAt: Date,
        modifiedAt: Date,
        contentFilename: String
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.contentFilename = contentFilename
    }
}

/// A local replacement for the browser's document shelf.
///
/// Every document is a plain Markdown file plus a small JSON sidecar. The
/// UUID in the filename is the stable identifier; titles live only in the
/// sidecar, so renaming a document never changes its identity. Content and
/// sidecar are written with `.atomic`, and a failed create removes the
/// half-written content rather than leaving an entry without metadata.
public final class LocalShelf {
    public static let shared = LocalShelf(root: LocalShelf.defaultRoot())

    public let root: URL

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private static let allowedExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root.standardizedFileURL
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Loomings", isDirectory: true)
            .appendingPathComponent("Shelf", isDirectory: true)
    }

    // MARK: - Creating and importing

    public func create(
        title: String,
        data: Data,
        fileExtension: String = "md"
    ) throws -> ShelfEntry {
        try ensureRoot()

        let id = UUID()
        let extensionName = Self.normalizedExtension(fileExtension)
        let filename = "\(id.uuidString).\(extensionName)"
        let contentURL = root.appendingPathComponent(filename)
        let now = Date()
        let entry = ShelfEntry(
            id: id,
            title: Self.normalizedTitle(title),
            createdAt: now,
            modifiedAt: now,
            contentFilename: filename
        )

        do {
            try data.write(to: contentURL, options: .atomic)
            try writeMetadata(entry)
        } catch {
            try? fileManager.removeItem(at: contentURL)
            throw error
        }
        return entry
    }

    public func create(title: String, text: String) throws -> ShelfEntry {
        let data = try TextFileCodec.encode(TextFile(text: text))
        return try create(title: title, data: data, fileExtension: "md")
    }

    public func importFile(at url: URL, title: String? = nil) throws -> ShelfEntry {
        let data = try Data(contentsOf: url)
        _ = try TextFileCodec.decode(data)

        let proposed = title ?? url.deletingPathExtension().lastPathComponent
        let extensionName = url.pathExtension.isEmpty ? "md" : url.pathExtension
        return try create(
            title: proposed.isEmpty ? "Imported Document" : proposed,
            data: data,
            fileExtension: extensionName
        )
    }

    // MARK: - Listing and reading

    public func entries() throws -> [ShelfEntry] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var result: [ShelfEntry] = []
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? decoder.decode(ShelfEntry.self, from: data) else {
                continue
            }
            guard fileManager.fileExists(atPath: contentURL(for: entry).path) else {
                continue
            }
            result.append(entry)
        }

        return result.sorted {
            if $0.modifiedAt != $1.modifiedAt {
                return $0.modifiedAt > $1.modifiedAt
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    public func entry(id: UUID) throws -> ShelfEntry? {
        let metadata = metadataURL(for: id)
        guard let data = try? Data(contentsOf: metadata) else { return nil }
        return try decoder.decode(ShelfEntry.self, from: data)
    }

    public func read(id: UUID) throws -> (entry: ShelfEntry, data: Data) {
        guard let entry = try entry(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: contentURL(for: entry))
        return (entry, data)
    }

    // MARK: - Updating

    public func update(id: UUID, data: Data) throws {
        guard let entry = try entry(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try data.write(to: contentURL(for: entry), options: .atomic)
        try touch(id: id)
    }

    public func updateTitle(id: UUID, title: String) throws {
        guard var entry = try entry(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        entry.title = Self.normalizedTitle(title)
        entry.modifiedAt = Date()
        try writeMetadata(entry)
    }

    public func touch(id: UUID, at date: Date = Date()) throws {
        guard var entry = try entry(id: id) else {
            throw CocoaError(.fileNoSuchFile)
        }
        entry.modifiedAt = date
        try writeMetadata(entry)
    }

    public func delete(id: UUID) throws {
        guard let entry = try entry(id: id) else { return }
        try? fileManager.removeItem(at: contentURL(for: entry))
        try? fileManager.removeItem(at: metadataURL(for: id))
    }

    // MARK: - Locations

    public func contentURL(for entry: ShelfEntry) -> URL {
        root.appendingPathComponent(entry.contentFilename)
    }

    public func metadataURL(for id: UUID) -> URL {
        root.appendingPathComponent("\(id.uuidString).json")
    }

    public func contains(_ url: URL) -> Bool {
        entry(containing: url) != nil
    }

    public func entry(containing url: URL) -> ShelfEntry? {
        let standardized = url.standardizedFileURL
        guard standardized.deletingLastPathComponent().path == root.path else {
            return nil
        }
        let filename = standardized.lastPathComponent
        return try? entries().first { $0.contentFilename == filename }
    }

    // MARK: - Helpers

    private func ensureRoot() throws {
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
    }

    private func writeMetadata(_ entry: ShelfEntry) throws {
        try ensureRoot()
        let data = try encoder.encode(entry)
        try data.write(to: metadataURL(for: entry.id), options: .atomic)
    }

    private static func normalizedExtension(_ value: String) -> String {
        let lower = value.lowercased()
        return allowedExtensions.contains(lower) ? lower : "md"
    }

    private static func normalizedTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}
