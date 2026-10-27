import Foundation

/// Tracks which content generation was last written, so a save that finishes
/// after newer edits can never mark those edits saved.
///
/// Generations are monotonic and come from the editor. Recording an older
/// snapshot than one already recorded is ignored: overlapping saves can
/// complete out of order, and the newest written generation wins.
public struct SaveGeneration: Sendable, Equatable {
    public private(set) var savedGeneration: UInt64

    public init(savedGeneration: UInt64 = 0) {
        self.savedGeneration = savedGeneration
    }

    public func isEdited(currentGeneration: UInt64) -> Bool {
        currentGeneration != savedGeneration
    }

    public mutating func recordSave(snapshot: UInt64) {
        guard snapshot > savedGeneration else { return }
        savedGeneration = snapshot
    }
}

public struct FileStamp: Sendable, Equatable {
    public let exists: Bool
    public let modificationDate: Date?
    public let size: Int?

    public init(exists: Bool, modificationDate: Date?, size: Int?) {
        self.exists = exists
        self.modificationDate = modificationDate
        self.size = size
    }

    public init(url: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            self.init(exists: false, modificationDate: nil, size: nil)
            return
        }
        self.init(
            exists: true,
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.intValue
        )
    }
}

public enum ExternalFileChange: Sendable, Equatable {
    case none
    case modified
    case deleted
}

public enum FileChangeDetector {
    public static func change(previous: FileStamp, at url: URL) -> ExternalFileChange {
        let current = FileStamp(url: url)
        if previous.exists, !current.exists {
            return .deleted
        }
        if !previous.exists, current.exists {
            return .modified
        }
        guard previous.exists else { return .none }
        if previous.modificationDate != current.modificationDate || previous.size != current.size {
            return .modified
        }
        return .none
    }
}
