// Tests for PDFAnalyzer — `countWords` + `firstParagraph` are pure
// helpers we can pin without a fixture PDF. The PDFDocument-dependent
// stats + outline are exercised via a minimal PDF we build in-process
// from a PDFView export so the test is self-contained.

import XCTest
import PDFKit
@testable import PreviewKit

final class PDFAnalyzerTests: XCTestCase {

    // MARK: - countWords

    func testCountWordsWhitespaceSplit() {
        XCTAssertEqual(PDFAnalyzer.countWords(in: ""), 0)
        XCTAssertEqual(PDFAnalyzer.countWords(in: "hello"), 1)
        XCTAssertEqual(PDFAnalyzer.countWords(in: "hello world"), 2)
        XCTAssertEqual(PDFAnalyzer.countWords(in: "hello  world\n\tfoo"), 3)
    }

    // MARK: - firstParagraph

    func testFirstParagraphStopsAtBlankLineAfterMinLength() {
        let text = """
        Title line

        This is the lead paragraph that should be captured. It is made long enough to cross the 120-character threshold so the blank-line termination kicks in.

        Another paragraph that must not be captured.
        """
        let lead = PDFAnalyzer.firstParagraph(in: text)
        XCTAssertNotNil(lead)
        XCTAssertTrue(lead!.contains("should be captured"))
        XCTAssertFalse(lead!.contains("must not be"))
    }

    func testFirstParagraphReturnsNilForEmpty() {
        XCTAssertNil(PDFAnalyzer.firstParagraph(in: ""))
        XCTAssertNil(PDFAnalyzer.firstParagraph(in: "   \n\n  "))
    }

    // MARK: - PDFDocument-backed

    func testQuickStatsOnSyntheticPDF() throws {
        let doc = try Self.makeSyntheticPDF(pageText: "Hello, PreviewKit. This is a test.")
        let stats = PDFAnalyzer.quickStats(document: doc)
        XCTAssertEqual(stats.pageCount, 1)
        XCTAssertTrue(stats.isSearchable)
        XCTAssertFalse(stats.isEncrypted)
    }

    func testWordCountOnSyntheticPDF() throws {
        let doc = try Self.makeSyntheticPDF(pageText: "One two three four five six")
        let words = PDFAnalyzer.computeWordCount(document: doc)
        XCTAssertEqual(words, 6)
    }

    // MARK: - Helper

    /// Build a single-page PDFDocument by drawing text into a CGContext.
    /// Keeps the test self-contained — no fixture files on disk.
    static func makeSyntheticPDF(pageText: String) throws -> PDFDocument {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: data),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw NSError(domain: "test", code: -1)
        }
        ctx.beginPDFPage(nil)
        let string = NSAttributedString(
            string: pageText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 18),
                .foregroundColor: NSColor.black,
            ]
        )
        let framesetter = CTFramesetterCreateWithAttributedString(string)
        let path = CGPath(rect: CGRect(x: 72, y: 72, width: 468, height: 648), transform: nil)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRangeMake(0, string.length),
            path,
            nil
        )
        CTFrameDraw(frame, ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        guard let doc = PDFDocument(data: data as Data) else {
            throw NSError(domain: "test", code: -2)
        }
        return doc
    }
}
