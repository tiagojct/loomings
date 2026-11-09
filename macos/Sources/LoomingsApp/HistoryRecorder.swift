import Foundation
import LoomingsTeaching

/// Records a document's writing history when, and only when, the writer
/// turns it on for that document. At most one step every two seconds while
/// typing; the last change is flushed when the window closes. An unrecorded
/// file is never touched, not even its extended attributes.
@MainActor
final class HistoryRecorder {
    static let shared = HistoryStore()

    let store: HistoryStore
    private let clock: () -> TimeInterval
    private let minimumGap: TimeInterval = 2
    private var recordingID: String?
    private var lastRecorded: TimeInterval = -.infinity
    private var pending: String?

    init(store: HistoryStore = HistoryRecorder.shared, clock: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }) {
        self.store = store
        self.clock = clock
    }

    /// Called once when the history cannot be written (a full disk, a
    /// folder that cannot be made), with the reason.
    var onError: ((String) -> Void)?
    private var reportedError = false

    var isRecording: Bool { recordingID != nil }

    /// The last answer of `hasHistory`. A menu asks on every validation, and
    /// the answer costs a read of the path table and of the whole history.
    private var historyAnswer: (file: URL, has: Bool)?

    /// Whether this file has a history to replay or delete.
    func hasHistory(fileURL: URL?) -> Bool {
        guard let fileURL else { return false }
        if let historyAnswer, historyAnswer.file == fileURL { return historyAnswer.has }
        let has: Bool
        if let id = store.existingIdentifier(for: fileURL) {
            has = !((try? store.entries(for: id)) ?? []).isEmpty
        } else {
            has = false
        }
        historyAnswer = (fileURL, has)
        return has
    }

    /// Forget the last answer of `hasHistory`: another window, or another
    /// process, can record or delete the history of the same file.
    func forgetHistoryAnswer() {
        historyAnswer = nil
    }

    /// Picks up a recording switched on in an earlier session.
    func load(fileURL: URL?) {
        guard let fileURL, let id = store.existingIdentifier(for: fileURL), store.isRecording(id) else {
            recordingID = nil
            return
        }
        recordingID = id
    }

    func setRecording(_ on: Bool, fileURL: URL, text: String) {
        historyAnswer = nil
        if on {
            guard let id = try? store.identifier(for: fileURL) else { return }
            store.setRecording(id, true)
            recordingID = id
            record(text)
        } else {
            flush()
            if let id = recordingID { store.setRecording(id, false) }
            recordingID = nil
        }
    }

    func textChanged(_ text: String) {
        guard recordingID != nil else { return }
        if clock() - lastRecorded >= minimumGap {
            record(text)
        } else {
            pending = text
        }
    }

    func flush() {
        if let pending { record(pending) }
    }

    func entries(fileURL: URL?) -> [HistoryEntry] {
        guard let fileURL, let id = store.existingIdentifier(for: fileURL) else { return [] }
        return (try? store.entries(for: id)) ?? []
    }

    func deleteHistory() {
        historyAnswer = nil
        let id = recordingID
        pending = nil
        recordingID = nil
        if let id { try? store.delete(id) }
    }

    /// Deletes the history of a file that is not being recorded now.
    func deleteHistory(fileURL: URL?) {
        historyAnswer = nil
        if recordingID != nil { deleteHistory(); return }
        guard let fileURL, let id = store.existingIdentifier(for: fileURL) else { return }
        try? store.delete(id)
    }

    private func record(_ text: String) {
        guard let id = recordingID else { return }
        pending = nil
        lastRecorded = clock()
        do {
            try store.record(text: text, at: Date().timeIntervalSince1970, for: id)
            historyAnswer = nil
        } catch {
            guard !reportedError else { return }
            reportedError = true
            onError?(error.localizedDescription)
        }
    }
}
