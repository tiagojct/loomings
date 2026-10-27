import Foundation
import Testing
@testable import LoomingsDocuments

@Suite("Local shelf")
struct LocalShelfTests {
    private func makeShelf() -> (LocalShelf, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-shelf-\(UUID().uuidString)", isDirectory: true)
        return (LocalShelf(root: root), root)
    }

    @Test("Create, list, read and delete keep the identifier stable")
    func lifecycle() throws {
        let (shelf, root) = makeShelf()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try shelf.create(title: "First", text: "# One\n")
        let second = try shelf.create(title: "Second", text: "# Two\n")
        #expect(first.id != second.id)

        let entries = try shelf.entries()
        #expect(entries.count == 2)
        #expect(entries.contains { $0.id == first.id })
        #expect(entries.contains { $0.id == second.id })

        let read = try shelf.read(id: first.id)
        #expect(read.entry.title == "First")
        #expect(String(data: read.data, encoding: .utf8) == "# One\n")

        try shelf.update(id: first.id, data: Data("# One, revised\n".utf8))
        let updated = try shelf.read(id: first.id)
        #expect(updated.entry.id == first.id)
        #expect(String(data: updated.data, encoding: .utf8) == "# One, revised\n")

        try shelf.updateTitle(id: first.id, title: "Renamed")
        #expect(try shelf.entry(id: first.id)?.title == "Renamed")
        #expect(try shelf.read(id: first.id).entry.id == first.id)

        try shelf.delete(id: second.id)
        #expect(try shelf.entries().count == 1)
        #expect(try shelf.entry(id: second.id) == nil)
    }

    @Test("Failed writes leave the previous content intact")
    func failedWriteKeepsOldContent() throws {
        let (shelf, root) = makeShelf()
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: root.path
            )
            try? FileManager.default.removeItem(at: root)
        }

        let entry = try shelf.create(title: "Safe", text: "original\n")
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: root.path
        )

        #expect(throws: (any Error).self) {
            try shelf.update(id: entry.id, data: Data("replacement\n".utf8))
        }

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: root.path
        )
        let read = try shelf.read(id: entry.id)
        #expect(String(data: read.data, encoding: .utf8) == "original\n")
    }

    @Test("Import refuses unsupported encodings and reports the file")
    func importValidation() throws {
        let (shelf, root) = makeShelf()
        defer { try? FileManager.default.removeItem(at: root) }

        let good = root.deletingLastPathComponent()
            .appendingPathComponent("loomings-import-\(UUID().uuidString).md")
        let bad = root.deletingLastPathComponent()
            .appendingPathComponent("loomings-import-\(UUID().uuidString).md")
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }

        try Data("imported\r\ntext\r\n".utf8).write(to: good)
        let entry = try shelf.importFile(at: good, title: "Imported")
        let read = try shelf.read(id: entry.id)
        #expect(String(data: read.data, encoding: .utf8) == "imported\r\ntext\r\n")

        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: bad)
        #expect(throws: TextFileError.unsupportedEncoding) {
            try shelf.importFile(at: bad)
        }
        #expect(try shelf.entries().count == 1)
    }

    @Test("Shelf membership is decided by location, not title")
    func containsURL() throws {
        let (shelf, root) = makeShelf()
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = try shelf.create(title: "Contained", text: "x")
        let content = shelf.contentURL(for: entry)
        #expect(shelf.contains(content))
        #expect(!shelf.contains(root.deletingLastPathComponent().appendingPathComponent("outside.md")))
        #expect(shelf.entry(containing: content)?.id == entry.id)
    }
}
