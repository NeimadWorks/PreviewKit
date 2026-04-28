// OOXMLParser — minimal OOXML (DOCX / XLSX / PPTX) inspector.
//
// OOXML files are ZIP containers of XML. We don't decompress the whole
// thing into memory; we shell out to `/usr/bin/unzip -p <file> <entry>`
// for each entry we need, stream into `Foundation.XMLParser`, and tally
// counters. No external deps.
//
// Per ADR-017 + the v1 spec, this is read-only and never alters the
// underlying archive — the round-trip guarantee is the responsibility
// of the compression pipeline, not the preview renderer.

import Foundation

// MARK: - Public surface

public struct OOXMLSummary: Sendable, Hashable {

    // Common
    public let kind: OfficeKind
    public let hasMacros: Bool

    // Word-specific
    public let wordCount: Int
    public let paragraphCount: Int
    public let trackedChangeCount: Int
    public let commentCount: Int

    // Excel-specific
    public let sheetCount: Int
    public let formulaCount: Int
    public let namedRangeCount: Int

    // PowerPoint-specific
    public let slideCount: Int
    public let slideLayoutCount: Int
    public let hasSpeakerNotes: Bool

    public init(
        kind: OfficeKind,
        hasMacros: Bool = false,
        wordCount: Int = 0,
        paragraphCount: Int = 0,
        trackedChangeCount: Int = 0,
        commentCount: Int = 0,
        sheetCount: Int = 0,
        formulaCount: Int = 0,
        namedRangeCount: Int = 0,
        slideCount: Int = 0,
        slideLayoutCount: Int = 0,
        hasSpeakerNotes: Bool = false
    ) {
        self.kind = kind
        self.hasMacros = hasMacros
        self.wordCount = wordCount
        self.paragraphCount = paragraphCount
        self.trackedChangeCount = trackedChangeCount
        self.commentCount = commentCount
        self.sheetCount = sheetCount
        self.formulaCount = formulaCount
        self.namedRangeCount = namedRangeCount
        self.slideCount = slideCount
        self.slideLayoutCount = slideLayoutCount
        self.hasSpeakerNotes = hasSpeakerNotes
    }
}

public enum OfficeKind: String, Sendable, Hashable {
    case docx, xlsx, pptx, unknown

    public init(extension ext: String) {
        switch ext.lowercased() {
        case "docx", "docm": self = .docx
        case "xlsx", "xlsm": self = .xlsx
        case "pptx", "pptm": self = .pptx
        default:             self = .unknown
        }
    }

    public static func macros(extension ext: String) -> Bool {
        ["docm", "xlsm", "pptm"].contains(ext.lowercased())
    }

    public var displayLabel: String {
        switch self {
        case .docx:    return "Word"
        case .xlsx:    return "Excel"
        case .pptx:    return "PowerPoint"
        case .unknown: return "Office"
        }
    }
}

public enum OOXMLParserError: Error, CustomStringConvertible, Sendable {
    case unzipFailed(String)
    case parseFailed(String)

    public var description: String {
        switch self {
        case .unzipFailed(let msg): return "Unzip failed: \(msg)"
        case .parseFailed(let msg): return "XML parse failed: \(msg)"
        }
    }
}

// MARK: - Parser entry point

public enum OOXMLParser {

    /// Extract a summary from a file on disk. The file extension drives
    /// which entries we inspect; macro-enabled extensions flag the
    /// `hasMacros` bit.
    public static func summarise(fileURL: URL) throws -> OOXMLSummary {
        let ext = fileURL.pathExtension
        let kind = OfficeKind(extension: ext)
        let macros = OfficeKind.macros(extension: ext)

        switch kind {
        case .docx: return try parseDocx(at: fileURL, macros: macros)
        case .xlsx: return try parseXlsx(at: fileURL, macros: macros)
        case .pptx: return try parsePptx(at: fileURL, macros: macros)
        case .unknown: return OOXMLSummary(kind: .unknown, hasMacros: macros)
        }
    }

    // MARK: - DOCX

    private static func parseDocx(at url: URL, macros: Bool) throws -> OOXMLSummary {
        let xml = try unzipEntry(at: url, entry: "word/document.xml")
        let stats = try DocxTextVisitor.visit(xml: xml)
        let comments = (try? unzipEntry(at: url, entry: "word/comments.xml"))
            .map { CommentCountVisitor.visit(xml: $0) } ?? 0

        return OOXMLSummary(
            kind: .docx,
            hasMacros: macros,
            wordCount: stats.words,
            paragraphCount: stats.paragraphs,
            trackedChangeCount: stats.trackedChanges,
            commentCount: comments
        )
    }

    // MARK: - XLSX

    private static func parseXlsx(at url: URL, macros: Bool) throws -> OOXMLSummary {
        let workbook = try unzipEntry(at: url, entry: "xl/workbook.xml")
        let wb = XlsxWorkbookVisitor.visit(xml: workbook)

        // Count formulas across all sheets. We only look at the first few
        // sheets if there are many — an XLSX with 200 sheets shouldn't
        // freeze the renderer.
        var formulaTally = 0
        for index in 1...min(wb.sheetCount, 16) {
            let entry = "xl/worksheets/sheet\(index).xml"
            if let sheet = try? unzipEntry(at: url, entry: entry) {
                formulaTally += XlsxFormulaVisitor.visit(xml: sheet)
            }
        }

        return OOXMLSummary(
            kind: .xlsx,
            hasMacros: macros,
            sheetCount: wb.sheetCount,
            formulaCount: formulaTally,
            namedRangeCount: wb.namedRangeCount
        )
    }

    // MARK: - PPTX

    private static func parsePptx(at url: URL, macros: Bool) throws -> OOXMLSummary {
        let presentation = try unzipEntry(at: url, entry: "ppt/presentation.xml")
        let p = PptxPresentationVisitor.visit(xml: presentation)

        // Count slide layouts by peeking at the content types map (cheap,
        // central catalog of every ppart in the archive).
        let contentTypes = (try? unzipEntry(at: url, entry: "[Content_Types].xml")) ?? Data()
        let layouts = PptxLayoutVisitor.visit(xml: contentTypes)

        // Speaker-notes presence: any `notesSlide*.xml` in the archive.
        let notesPresent = (try? unzipList(at: url).contains {
            $0.contains("notesSlide") && $0.hasSuffix(".xml")
        }) ?? false

        return OOXMLSummary(
            kind: .pptx,
            hasMacros: macros,
            slideCount: p.slideCount,
            slideLayoutCount: layouts,
            hasSpeakerNotes: notesPresent
        )
    }

    // MARK: - Unzip shell-outs

    /// Extract a single entry to `Data`. Shells out to `/usr/bin/unzip
    /// -p` which streams to stdout without touching disk. Fails closed
    /// if unzip exits non-zero.
    public static func unzipEntry(at url: URL, entry: String) throws -> Data {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", url.path, entry]
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0, !data.isEmpty else {
            let msg = String(data: err, encoding: .utf8) ?? "unknown unzip error"
            throw OOXMLParserError.unzipFailed("\(entry) — \(msg)")
        }
        return data
    }

    /// List entries in a zip. Used for speaker-notes detection.
    public static func unzipList(at url: URL) throws -> [String] {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z", "-1", url.path]
        process.standardOutput = stdout
        process.standardError = Pipe()

        try process.run()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw OOXMLParserError.unzipFailed("list \(url.lastPathComponent)")
        }
        return String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .map(String.init) ?? []
    }
}

// MARK: - DOCX visitor

final class DocxTextVisitor: NSObject, XMLParserDelegate {

    struct Stats { let words: Int; let paragraphs: Int; let trackedChanges: Int }

    private var textBuffer = ""
    private var paragraphCount = 0
    private var trackedChanges = 0
    private var insideT = false

    static func visit(xml: Data) throws -> Stats {
        let visitor = DocxTextVisitor()
        let parser = XMLParser(data: xml)
        parser.delegate = visitor
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw OOXMLParserError.parseFailed(
                parser.parserError?.localizedDescription ?? "unknown"
            )
        }
        let words = visitor.textBuffer
            .split(whereSeparator: { $0.isWhitespace })
            .count
        return Stats(
            words: words,
            paragraphs: visitor.paragraphCount,
            trackedChanges: visitor.trackedChanges
        )
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch stripNS(qualifiedName ?? name) {
        case "t":       insideT = true
        case "p":       paragraphCount += 1
        case "ins", "del": trackedChanges += 1
        default:        break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        if stripNS(qualifiedName ?? name) == "t" { insideT = false }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideT {
            textBuffer.append(string)
            textBuffer.append(" ")
        }
    }

    private func stripNS(_ name: String) -> String {
        if let colon = name.firstIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }
}

// MARK: - Comment counter

final class CommentCountVisitor: NSObject, XMLParserDelegate {
    private var count = 0

    static func visit(xml: Data) -> Int {
        let visitor = CommentCountVisitor()
        let parser = XMLParser(data: xml)
        parser.delegate = visitor
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return visitor.count
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if stripNS(qualifiedName ?? name) == "comment" { count += 1 }
    }

    private func stripNS(_ name: String) -> String {
        if let colon = name.firstIndex(of: ":") {
            return String(name[name.index(after: colon)...])
        }
        return name
    }
}

// MARK: - XLSX visitors

final class XlsxWorkbookVisitor: NSObject, XMLParserDelegate {

    struct Workbook { let sheetCount: Int; let namedRangeCount: Int }

    private var sheets = 0
    private var definedNames = 0

    static func visit(xml: Data) -> Workbook {
        let v = XlsxWorkbookVisitor()
        let parser = XMLParser(data: xml)
        parser.delegate = v
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return Workbook(sheetCount: v.sheets, namedRangeCount: v.definedNames)
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch strip(qualifiedName ?? name) {
        case "sheet":       sheets += 1
        case "definedName": definedNames += 1
        default: break
        }
    }

    private func strip(_ s: String) -> String {
        if let c = s.firstIndex(of: ":") { return String(s[s.index(after: c)...]) }
        return s
    }
}

final class XlsxFormulaVisitor: NSObject, XMLParserDelegate {

    private var formulas = 0

    static func visit(xml: Data) -> Int {
        let v = XlsxFormulaVisitor()
        let parser = XMLParser(data: xml)
        parser.delegate = v
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return v.formulas
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if strip(qualifiedName ?? name) == "f" { formulas += 1 }
    }

    private func strip(_ s: String) -> String {
        if let c = s.firstIndex(of: ":") { return String(s[s.index(after: c)...]) }
        return s
    }
}

// MARK: - PPTX visitors

final class PptxPresentationVisitor: NSObject, XMLParserDelegate {

    struct Presentation { let slideCount: Int }

    private var slides = 0

    static func visit(xml: Data) -> Presentation {
        let v = PptxPresentationVisitor()
        let parser = XMLParser(data: xml)
        parser.delegate = v
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return Presentation(slideCount: v.slides)
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if strip(qualifiedName ?? name) == "sldId" { slides += 1 }
    }

    private func strip(_ s: String) -> String {
        if let c = s.firstIndex(of: ":") { return String(s[s.index(after: c)...]) }
        return s
    }
}

final class PptxLayoutVisitor: NSObject, XMLParserDelegate {

    private var layouts = 0

    static func visit(xml: Data) -> Int {
        let v = PptxLayoutVisitor()
        let parser = XMLParser(data: xml)
        parser.delegate = v
        parser.shouldProcessNamespaces = false
        _ = parser.parse()
        return v.layouts
    }

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if strip(qualifiedName ?? name) == "Override" {
            if let ctype = attributes["ContentType"],
               ctype.contains("slideLayout") {
                layouts += 1
            }
        }
    }

    private func strip(_ s: String) -> String {
        if let c = s.firstIndex(of: ":") { return String(s[s.index(after: c)...]) }
        return s
    }
}
