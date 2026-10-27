import Foundation
import Testing
@testable import LoomingsDocuments

@Suite("Save generation and external changes")
struct SaveStateTests {
    @Test("A completed older save never clears newer edits")
    func olderSaveDoesNotClearNewerEdits() {
        var state = SaveGeneration()
        #expect(state.isEdited(currentGeneration: 5))

        state.recordSave(snapshot: 5)
        #expect(!state.isEdited(currentGeneration: 5))

        // Edits arrive while a save is in flight.
        #expect(state.isEdited(currentGeneration: 6))

        // The save that started at generation 5 completes late.
        state.recordSave(snapshot: 5)
        #expect(state.isEdited(currentGeneration: 6))

        // A save started after the edit completes.
        state.recordSave(snapshot: 6)
        #expect(!state.isEdited(currentGeneration: 6))
    }

    @Test("Saves completing out of order cannot rewind the saved generation")
    func outOfOrderSavesAreIgnored() {
        var state = SaveGeneration()
        state.recordSave(snapshot: 9)
        state.recordSave(snapshot: 4)
        #expect(state.savedGeneration == 9)
        #expect(state.isEdited(currentGeneration: 8))
        #expect(!state.isEdited(currentGeneration: 9))
    }

    @Test("External modification and deletion are detected")
    func externalChanges() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-change-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        try Data("one".utf8).write(to: url)
        let stamp = FileStamp(url: url)
        #expect(stamp.exists)
        #expect(FileChangeDetector.change(previous: stamp, at: url) == .none)

        try Data("two two".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(30)],
            ofItemAtPath: url.path
        )
        #expect(FileChangeDetector.change(previous: stamp, at: url) == .modified)

        let updated = FileStamp(url: url)
        try FileManager.default.removeItem(at: url)
        #expect(FileChangeDetector.change(previous: updated, at: url) == .deleted)
    }

    @Test("A file that did not exist and now does is a modification")
    func newFileIsModification() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-new-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }

        let missing = FileStamp(url: url)
        #expect(!missing.exists)
        try Data("x".utf8).write(to: url)
        #expect(FileChangeDetector.change(previous: missing, at: url) == .modified)
    }
}
