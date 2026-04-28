// PDFAnalyzer — logic-only helpers for PDFRenderer. Kept separate from
// the view code so every heuristic (word-count, outline extraction,
// lead paragraph, table/image tally) can be unit-tested against known
// PDF fixtures without mounting SwiftUI.

import Foundation
import PDFKit

public struct PDFStats: Sendable, Hashable {
    public let pageCount: Int
    public let wordCount: Int
    public let imageCount: Int
    public let annotationCount: Int
    public let isSearchable: Bool
    public let hasForm: Bool
    public let isEncrypted: Bool

    public init(
        pageCount: Int,
        wordCount: Int,
        imageCount: Int,
        annotationCount: Int,
        isSearchable: Bool,
        hasForm: Bool,
        isEncrypted: Bool
    ) {
        self.pageCount = pageCount
        self.wordCount = wordCount
        self.imageCount = imageCount
        self.annotationCount = annotationCount
        self.isSearchable = isSearchable
        self.hasForm = hasForm
        self.isEncrypted = isEncrypted
    }
}

public enum PDFAnalyzer {

    /// Compute cheap stats — page count, encryption, form presence.
    /// Word count is deliberately excluded; compute that via
    /// `computeWordCount(document:)` off-main because full-text
    /// extraction is expensive on large PDFs.
    public static func quickStats(document: PDFDocument) -> PDFStats {
        var annotationCount = 0
        var imageCount = 0
        var hasText = false
        var hasForm = false

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            annotationCount += page.annotations.count
            for ann in page.annotations {
                // Form-field detection: non-empty widgetFieldType raw
                // value signals an interactive AcroForm field. A plain
                // note / highlight has an empty widgetFieldType.
                if !ann.widgetFieldType.rawValue.isEmpty { hasForm = true }
                if ann.type == "Stamp" || ann.type == "FileAttachment" { imageCount += 1 }
            }
            if let text = page.string, !text.isEmpty { hasText = true }
        }

        return PDFStats(
            pageCount: document.pageCount,
            wordCount: 0,
            imageCount: imageCount,
            annotationCount: annotationCount,
            isSearchable: hasText,
            hasForm: hasForm,
            isEncrypted: document.isEncrypted
        )
    }

    /// Full-text word count. O(total characters); the caller should
    /// invoke this off the main actor.
    public static func computeWordCount(document: PDFDocument) -> Int {
        var total = 0
        for i in 0..<document.pageCount {
            guard let page = document.page(at: i), let text = page.string else { continue }
            total += countWords(in: text)
        }
        return total
    }

    /// Split on Unicode whitespace. Exposed as a helper so tests can
    /// anchor the exact rule.
    public static func countWords(in string: String) -> Int {
        string.split(whereSeparator: { $0.isWhitespace }).count
    }

    // MARK: - Outline extraction

    /// Walk `document.outlineRoot` into a flat `OutlineEntry` array
    /// annotated with depth + weight fraction. Weight fraction is the
    /// rough page-range share of each top-level entry.
    public static func extractOutline(document: PDFDocument) -> [OutlineEntry] {
        guard let root = document.outlineRoot else { return [] }
        var children: [OutlineEntry] = []
        for index in 0..<root.numberOfChildren {
            if let child = root.child(at: index) {
                children.append(convert(child, depth: 0, document: document))
            }
        }
        annotateWeights(&children, document: document)
        return children
    }

    private static func convert(_ node: PDFOutline, depth: Int, document: PDFDocument) -> OutlineEntry {
        var kids: [OutlineEntry] = []
        for index in 0..<node.numberOfChildren {
            if let child = node.child(at: index) {
                kids.append(convert(child, depth: depth + 1, document: document))
            }
        }
        let title = node.label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "•"
        // `document.index(for:)` returns `NSNotFound` (Int.max) when the
        // page isn't part of the document — common for action-based
        // outline entries whose `destination.page` is nil. `+ 1` on
        // that overflows, so we guard against the sentinel explicitly.
        let subtitle: String? = {
            guard let dest = node.destination, let page = dest.page else { return nil }
            let idx = document.index(for: page)
            guard idx != NSNotFound, idx >= 0 else { return nil }
            return "p. \(idx + 1)"
        }()
        return OutlineEntry(
            title: title.isEmpty ? "•" : title,
            subtitle: subtitle,
            depth: depth,
            weightFraction: 0,
            children: kids,
            kind: depth == 0 ? .chapter : .heading
        )
    }

    /// Assign a rough weight fraction to each top-level entry based on
    /// how many pages it likely spans. Not perfect — the PDF spec
    /// doesn't give us a canonical answer — but good enough to read
    /// the document's "shape" at a glance.
    private static func annotateWeights(_ entries: inout [OutlineEntry], document: PDFDocument) {
        let totalPages = max(1, document.pageCount)
        guard !entries.isEmpty else { return }

        // Collect start page per top-level entry.
        func startPage(of node: OutlineEntry, in document: PDFDocument) -> Int? {
            // Need the original PDFOutline to pull destination; approximate
            // by parsing the "p. N" subtitle we generated.
            guard let sub = node.subtitle,
                  let range = sub.range(of: #"\d+"#, options: .regularExpression) else {
                return nil
            }
            return Int(sub[range])
        }

        let starts: [Int] = entries.compactMap { startPage(of: $0, in: document) }
        guard starts.count == entries.count else { return }

        var updated: [OutlineEntry] = []
        for (i, entry) in entries.enumerated() {
            let thisStart = starts[i]
            let nextStart = i + 1 < starts.count ? starts[i + 1] : totalPages
            let span = max(1, nextStart - thisStart)
            let fraction = Double(span) / Double(totalPages)
            updated.append(OutlineEntry(
                id: entry.id,
                title: entry.title,
                subtitle: entry.subtitle,
                depth: entry.depth,
                weightFraction: min(1, fraction),
                children: entry.children,
                kind: entry.kind
            ))
        }
        entries = updated
    }

    // MARK: - Lead paragraph

    /// The first paragraph-ish piece of prose from page 1 — used by
    /// `LeadBlock`. We stop at the first blank line (two or more
    /// newlines) after we've seen > 120 non-whitespace chars, which
    /// covers the common "title + subtitle + first paragraph" pattern
    /// without swallowing the entire first page.
    public static func extractLeadParagraph(document: PDFDocument) -> String? {
        guard let page = document.page(at: 0), let text = page.string else { return nil }
        return firstParagraph(in: text)
    }

    /// Exposed so tests can run the heuristic without a PDF.
    public static func firstParagraph(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Collapse runs of whitespace / linebreaks into single spaces.
        var accumulated = ""
        var lastWasBlank = false
        for line in trimmed.components(separatedBy: .newlines) {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty {
                if accumulated.count > 120 { break }
                lastWasBlank = true
                continue
            }
            if lastWasBlank, !accumulated.isEmpty { accumulated += " " }
            accumulated += stripped + " "
            lastWasBlank = false
            if accumulated.count > 400 { break }
        }
        return accumulated
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
