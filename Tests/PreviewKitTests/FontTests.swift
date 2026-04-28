// Tests for FontAnalyzer — load a system font via its file URL,
// confirm specimen extraction returns plausible values.

import XCTest
import CoreText
@testable import PreviewKit

final class FontTests: XCTestCase {

    /// Load a CTFont directly by PostScript name (Helvetica ships with
    /// every macOS), then exercise the analyzer against it. We skip
    /// the file-URL path because system fonts live in private SDK
    /// locations whose paths aren't stable across OS versions.
    private func helvetica() throws -> CTFont {
        CTFontCreateWithName("Helvetica" as CFString, 24, nil)
    }

    func testSpecimenReturnsExpectedShape() throws {
        let font = try helvetica()
        let specimen = FontAnalyzer.specimen(for: font)
        XCTAssertEqual(specimen.family, "Helvetica")
        XCTAssertGreaterThan(specimen.glyphCount, 0)
        XCTAssertFalse(specimen.firstGlyphs.isEmpty)
        XCTAssertTrue(specimen.pangram.contains("zéphyr"))
    }

    func testUnicodeRangesIncludeBasicLatin() throws {
        let font = try helvetica()
        let ranges = FontAnalyzer.unicodeRanges(for: font)
        XCTAssertTrue(ranges.contains("Basic Latin"))
    }

    func testFirstGlyphsLimitHonoured() throws {
        let font = try helvetica()
        let glyphs = FontAnalyzer.firstGlyphs(for: font, limit: 10)
        XCTAssertEqual(glyphs.count, 10)
    }

    func testLoadFromDataRoundTrip() {
        // Loading from random bytes should fail closed.
        let garbage = Data(repeating: 0, count: 16)
        XCTAssertNil(FontAnalyzer.loadCTFont(from: garbage))
    }
}
