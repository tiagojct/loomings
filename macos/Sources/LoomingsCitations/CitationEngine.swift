import Foundation
import JavaScriptCore

public enum CitationEngineError: Error, Equatable, CustomStringConvertible {
    /// The resources folder has no `citations.js`.
    case bundleMissing(String)
    /// The citation code failed, or its output cannot be read.
    case script(String)
    /// `setCitationMeta` refused the change. The message is for the writer.
    case refused(String)

    public var description: String {
        switch self {
        case .bundleMissing(let path): return "The citation code is missing: \(path)"
        case .script(let message), .refused(let message): return message
        }
    }
}

/// What the citation controller needs from an engine. The self-test puts a
/// slow engine in its place.
public protocol CitationEngineProtocol: AnyObject, Sendable {
    func setSources(_ sources: CitationSources)
    func analyse(_ source: String) -> CitationReport
    func readMeta(_ source: String) throws -> CitationMeta
    func resolveNative(_ request: CitationSourceRequest, known: CitationKnownFiles) throws -> CitationPlan
    func setMeta(_ source: String, key: String, value: String?) throws -> String
    func fileChange(_ source: String, name: String, path: String) throws -> CitationMetaChange
    func addBibliography(_ source: String, path: String) throws -> String
    func referenceChoices(_ source: String) throws -> CitationChoices
    func insertCitation(_ source: String, position: Int, key: String) throws -> CitationInsertion
    func bundledStyle(_ id: String) -> String?
    func bundledLocale(_ tag: String) -> String?
}

/// Runs the citation code of `src/citations` in JavaScriptCore, so that its
/// rules are not repeated in Swift.
///
/// One `JSContext` is confined to one private serial queue, and each method
/// waits on that queue, so the work runs while the caller waits. A call can
/// take 500 ms: do not call from the main thread. The bundle loads on the
/// first call that needs it, so a document with no citations costs nothing.
/// `init` only finds the file.
public final class CitationEngine: CitationEngineProtocol, @unchecked Sendable {
    private let resources: URL
    private let queue = DispatchQueue(label: "eu.tiagojacinto.loomings.citations", qos: .userInitiated)

    // Use these only on `queue`.
    private var context: JSContext?
    private var api: JSValue?
    private var loadFailure: String?
    private var sourcesFailure: String?

    /// - Parameter resources: the folder that holds `citations.js`, `styles/`
    ///   and `locales/`.
    public init(resources: URL) throws {
        let bundle = resources.appendingPathComponent("citations.js")
        guard FileManager.default.isReadableFile(atPath: bundle.path) else {
            throw CitationEngineError.bundleMissing(bundle.path)
        }
        self.resources = resources
    }

    /// A failure here gives a note in the next report.
    public func setSources(_ sources: CitationSources) {
        let json: String
        do {
            json = String(decoding: try JSONEncoder().encode(sources), as: UTF8.self)
        } catch {
            queue.sync { sourcesFailure = String(describing: error) }
            return
        }
        queue.sync {
            do {
                _ = try autoreleasepool { try invoke("setSources", [json]) }
                sourcesFailure = nil
            } catch {
                sourcesFailure = String(describing: error)
            }
        }
    }

    /// A failure gives an empty report with one note. The context stays usable.
    public func analyse(_ source: String) -> CitationReport {
        queue.sync {
            do {
                if let sourcesFailure { throw CitationEngineError.script(sourcesFailure) }
                return try call("analyse", [source])
            } catch {
                return CitationReport(failure: String(describing: error), source: source)
            }
        }
    }

    public func readMeta(_ source: String) throws -> CitationMeta {
        try queue.sync { try call("readMeta", [source]) }
    }

    /// The next step to find the files of a document.
    public func resolveNative(_ request: CitationSourceRequest, known: CitationKnownFiles) throws -> CitationPlan {
        let encoder = JSONEncoder()
        let meta = String(decoding: try encoder.encode(request), as: UTF8.self)
        let files = String(decoding: try encoder.encode(known), as: UTF8.self)
        return try queue.sync { try call("resolveNative", [meta, files]) }
    }

    /// Sets or removes one frontmatter key. A nil value removes the key.
    /// - Parameter key: `bibliography`, `csl` or `references`.
    public func setMeta(_ source: String, key: String, value: String?) throws -> String {
        try queue.sync { try call("setMeta", [source, key, value ?? NSNull()]) }
    }

    /// The change that puts the file at `path` in the place of the missing
    /// file `name`. Give the result to `setMeta`.
    public func fileChange(_ source: String, name: String, path: String) throws -> CitationMetaChange {
        try queue.sync { try call("fileChange", [source, name, path]) }
    }

    /// Adds a chosen file to `bibliography`, and gives the changed text.
    public func addBibliography(_ source: String, path: String) throws -> String {
        try queue.sync { try call("addBibliography", [source, path]) }
    }

    /// The checked items of the References menu.
    public func referenceChoices(_ source: String) throws -> CitationChoices {
        try queue.sync { try call("referenceChoices", [source]) }
    }

    /// The text to insert for `key`. `position` is the end of the selection.
    public func insertCitation(_ source: String, position: Int, key: String) throws -> CitationInsertion {
        try queue.sync { try call("insertCitation", [source, position, key]) }
    }

    public func checkStyle(_ xml: String) throws -> CitationStyleCheck {
        try queue.sync { try call("checkStyle", [xml]) }
    }

    /// The text of a bundled style. These reads use no JavaScript.
    public func bundledStyle(_ id: String) -> String? {
        readResource("styles/\(id).csl", name: id)
    }

    /// The text of a bundled locale, for a tag such as `pt-PT`.
    public func bundledLocale(_ tag: String) -> String? {
        readResource("locales/locales-\(tag).xml", name: tag)
    }

    private func readResource(_ path: String, name: String) -> String? {
        guard !name.contains("/") else { return nil }
        return try? String(contentsOf: resources.appendingPathComponent(path), encoding: .utf8)
    }

    // MARK: On the queue

    /// Each function of the JavaScript API gives JSON. The pool is here because
    /// `queue.sync` can run on the caller's thread, which can have no pool.
    private func call<Result: Decodable>(_ name: String, _ arguments: [Any]) throws -> Result {
        try autoreleasepool {
            let value = try invoke(name, arguments)
            guard value.isString, let text = value.toString() else {
                throw CitationEngineError.script("The citation code gave no text.")
            }
            do {
                return try JSONDecoder().decode(Result.self, from: Data(text.utf8))
            } catch {
                throw CitationEngineError.script("The citation code gave text that cannot be read.")
            }
        }
    }

    /// The start of each message from `setCitationMeta`.
    private static let refusal = "setCitationMeta: "

    private func invoke(_ name: String, _ arguments: [Any]) throws -> JSValue {
        let (context, api) = try loaded()
        context.exception = nil
        let result = api.invokeMethod(name, withArguments: arguments)
        if let exception = context.exception {
            context.exception = nil
            let message = exception.forProperty("message")?.toString() ?? ""
            if message.hasPrefix(Self.refusal) {
                let reason = message.dropFirst(Self.refusal.count)
                throw CitationEngineError.refused(reason.prefix(1).uppercased() + reason.dropFirst())
            }
            throw CitationEngineError.script("The citations could not be formatted: \(exception)")
        }
        guard let result else { throw CitationEngineError.script("The citation code gave no text.") }
        return result
    }

    private func loaded() throws -> (JSContext, JSValue) {
        if let context, let api { return (context, api) }
        if let loadFailure { throw CitationEngineError.script(loadFailure) }
        do {
            let result = try load()
            context = result.0
            api = result.1
            return result
        } catch {
            loadFailure = String(describing: error)
            throw error
        }
    }

    private func load() throws -> (JSContext, JSValue) {
        let bundle = resources.appendingPathComponent("citations.js")
        let script: String
        do {
            script = try String(contentsOf: bundle, encoding: .utf8)
        } catch {
            throw CitationEngineError.script("The citation code could not be read.")
        }
        guard let context = JSContext() else {
            throw CitationEngineError.script("The citation code could not start.")
        }
        context.name = "Loomings citations"
        context.evaluateScript(script, withSourceURL: bundle)
        if let exception = context.exception {
            throw CitationEngineError.script("The citation code could not start: \(exception)")
        }
        guard let api = context.objectForKeyedSubscript("LoomingsCitations"), api.isObject else {
            throw CitationEngineError.script("The citation code could not start.")
        }
        return (context, api)
    }
}

extension CitationReport {
    /// The report of a failure: the session's empty report with one note.
    public init(failure message: String, source: String) {
        citations = []
        bibliography = []
        bibliographyMarkdown = ""
        library = []
        notes = [Note(from: 0, to: 0, message: message, file: nil, line: 0)]
        markdownSource = source
    }
}
