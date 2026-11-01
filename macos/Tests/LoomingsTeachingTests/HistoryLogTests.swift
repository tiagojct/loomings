import Foundation
import Testing
@testable import LoomingsTeaching

@Suite("Writing history")
struct HistoryLogTests {
    static func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("loomings-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("A delta is the changed middle between a common prefix and suffix")
    func deltaShape() throws {
        let entry = try #require(HistoryLog.entry(from: "the white whale", to: "the great white whale", at: 1))
        #expect(entry.location == 4)
        #expect(entry.deleted == 0)
        #expect(entry.inserted == "great ")
        #expect(HistoryLog.entry(from: "same", to: "same", at: 2) == nil)
    }

    @Test("A delta never splits a surrogate pair")
    func deltaKeepsSurrogatesWhole() throws {
        // 🌊 and 🌍 share their high surrogate (D83C).
        let entry = try #require(HistoryLog.entry(from: "a🌊b", to: "a🌍b", at: 0))
        #expect(entry.location == 1)
        #expect(entry.deleted == 2)
        #expect(entry.inserted == "🌍")
    }

    @Test("Every recorded state can be rebuilt, emoji and all")
    func deltaRoundTrip() throws {
        let store = HistoryStore(root: try Self.temporaryRoot())
        var generator = SystemRandomNumberGenerator()
        let pieces = ["a", "whale ", "🌊", "é", "\n", "**", "Ishmael", "e\u{301}"]
        var text = ""
        var states: [String] = []
        for step in 0..<300 {
            let ns = text as NSString
            var next = text
            if ns.length > 4, Bool.random(using: &generator) {
                let start = Int.random(in: 0..<(ns.length - 2), using: &generator)
                let range = (text as NSString).rangeOfComposedCharacterSequences(for: NSRange(location: start, length: 2))
                next = ns.replacingCharacters(in: range, with: pieces.randomElement(using: &generator)!)
            } else {
                next = text + pieces.randomElement(using: &generator)!
            }
            if next == text { next += "x" }
            text = next
            try store.record(text: text, at: TimeInterval(step), for: "doc")
            states.append(text)
        }
        let entries = try store.entries(for: "doc")
        #expect(entries.count == states.count)
        for index in states.indices {
            #expect(HistoryLog.reconstruct(entries, upTo: index) == states[index], "step \(index)")
        }
    }

    @Test("A full keyframe every 200 entries bounds how far back a rebuild reads")
    func keyframesBoundCost() throws {
        let store = HistoryStore(root: try Self.temporaryRoot())
        for step in 0..<450 {
            try store.record(text: String(repeating: "x", count: step + 1), at: TimeInterval(step), for: "doc")
        }
        let entries = try store.entries(for: "doc")
        let keyframes = entries.indices.filter { entries[$0].keyframe != nil }
        #expect(keyframes == [0, 200, 400])
        #expect(HistoryLog.reconstruct(entries, upTo: 449) == String(repeating: "x", count: 450))
    }

    @Test("A recorded file keeps its history when renamed or moved")
    func historyFollowsRename() throws {
        let root = try Self.temporaryRoot()
        let store = HistoryStore(root: root.appendingPathComponent("History"))
        let file = root.appendingPathComponent("draft.md")
        try "draft".write(to: file, atomically: true, encoding: .utf8)
        let id = try store.identifier(for: file)
        let moved = root.appendingPathComponent("final.md")
        try FileManager.default.moveItem(at: file, to: moved)
        #expect(try store.identifier(for: moved) == id)
        let other = root.appendingPathComponent("other.md")
        try "other".write(to: other, atomically: true, encoding: .utf8)
        #expect(try store.identifier(for: other) != id)
    }

    @Test("Recording is off until turned on, and the choice persists")
    func notRecordingByDefault() throws {
        let root = try Self.temporaryRoot()
        let store = HistoryStore(root: root)
        #expect(!store.isRecording("doc"))
        store.setRecording("doc", true)
        #expect(HistoryStore(root: root).isRecording("doc"))
        store.setRecording("doc", false)
        #expect(!HistoryStore(root: root).isRecording("doc"))
    }

    @Test("Deleting history removes its file and its recording switch")
    func deleteRemovesFile() throws {
        let root = try Self.temporaryRoot()
        let store = HistoryStore(root: root)
        store.setRecording("doc", true)
        try store.record(text: "one", at: 1, for: "doc")
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("doc.jsonl").path))
        try store.delete("doc")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("doc.jsonl").path))
        #expect(try store.entries(for: "doc").isEmpty)
        #expect(!store.isRecording("doc"))
    }

    @Test("A damaged line is skipped, and recording goes on")
    func corruptLineIsSkipped() throws {
        let root = try Self.temporaryRoot()
        let store = HistoryStore(root: root)
        for (step, text) in ["one", "one two", "one two three"].enumerated() {
            try store.record(text: text, at: TimeInterval(step), for: "doc")
        }
        let handle = try FileHandle(forWritingTo: root.appendingPathComponent("doc.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"time\": 3, \"locat".utf8))
        try handle.close()
        let fresh = HistoryStore(root: root)
        #expect(try fresh.entries(for: "doc").count == 3)
        try fresh.record(text: "one two three four", at: 4, for: "doc")
        let entries = try fresh.entries(for: "doc")
        #expect(entries.count == 4)
        #expect(HistoryLog.reconstruct(entries, upTo: 3) == "one two three four")
    }

    @Test("A copy of a recorded file gets its own history")
    func copyGetsItsOwnHistory() throws {
        let root = try Self.temporaryRoot()
        let store = HistoryStore(root: root.appendingPathComponent("History"))
        let original = root.appendingPathComponent("essay.md")
        try "essay".write(to: original, atomically: true, encoding: .utf8)
        let id = try store.identifier(for: original)
        let copy = root.appendingPathComponent("essay copy.md")
        try FileManager.default.copyItem(at: original, to: copy)
        #expect(store.existingIdentifier(for: copy) == nil, "a copy is not taken for the original")
        let copyID = try store.identifier(for: copy)
        #expect(copyID != id)
        #expect(store.existingIdentifier(for: original) == id)
        #expect(store.existingIdentifier(for: copy) == copyID)
    }
}
