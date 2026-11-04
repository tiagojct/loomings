import Foundation
import LoomingsCitations

/// Gives one document window its citation report. The window owns one engine,
/// made when a document first passes `CitationGate`. All work runs on a private
/// queue, after a pause in the typing, and never joins the parse. A report
/// comes back to the main actor, and a stale one is dropped.
@MainActor
final class CitationController {
    typealias EngineFactory = @Sendable () throws -> any CitationEngineProtocol

    /// What the preview does for the current text.
    enum PreviewText: Equatable {
        case render(String)
        /// A report is on the way. The last preview stays.
        case keepLast
    }

    /// The text to export. `status` says why the citations are not formatted.
    struct ExportText {
        let markdown: String
        let status: String?
    }

    private struct Request {
        let source: String
        let documentURL: URL?

        var folder: URL? { documentURL?.deletingLastPathComponent() }
    }

    var onReport: ((CitationReport) -> Void)?
    /// How long an export waits for its report.
    var exportLimit: TimeInterval = 10
    private(set) var droppedReports = 0
    var enginesCreated: Int { worker.enginesCreated }

    private let debounce: TimeInterval = 0.4
    private var worker: CitationWorker
    private var generation: UInt64 = 0
    private var requested: Request?
    private var pending: DispatchWorkItem?
    /// The newest report, with the text it belongs to.
    private var latest: (source: String, report: CitationReport)?

    init(makeEngine: @escaping EngineFactory = CitationController.bundledEngine) {
        worker = CitationWorker(makeEngine: makeEngine)
    }

    nonisolated static func bundledEngine() throws -> any CitationEngineProtocol {
        guard let root = Bundle.main.resourceURL else {
            throw CitationEngineError.bundleMissing("the app resources")
        }
        return try CitationEngine(resources: root.appendingPathComponent("Citations"))
    }

    func useEngineForTesting(_ engine: any CitationEngineProtocol) {
        worker = CitationWorker(makeEngine: { engine })
    }

    /// Asks for a report of `source` after a pause. Text with no citation keys
    /// costs only the gate.
    func update(source: String, documentURL: URL?) {
        guard CitationGate.applies(to: source) else {
            forget()
            return
        }
        if let requested, requested.documentURL == documentURL, requested.source == source { return }
        let request = Request(source: source, documentURL: documentURL)
        requested = request
        generation &+= 1
        worker.markNewest(generation)
        pending?.cancel()
        let token = generation
        let item = DispatchWorkItem { [weak self] in
            self?.start(request, generation: token)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    /// Reads the files again if they changed. The app calls this on activation.
    func checkFiles() {
        guard requested != nil else { return }
        let worker = self.worker
        worker.queue.async { [weak self] in
            guard worker.filesChanged() else { return }
            DispatchQueue.main.async {
                self?.requestAgain()
            }
        }
    }

    /// Ends the work for a window that closes.
    func close() {
        forget()
        onReport = nil
    }

    /// The report of exactly this text.
    func report(for source: String) -> CitationReport? {
        guard let latest, latest.source == source else { return nil }
        return latest.report
    }

    func previewText(for source: String) -> PreviewText {
        guard CitationGate.applies(to: source) else { return .render(source) }
        if let report = report(for: source) { return .render(report.markdownSource) }
        return latest == nil ? .render(source) : .keepLast
    }

    /// Calls `completion` on the main actor with the report's text for exactly
    /// this `source`, or with `source` and a status after `exportLimit`. The
    /// main thread does not wait.
    func exportText(source: String, documentURL: URL?, completion: @escaping (ExportText) -> Void) {
        guard CitationGate.applies(to: source) else {
            completion(ExportText(markdown: source, status: nil))
            return
        }
        if let report = report(for: source) {
            completion(Self.exportText(of: report))
            return
        }
        // The limit's timer outlives a quick report, and `completion` can hold
        // a window, so `finish` lets go of it on the first call.
        var waiting: ((ExportText) -> Void)? = completion
        let finish = { (text: ExportText) in
            guard let done = waiting else { return }
            waiting = nil
            done(text)
        }
        let request = Request(source: source, documentURL: documentURL)
        let worker = self.worker
        worker.queue.async {
            let report = worker.report(for: request.source, folder: request.folder)
            DispatchQueue.main.async {
                finish(Self.exportText(of: report))
            }
        }
        let limit = exportLimit
        DispatchQueue.main.asyncAfter(deadline: .now() + limit) {
            finish(ExportText(
                markdown: source,
                status: "The citations were not ready after \(Int(limit.rounded())) seconds, so the export shows the citation keys. Export again in a moment."
            ))
        }
    }

    /// A note with no place in the text is about a file or a failure, and the
    /// export can then show citation keys. A note about one key has a place.
    private static func exportText(of report: CitationReport) -> ExportText {
        let notes = report.notes.filter { $0.to == 0 }.prefix(3).map(\.message)
        return ExportText(
            markdown: report.markdownSource,
            status: notes.isEmpty ? nil : notes.joined(separator: " ")
        )
    }

    private func forget() {
        generation &+= 1
        worker.markNewest(generation)
        pending?.cancel()
        pending = nil
        requested = nil
        latest = nil
    }

    private func requestAgain() {
        guard let request = requested else { return }
        requested = nil
        update(source: request.source, documentURL: request.documentURL)
    }

    private func start(_ request: Request, generation: UInt64) {
        let worker = self.worker
        worker.queue.async { [weak self] in
            guard worker.isNewest(generation) else { return }
            let report = worker.report(for: request.source, folder: request.folder)
            DispatchQueue.main.async {
                self?.deliver(report, source: request.source, generation: generation)
            }
        }
    }

    private func deliver(_ report: CitationReport, source: String, generation: UInt64) {
        guard generation == self.generation else {
            droppedReports += 1
            return
        }
        latest = (source, report)
        onReport?(report)
    }
}

/// The state of one engine. Use the state only on `queue`. An engine call
/// waits, so it must not run on the main thread.
private final class CitationWorker: @unchecked Sendable {
    let queue = DispatchQueue(label: "eu.tiagojacinto.loomings.citation-controller", qos: .userInitiated)

    private let makeEngine: CitationController.EngineFactory
    private let lock = NSLock()
    private var newest: UInt64 = 0
    private var created = 0

    // Use these only on `queue`.
    private var engine: (any CitationEngineProtocol)?
    private var request: CitationSourceRequest?
    private var folder: URL?
    private var load: CitationLoad?

    init(makeEngine: @escaping CitationController.EngineFactory) {
        self.makeEngine = makeEngine
    }

    var enginesCreated: Int { lock.withLock { created } }

    func markNewest(_ generation: UInt64) {
        lock.withLock { newest = generation }
    }

    func isNewest(_ generation: UInt64) -> Bool {
        lock.withLock { newest == generation }
    }

    /// The sources change only when the frontmatter keys, the folder or a file
    /// changes, because a new set costs a new citeproc engine.
    func report(for source: String, folder: URL?) -> CitationReport {
        do {
            let engine = try currentEngine()
            let wanted = try engine.readMeta(source).sourceRequest
            if load == nil || wanted != request || folder != self.folder {
                let next = try CitationSourceReader.load(wanted, folder: folder, engine: engine)
                engine.setSources(next.sources)
                load = next
                request = wanted
                self.folder = folder
            }
            return engine.analyse(source)
        } catch {
            return CitationReport(failure: String(describing: error), source: source)
        }
    }

    func filesChanged() -> Bool {
        guard let load, load.changedFiles() else { return false }
        self.load = nil
        return true
    }

    private func currentEngine() throws -> any CitationEngineProtocol {
        if let engine { return engine }
        let made = try makeEngine()
        lock.withLock { created += 1 }
        engine = made
        return made
    }
}
