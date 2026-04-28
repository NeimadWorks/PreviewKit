// Tests for ArchiveInspector — exercise the line parsers against
// canonical unzip / tar output so we don't need real archives on disk.

import XCTest
@testable import PreviewKit

final class ArchiveInspectorTests: XCTestCase {

    func testParseUnzipListingCapturesSizeAndName() {
        let raw = """
        Archive:  sample.zip
          Length      Date    Time    Name
        ---------  ---------- -----   ----
             1024  01-01-2026 12:00   README.md
             2048  01-01-2026 12:00   src/main.swift
        ---------                     -------
             3072                     2 files
        """
        let entries = ArchiveInspector.parseUnzipLines(raw)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "README.md")
        XCTAssertEqual(entries[0].uncompressedBytes, 1024)
        XCTAssertEqual(entries[1].name, "src/main.swift")
        XCTAssertEqual(entries[1].uncompressedBytes, 2048)
    }

    func testParseTarListingCapturesName() {
        let raw = """
        -rw-r--r--  0 user group  1024  1 Jan 12:00 README.md
        -rw-r--r--  0 user group  2048  1 Jan 12:00 src/main.swift
        """
        let entries = ArchiveInspector.parseTarLines(raw)
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].name, "README.md")
        XCTAssertEqual(entries[1].name, "src/main.swift")
    }

    func testMimeSegmentsSumToOne() {
        let entries: [ArchiveEntry] = [
            .init(name: "foo.swift",    uncompressedBytes: 1000, compressedBytes: 300),
            .init(name: "bar.png",      uncompressedBytes: 2000, compressedBytes: 1800),
            .init(name: "README.md",    uncompressedBytes:  500, compressedBytes:  200),
        ]
        let segments = ArchiveInspector.mimeSegments(for: entries)
        let sum = segments.map(\.fraction).reduce(0, +)
        XCTAssertEqual(sum, 1, accuracy: 1e-6)
        XCTAssertTrue(segments.contains { $0.family == .code })
        XCTAssertTrue(segments.contains { $0.family == .images })
        XCTAssertTrue(segments.contains { $0.family == .documents })
    }

    func testArchiveEntryRatio() {
        let e = ArchiveEntry(name: "a.txt", uncompressedBytes: 100, compressedBytes: 25)
        XCTAssertEqual(e.ratio, 0.25, accuracy: 1e-9)
    }

    func testArchiveEntryRatioZeroOnEmpty() {
        let e = ArchiveEntry(name: "empty", uncompressedBytes: 0, compressedBytes: 0)
        XCTAssertEqual(e.ratio, 0)
    }

    func testArchiveEntryFamilyInference() {
        let e = ArchiveEntry(name: "Foo.swift", uncompressedBytes: 1, compressedBytes: 1)
        XCTAssertEqual(e.family, .code)
    }
}
