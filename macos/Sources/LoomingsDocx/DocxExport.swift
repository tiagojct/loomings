import AppKit
import Foundation
import LoomingsMarkdown
import LoomingsPreview

/// Word export. It walks the cmark tree of the export text (the source with
/// its citations formatted and the reference list appended) and writes a DOCX
/// package. Paragraphs use the Word style ids Title, Heading1-6, Quote,
/// Bibliography, SourceCode and Hyperlink, as the web export does, so a Word
/// template restyles the file. The rules match `src/docx.js`.
public enum DocxExport {
    public enum Paper: Sendable {
        case a4
        case letter

        public static var current: Paper {
            switch Locale.current.region?.identifier {
            case "US", "LR", "MM": return .letter
            default: return .a4
            }
        }
    }

    /// - Parameters:
    ///   - markdown: the export text, with the frontmatter.
    ///   - bibliographyMarkdown: the reference list that ends `markdown`, if any.
    ///     Its paragraphs get the Bibliography style.
    ///   - documentURL: the base for relative image paths.
    public static func data(
        markdown: String,
        bibliographyMarkdown: String = "",
        documentURL: URL?,
        paper: Paper = .current
    ) -> Data {
        var writer = DocxWriter(documentURL: documentURL, paper: paper)
        return writer.build(markdown: markdown, bibliography: bibliographyMarkdown)
    }

    /// The `title:` and `lang:` of the frontmatter, and the text after it.
    static func split(_ markdown: String) -> (title: String?, lang: String?, body: String) {
        let text = markdown as NSString
        guard let range = MarkdownFrontmatter.range(in: markdown) else { return (nil, nil, markdown) }
        let head = text.substring(with: range)
        func value(_ key: String) -> String? {
            for line in head.split(whereSeparator: \.isNewline) {
                guard line.hasPrefix("\(key):") else { continue }
                var raw = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces)
                if let hash = raw.range(of: " #") { raw = String(raw[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
                if raw.count >= 2, let first = raw.first, first == "\"" || first == "'", raw.last == first {
                    raw = String(raw.dropFirst().dropLast())
                }
                return raw.isEmpty ? nil : raw
            }
            return nil
        }
        return (value("title"), value("lang"), text.substring(from: range.location + range.length))
    }
}

private struct Marks {
    var bold = false
    var italic = false
    var strike = false
    var code = false
    var sup = false
    var sub = false
    var link = false
}

private final class ListState {
    var numId: Int
    var level: Int
    var firstPending = true
    var checkbox: MarkdownCheckbox?
    init(numId: Int, level: Int, checkbox: MarkdownCheckbox? = nil) {
        self.numId = numId
        self.level = level
        self.checkbox = checkbox
    }
}

private struct Context {
    var style: String?
    var list: ListState?
}

private struct DocxWriter {
    let documentURL: URL?
    let paper: DocxExport.Paper

    private var relationships: [(id: String, type: String, target: String, external: Bool)] = []
    private var media: [(name: String, data: Data)] = []
    private var abstractNums: [String] = []
    private var nums: [(numId: Int, abstractId: Int)] = []
    private var bulletNumId = 0
    private var drawingId = 0

    private let maxImageWidth = 600.0 // pixels at 96 dpi: the text width of an A4 page with 2.5 cm margins

    init(documentURL: URL?, paper: DocxExport.Paper) {
        self.documentURL = documentURL
        self.paper = paper
    }

    // MARK: Package

    mutating func build(markdown: String, bibliography: String) -> Data {
        let parts = DocxExport.split(markdown)
        var body = parts.body
        var references = ""
        if !bibliography.isEmpty, body.hasSuffix(bibliography) {
            body = String(body.dropLast(bibliography.count))
            references = bibliography
        }

        bulletNumId = newNumbering(ordered: false, start: 1)
        var xml = ""
        let tree = MarkdownTree(parsing: body)
        var blocks = ""
        withExtendedLifetime(tree) {
            blocks = self.blocks(of: tree.document, Context())
            if !references.isEmpty {
                let refs = MarkdownTree(parsing: references)
                withExtendedLifetime(refs) {
                    blocks += self.blocks(of: refs.document, Context(style: "Bibliography"))
                }
            }
            if let title = parts.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
                var opensWithTitle = false
                if let first = tree.document.firstChild, first.kind == .heading, first.headingLevel == 1 {
                    opensWithTitle = plainText(first).trimmingCharacters(in: .whitespaces) == title
                }
                if !opensWithTitle {
                    xml += paragraph(style: "Title", runs: run(title, Marks()))
                }
            }
        }
        xml += blocks
        if xml.isEmpty { xml = "<w:p/>" }

        var zip = ZipWriter()
        zip.add("[Content_Types].xml", Data(contentTypes.utf8))
        zip.add("_rels/.rels", Data(rootRels.utf8))
        zip.add("docProps/core.xml", Data(core(title: parts.title).utf8))
        zip.add("word/document.xml", Data(documentXML(xml).utf8))
        zip.add("word/styles.xml", Data(stylesXML(lang: parts.lang ?? "en-US").utf8))
        zip.add("word/numbering.xml", Data(numberingXML().utf8))
        zip.add("word/_rels/document.xml.rels", Data(documentRels().utf8))
        for item in media { zip.add("word/media/\(item.name)", item.data) }
        return zip.finish()
    }

    // MARK: Blocks

    private mutating func blocks(of node: MarkdownNode, _ context: Context) -> String {
        var out = ""
        for child in node.children { out += block(child, context) }
        return out
    }

    private mutating func block(_ node: MarkdownNode, _ context: Context) -> String {
        switch node.kind {
        case .paragraph:
            return paragraphFor(node, context)
        case .heading:
            return paragraph(style: "Heading\(min(max(node.headingLevel, 1), 6))", runs: inline(node, Marks()))
        case .blockQuote:
            return blocks(of: node, Context(style: "Quote", list: context.list))
        case .list:
            return list(node, context)
        case .codeBlock:
            return code(node.literal)
        case .htmlBlock:
            return code(node.literal)
        case .thematicBreak:
            return "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"999999\"/></w:pBdr><w:spacing w:before=\"200\" w:after=\"200\"/></w:pPr></w:p>"
        case .table:
            return table(node) + "<w:p/>"
        default:
            return node.hasChildren ? blocks(of: node, context) : ""
        }
    }

    private mutating func paragraphFor(_ node: MarkdownNode, _ context: Context) -> String {
        var runs = inline(node, Marks())
        if let list = context.list, list.firstPending, let box = list.checkbox {
            runs = run(box == .checked ? "\u{2611} " : "\u{2610} ", Marks()) + runs
        }
        var numbering = ""
        var indent = ""
        if let list = context.list {
            if list.firstPending {
                list.firstPending = false
                numbering = "<w:numPr><w:ilvl w:val=\"\(list.level)\"/><w:numId w:val=\"\(list.numId)\"/></w:numPr>"
            } else {
                indent = "<w:ind w:left=\"\(720 * (list.level + 1))\"/>"
            }
        }
        return paragraph(style: context.style, numbering: numbering, extra: indent, runs: runs)
    }

    private mutating func list(_ node: MarkdownNode, _ context: Context) -> String {
        let level = context.list.map { min($0.level + 1, 8) } ?? 0
        let numId = node.isOrderedList
            ? newNumbering(ordered: true, start: max(node.listStart, 1))
            : bulletNumId
        var out = ""
        for item in node.children where item.kind == .item {
            let state = ListState(numId: numId, level: level, checkbox: item.checkbox)
            out += blocks(of: item, Context(style: context.style, list: state))
        }
        return out
    }

    private func code(_ literal: String) -> String {
        var lines = literal.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if lines.isEmpty { lines = [" "] }
        return lines.enumerated().map { index, line in
            let last = index == lines.count - 1
            return paragraph(
                style: "SourceCode",
                extra: last ? "<w:spacing w:after=\"160\"/>" : "",
                runs: "<w:r><w:rPr><w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\" w:cs=\"Menlo\"/></w:rPr><w:t xml:space=\"preserve\">\(escape(line.isEmpty ? " " : line))</w:t></w:r>"
            )
        }.joined()
    }

    private mutating func table(_ node: MarkdownNode) -> String {
        let alignments = node.columnAlignments
        var rows: [MarkdownNode] = []
        for row in node.children where row.kind == .tableHead || row.kind == .tableRow { rows.append(row) }
        let columns = max(rows.map { $0.childCount }.max() ?? 1, 1)
        let width = 9070 / columns
        var xml = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"5000\" w:type=\"pct\"/></w:tblPr><w:tblGrid>"
        xml += String(repeating: "<w:gridCol w:w=\"\(width)\"/>", count: columns)
        xml += "</w:tblGrid>"
        for row in rows {
            let header = row.kind == .tableHead
            xml += "<w:tr><w:trPr><w:cantSplit/>\(header ? "<w:tblHeader/>" : "")</w:trPr>"
            var column = 0
            for cell in row.children where cell.kind == .tableCell {
                var marks = Marks()
                marks.bold = header
                let align = column < alignments.count ? alignments[column] : nil
                let jc: String
                switch align {
                case .right: jc = "<w:jc w:val=\"right\"/>"
                case .center: jc = "<w:jc w:val=\"center\"/>"
                default: jc = ""
                }
                xml += "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/></w:tcPr>"
                xml += "<w:p><w:pPr>\(jc.isEmpty ? "" : "<w:spacing w:after=\"60\"/>" + jc)</w:pPr>\(inline(cell, marks))</w:p></w:tc>"
                column += 1
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>"
    }

    private func paragraph(style: String? = nil, numbering: String = "", extra: String = "", runs: String) -> String {
        var props = ""
        if let style { props += "<w:pStyle w:val=\"\(style)\"/>" }
        props += numbering
        props += extra
        return "<w:p>\(props.isEmpty ? "" : "<w:pPr>\(props)</w:pPr>")\(runs)</w:p>"
    }

    // MARK: Inline

    private mutating func inline(_ node: MarkdownNode, _ marks: Marks) -> String {
        var out = ""
        var current = marks
        for child in node.children {
            switch child.kind {
            case .text:
                out += run(child.literal, current)
            case .softBreak:
                out += run(" ", current)
            case .lineBreak:
                out += "<w:r><w:br/></w:r>"
            case .code:
                var m = current
                m.code = true
                out += run(child.literal, m)
            case .emphasis:
                var m = current
                m.italic = true
                out += inline(child, m)
            case .strong:
                var m = current
                m.bold = true
                out += inline(child, m)
            case .strikethrough:
                var m = current
                m.strike = true
                out += inline(child, m)
            case .link:
                out += link(child, current)
            case .image:
                out += image(child)
            case .inlineHTML:
                switch child.literal.lowercased().replacingOccurrences(of: " ", with: "") {
                case "<br>", "<br/>": out += "<w:r><w:br/></w:r>"
                case "<sup>": current.sup = true
                case "</sup>": current.sup = false
                case "<sub>": current.sub = true
                case "</sub>": current.sub = false
                case "<i>", "<em>": current.italic = true
                case "</i>", "</em>": current.italic = false
                case "<b>", "<strong>": current.bold = true
                case "</b>", "</strong>": current.bold = false
                default: break
                }
            default:
                if child.hasChildren { out += inline(child, current) } else if !child.literal.isEmpty { out += run(child.literal, current) }
            }
        }
        return out
    }

    private mutating func link(_ node: MarkdownNode, _ marks: Marks) -> String {
        let destination = node.destination ?? ""
        let lower = destination.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:") else {
            return inline(node, marks)
        }
        var m = marks
        m.link = true
        let id = addRelationship(
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink",
            target: destination, external: true
        )
        return "<w:hyperlink r:id=\"\(id)\">\(inline(node, m))</w:hyperlink>"
    }

    private mutating func image(_ node: MarkdownNode) -> String {
        let alt = plainText(node)
        let fallback = run("[image\(alt.isEmpty ? "" : ": " + alt)]", { var m = Marks(); m.italic = true; return m }())
        guard let raw = node.destination,
              case .image(let picture) = PreviewImageLoader.load(raw, baseURL: documentURL),
              let tiff = picture.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]),
              rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            return fallback
        }
        drawingId += 1
        let name = "image\(drawingId).png"
        media.append((name, png))
        let id = addRelationship(
            type: "http://schemas.openxmlformats.org/officeDocument/2006/relationships/image",
            target: "media/\(name)", external: false
        )
        let scale = Double(rep.pixelsWide) > maxImageWidth ? maxImageWidth / Double(rep.pixelsWide) : 1
        let cx = Int((Double(rep.pixelsWide) * scale * 9525).rounded())
        let cy = Int((Double(rep.pixelsHigh) * scale * 9525).rounded())
        let description = escape(alt.isEmpty ? "image" : alt)
        return """
        <w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0"><wp:extent cx="\(cx)" cy="\(cy)"/>\
        <wp:docPr id="\(drawingId)" name="Picture \(drawingId)" descr="\(description)"/>\
        <wp:cNvGraphicFramePr><a:graphicFrameLocks xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" noChangeAspect="1"/></wp:cNvGraphicFramePr>\
        <a:graphic xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">\
        <pic:pic xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:nvPicPr><pic:cNvPr id="\(drawingId)" name="\(name)"/><pic:cNvPicPr/></pic:nvPicPr>\
        <pic:blipFill><a:blip r:embed="\(id)"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>\
        <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(cx)" cy="\(cy)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>\
        </a:graphicData></a:graphic></wp:inline></w:drawing></w:r>
        """
    }

    private func run(_ text: String, _ marks: Marks) -> String {
        guard !text.isEmpty else { return "" }
        var props = ""
        if marks.link { props += "<w:rStyle w:val=\"Hyperlink\"/>" }
        if marks.code { props += "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\" w:cs=\"Menlo\"/>" }
        if marks.bold { props += "<w:b/>" }
        if marks.italic { props += "<w:i/>" }
        if marks.strike { props += "<w:strike/>" }
        if marks.code { props += "<w:sz w:val=\"20\"/>" }
        if marks.sup { props += "<w:vertAlign w:val=\"superscript\"/>" }
        if marks.sub { props += "<w:vertAlign w:val=\"subscript\"/>" }
        return "<w:r>\(props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>")<w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>"
    }

    private func plainText(_ node: MarkdownNode) -> String {
        var out = ""
        for child in node.children {
            switch child.kind {
            case .text, .code: out += child.literal
            case .softBreak, .lineBreak: out += " "
            default: out += plainText(child)
            }
        }
        return out
    }

    // MARK: Numbering and relationships

    private mutating func newNumbering(ordered: Bool, start: Int) -> Int {
        let abstractId = abstractNums.count
        var levels = ""
        for level in 0..<9 {
            let format = ordered ? "decimal" : "bullet"
            let text = ordered ? "%\(level + 1)." : ["\u{2022}", "\u{25E6}", "\u{25AA}"][level % 3]
            let font = ordered ? "" : "<w:rPr><w:rFonts w:ascii=\"Arial\" w:hAnsi=\"Arial\" w:hint=\"default\"/></w:rPr>"
            levels += "<w:lvl w:ilvl=\"\(level)\"><w:start w:val=\"\(level == 0 ? start : 1)\"/><w:numFmt w:val=\"\(format)\"/><w:lvlText w:val=\"\(text)\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"\(720 * (level + 1))\" w:hanging=\"360\"/></w:pPr>\(font)</w:lvl>"
        }
        abstractNums.append("<w:abstractNum w:abstractNumId=\"\(abstractId)\"><w:multiLevelType w:val=\"hybridMultilevel\"/>\(levels)</w:abstractNum>")
        let numId = nums.count + 1
        nums.append((numId, abstractId))
        return numId
    }

    private mutating func addRelationship(type: String, target: String, external: Bool) -> String {
        let id = "rId\(relationships.count + 10)"
        relationships.append((id, type, target, external))
        return id
    }

    // MARK: Parts

    private let wordNamespaces = "xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:wp=\"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing\""

    private var contentTypes: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/><Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/><Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/></Types>
        """
    }

    private var rootRels: String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/></Relationships>
        """
    }

    private func core(title: String?) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>\(escape(title ?? ""))</dc:title><dc:creator>Loomings</dc:creator></cp:coreProperties>
        """
    }

    private func documentXML(_ body: String) -> String {
        let size = paper == .letter ? "w:w=\"12240\" w:h=\"15840\"" : "w:w=\"11906\" w:h=\"16838\""
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document \(wordNamespaces)><w:body>\(body)<w:sectPr><w:pgSz \(size)/><w:pgMar w:top="1418" w:right="1418" w:bottom="1418" w:left="1418" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr></w:body></w:document>
        """
    }

    private func documentRels() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        xml += "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>"
        xml += "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering\" Target=\"numbering.xml\"/>"
        for rel in relationships {
            xml += "<Relationship Id=\"\(rel.id)\" Type=\"\(rel.type)\" Target=\"\(escape(rel.target))\"\(rel.external ? " TargetMode=\"External\"" : "")/>"
        }
        return xml + "</Relationships>"
    }

    private func numberingXML() -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<w:numbering \(wordNamespaces)>"
        xml += abstractNums.joined()
        for item in nums { xml += "<w:num w:numId=\"\(item.numId)\"><w:abstractNumId w:val=\"\(item.abstractId)\"/></w:num>" }
        return xml + "</w:numbering>"
    }

    private func stylesXML(lang: String) -> String {
        func style(_ id: String, _ name: String, run: String = "", paragraph: String = "", next: String = "Normal") -> String {
            "<w:style w:type=\"paragraph\" w:styleId=\"\(id)\"><w:name w:val=\"\(name)\"/><w:basedOn w:val=\"Normal\"/><w:next w:val=\"\(next)\"/><w:qFormat/>\(paragraph.isEmpty ? "" : "<w:pPr>\(paragraph)</w:pPr>")\(run.isEmpty ? "" : "<w:rPr>\(run)</w:rPr>")</w:style>"
        }
        func heading(_ level: Int, _ size: Int, _ before: Int) -> String {
            style("Heading\(level)", "heading \(level)", run: "<w:b/><w:sz w:val=\"\(size)\"/>", paragraph: "<w:keepNext/><w:spacing w:before=\"\(before)\" w:after=\"120\"/><w:outlineLvl w:val=\"\(level - 1)\"/>")
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:styles \(wordNamespaces)><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Georgia" w:hAnsi="Georgia" w:cs="Georgia" w:eastAsia="Georgia"/><w:sz w:val="22"/><w:lang w:val="\(escape(lang))"/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:spacing w:after="140" w:line="300" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
        <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>\
        <w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/><w:uiPriority w:val="1"/><w:semiHidden/></w:style>\
        <w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:basedOn w:val="DefaultParagraphFont"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>\
        \(style("Title", "Title", run: "<w:b/><w:sz w:val=\"48\"/>", paragraph: "<w:spacing w:after=\"240\"/>"))\
        \(heading(1, 36, 360))\(heading(2, 30, 300))\(heading(3, 26, 240))\(heading(4, 24, 200))\(heading(5, 22, 200))\(heading(6, 22, 200))\
        \(style("Quote", "Quote", run: "<w:i/><w:color w:val=\"555555\"/>", paragraph: "<w:pBdr><w:left w:val=\"single\" w:sz=\"12\" w:space=\"8\" w:color=\"999999\"/></w:pBdr><w:ind w:left=\"567\"/>"))\
        \(style("Bibliography", "Bibliography", paragraph: "<w:spacing w:after=\"100\"/><w:ind w:left=\"540\" w:hanging=\"540\"/>"))\
        \(style("SourceCode", "Source Code", run: "<w:rFonts w:ascii=\"Menlo\" w:hAnsi=\"Menlo\" w:cs=\"Menlo\"/><w:sz w:val=\"20\"/>", paragraph: "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"F4F4F4\"/><w:spacing w:after=\"0\" w:line=\"260\" w:lineRule=\"auto\"/><w:ind w:left=\"120\" w:right=\"120\"/>"))\
        <w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/><w:uiPriority w:val="99"/><w:semiHidden/><w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/><w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>\
        <w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/><w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/></w:tblBorders></w:tblPr></w:style>\
        </w:styles>
        """
    }

    private func escape(_ value: String) -> String {
        var out = ""
        out.reserveCapacity(value.count)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 has no place for most control characters.
                if scalar.value >= 0x20 || scalar == "\t" || scalar == "\n" || scalar == "\r" { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }
}
