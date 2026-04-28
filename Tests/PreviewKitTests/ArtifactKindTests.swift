// Tests for `ArtifactKind.infer(...)` — the backbone of navigator/
// renderer dispatch. A broken inference path silently routes files to
// the wrong renderer, so this suite is deliberately exhaustive.

import XCTest
@testable import PreviewKit

final class ArtifactKindTests: XCTestCase {

    func testExtensionInferenceForDocuments() {
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "pdf"),      .pdf)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "md"),       .markdown)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "docx"),     .docx)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "xlsx"),     .xlsx)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "pptx"),     .pptx)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "pages"),    .pages)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "key"),      .keynote)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "RTF"),      .rtf) // case-insensitive
    }

    func testExtensionInferenceForImages() {
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "jpg"),  .jpeg)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "jpeg"), .jpeg)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "png"),  .png)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "heic"), .heic)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "svg"),  .svg)
    }

    func testExtensionInferenceForRAW() {
        for ext in ["dng", "cr3", "arw", "raf", "nef", "orf", "rw2", "raw"] {
            XCTAssertEqual(ArtifactKind.infer(fromExtension: ext), .raw, "failed for \(ext)")
        }
    }

    func testExtensionInferenceForCode() {
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "swift"), .sourceSwift)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "ts"),    .sourceTS)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "tsx"),   .sourceTS)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "py"),    .sourcePython)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "rs"),    .sourceRust)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "cpp"),   .sourceCpp)
    }

    func testExtensionInferenceForData() {
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "json"),    .json)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "yaml"),    .yaml)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "sqlite"),  .sqlite)
    }

    func testExtensionFallbackIsBinary() {
        XCTAssertEqual(ArtifactKind.infer(fromExtension: ""),       .binary)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "unknwn"), .binary)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "xyzzy"),  .binary)
    }

    func testURLInference() {
        let url = URL(fileURLWithPath: "/tmp/sample.swift")
        XCTAssertEqual(ArtifactKind.infer(from: url), .sourceSwift)
    }

    // MARK: - Magic bytes

    func testMagicPDF() {
        let bytes = Data([0x25, 0x50, 0x44, 0x46, 0x2D])  // "%PDF-"
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: bytes), .pdf)
    }

    func testMagicPNG() {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: bytes), .png)
    }

    func testMagicJPEG() {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: bytes), .jpeg)
    }

    func testMagicZIP() {
        let bytes = Data([0x50, 0x4B, 0x03, 0x04])
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: bytes), .archive)
    }

    func testMagicMachO() {
        // Little-endian 64-bit mach-o
        var magic: UInt32 = 0xFEEDFACF
        let bytes = withUnsafeBytes(of: &magic) { Data($0) } + Data(count: 28)
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: bytes), .machO)
    }

    func testMagicFallback() {
        let bytes = Data([0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: bytes), .binary)
    }

    func testMagicShortInput() {
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: Data()), .binary)
        XCTAssertEqual(ArtifactKind.infer(fromMagicBytes: Data([0x25])), .binary)
    }

    // MARK: - Classification

    func testIsGroup() {
        XCTAssertTrue(ArtifactKind.collection.isGroup)
        XCTAssertTrue(ArtifactKind.folder.isGroup)
        XCTAssertFalse(ArtifactKind.pdf.isGroup)
        XCTAssertFalse(ArtifactKind.jpeg.isGroup)
    }

    func testFamilyAssignment() {
        XCTAssertEqual(ArtifactKind.pdf.family,           .documents)
        XCTAssertEqual(ArtifactKind.jpeg.family,          .images)
        XCTAssertEqual(ArtifactKind.raw.family,           .images)
        XCTAssertEqual(ArtifactKind.video.family,         .media)
        XCTAssertEqual(ArtifactKind.audio.family,         .media)
        XCTAssertEqual(ArtifactKind.sourceSwift.family,   .code)
        XCTAssertEqual(ArtifactKind.json.family,          .data)
        XCTAssertEqual(ArtifactKind.font.family,          .design)
        XCTAssertEqual(ArtifactKind.machO.family,         .system)
    }
}
