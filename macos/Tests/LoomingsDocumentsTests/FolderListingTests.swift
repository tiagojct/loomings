import Foundation
import Testing
@testable import LoomingsDocuments

@Suite("Folder listing")
struct FolderListingTests {
    private func makeFolder(_ names: [String], folders: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("loomings-folder-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            try "x".write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        for name in folders {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
        return root
    }

    @Test("Folders come first, then writing files, in Finder order")
    func order() throws {
        let root = try makeFolder(["10.md", "2.md", "b.txt", "a.markdown"], folders: ["zeta", "Alpha"])
        defer { try? FileManager.default.removeItem(at: root) }
        let names = FolderListing.entries(in: root).map(\.name)
        #expect(names == ["Alpha", "zeta", "2.md", "10.md", "a.markdown", "b.txt"])
    }

    @Test("Other files, hidden names, node_modules and packages are left out")
    func skips() throws {
        let root = try makeFolder(
            ["poem.md", "photo.png", "data.csv", ".hidden.md", "NOTES.MD"],
            folders: ["node_modules", "Tool.app", ".git", "drafts"]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let names = FolderListing.entries(in: root).map(\.name)
        #expect(names == ["drafts", "NOTES.MD", "poem.md"])
    }

    @Test("A folder that cannot be read gives an empty list")
    func missing() {
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        #expect(FolderListing.entries(in: missing).isEmpty)
    }

    @Test("Each entry knows if it is a folder")
    func kinds() throws {
        let root = try makeFolder(["a.md"], folders: ["sub"])
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = FolderListing.entries(in: root)
        #expect(entries.map(\.isFolder) == [true, false])
    }
}
