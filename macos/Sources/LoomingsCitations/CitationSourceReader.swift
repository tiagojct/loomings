import Foundation
import LoomingsDocuments

/// The cheap test that keeps JavaScript away from a document with no citation
/// keys. It is a gate, not a rule: when it says yes, the citation code decides.
public enum CitationGate {
    private static let keys = [Array("bibliography".utf8), Array("references".utf8)]
    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
    private static let colon = UInt8(ascii: ":")

    /// True when the text starts with `---`, and a line in the first 50 lines
    /// starts with `bibliography` or `references`, then spaces or tabs, then
    /// a colon (`KEY` in `src/citations/frontmatter.js`).
    public static func applies(to source: String) -> Bool {
        guard source.hasPrefix("---") else { return false }
        let bytes = source.utf8
        var start = bytes.startIndex
        for _ in 0..<50 {
            guard start < bytes.endIndex else { return false }
            let end = bytes[start...].firstIndex(of: 10) ?? bytes.endIndex
            let line = bytes[start..<end]
            if keys.contains(where: { starts(line, withKey: $0) }) { return true }
            start = end < bytes.endIndex ? bytes.index(after: end) : end
        }
        return false
    }

    private static func starts(_ line: Substring.UTF8View, withKey key: [UInt8]) -> Bool {
        guard line.starts(with: key) else { return false }
        return line.dropFirst(key.count).first { $0 != space && $0 != tab } == colon
    }
}

/// The result of one read of the files of a document.
public struct CitationLoad: Sendable {
    public let sources: CitationSources
    /// Each file that was tried, also when it is absent, with its stamp.
    public let files: [URL: FileStamp]

    /// True when a file changed, appeared or went away after this read.
    public func changedFiles() -> Bool {
        files.contains { FileChangeDetector.change(previous: $0.value, at: $0.key) != .none }
    }
}

/// Reads the files that the plan of the citation code names. The rules for
/// names are in `src/citations/library.js`. This type only reads by path.
public enum CitationSourceReader {
    /// A bigger file is not a bibliography.
    private static let sizeLimit = 64 * 1024 * 1024

    private enum Content {
        case text(String)
        case absent
        case unreadable
    }

    /// Call this off the main thread.
    /// - Parameter folder: the document's folder, or nil when it has none.
    public static func load(
        _ request: CitationSourceRequest,
        folder: URL?,
        engine: any CitationEngineProtocol
    ) throws -> CitationLoad {
        var known = CitationKnownFiles(noFolder: folder == nil)
        var texts: [String: String] = [:]
        var stamps: [URL: FileStamp] = [:]

        while true {
            let plan = try engine.resolveNative(request, known: known)
            if plan.done {
                let sources = sources(of: plan, texts: texts, engine: engine)
                return CitationLoad(sources: sources, files: stamps)
            }
            let wanted = plan.bibFiles.map { ($0, "bib") } + (plan.stylePath.map { [($0, "csl")] } ?? [])
            let unread = wanted.filter { !known.tried.contains($0.0) }
            guard !unread.isEmpty else {
                throw CitationEngineError.script("The citation files could not be resolved.")
            }
            for (name, kind) in unread {
                known.tried.append(name)
                guard let url = url(of: name, folder: folder) else { continue }
                // The stamp comes first: a write during the read is then a change.
                stamps[url] = FileStamp(url: url)
                switch content(of: url) {
                case .text(let text):
                    texts[name] = text
                    known.files.append(.init(name: name, kind: kind, text: kind == "csl" ? text : nil))
                case .absent:
                    break
                case .unreadable:
                    known.unreadable.append(name)
                }
            }
        }
    }

    private static func sources(
        of plan: CitationPlan,
        texts: [String: String],
        engine: any CitationEngineProtocol
    ) -> CitationSources {
        CitationSources(
            bibs: plan.bibFiles.compactMap { name in
                texts[name].map { CitationSources.Bib(name: name, text: $0) }
            },
            styleXml: plan.stylePath.flatMap { texts[$0] } ?? plan.styleId.flatMap(engine.bundledStyle),
            localeXml: engine.bundledLocale(plan.lang),
            fallbackLocaleXml: engine.bundledLocale(plan.fallbackLang),
            lang: plan.lang,
            missing: plan.missing,
            missingNotes: plan.missingNotes,
            styleError: plan.styleError
        )
    }

    /// A relative name needs the folder. The stamp of a link must be the
    /// stamp of its target, so the path is resolved here.
    private static func url(of name: String, folder: URL?) -> URL? {
        let path = (name as NSString).expandingTildeInPath
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path).resolvingSymlinksInPath()
        }
        return folder?.appendingPathComponent(path).resolvingSymlinksInPath()
    }

    private static func content(of url: URL) -> Content {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return .absent
        }
        // A device or a pipe can have no end.
        guard attributes[.type] as? FileAttributeType == .typeRegular else { return .absent }
        guard let size = (attributes[.size] as? NSNumber)?.intValue, size <= sizeLimit,
              let data = try? Data(contentsOf: url),
              let file = try? TextFileCodec.decode(data) else {
            return .unreadable
        }
        return .text(file.text)
    }
}
