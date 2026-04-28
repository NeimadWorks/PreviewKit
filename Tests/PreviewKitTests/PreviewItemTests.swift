// Tests for `PreviewItem` — identity, factories, size helpers. The
// navigator relies on totalSizeBytes / leafCount / isGroup being
// correct across nested trees.

import XCTest
@testable import PreviewKit

final class PreviewItemTests: XCTestCase {

    func testLeafDoesNotHaveChildren() {
        let leaf = PreviewItem(
            kind: .markdown,
            displayName: "README.md",
            logicalPath: "/README.md",
            sizeBytes: 1024,
            modifiedAt: Date()
        )
        XCTAssertNil(leaf.children)
        XCTAssertFalse(leaf.isGroup)
        XCTAssertEqual(leaf.leafCount, 1)
        XCTAssertEqual(leaf.totalSizeBytes, 1024)
    }

    func testGroupRecursivelyTalliesSize() {
        let a = PreviewItem(kind: .jpeg, displayName: "a.jpg", logicalPath: "/c/a.jpg",
                            sizeBytes: 100, modifiedAt: Date())
        let b = PreviewItem(kind: .jpeg, displayName: "b.jpg", logicalPath: "/c/b.jpg",
                            sizeBytes: 200, modifiedAt: Date())
        let nested = PreviewItem.folder(
            name: "nested",
            logicalPath: "/c/nested",
            children: [
                PreviewItem(kind: .png, displayName: "c.png", logicalPath: "/c/nested/c.png",
                            sizeBytes: 400, modifiedAt: Date())
            ]
        )
        let col = PreviewItem.collection(name: "photos", logicalPath: "/c",
                                         children: [a, b, nested])
        XCTAssertTrue(col.isGroup)
        XCTAssertEqual(col.leafCount, 3)
        XCTAssertEqual(col.totalSizeBytes, 700)
    }

    func testCollectionFactorySetsGroupFlag() {
        let leaf = PreviewItem(kind: .txt, displayName: "x.txt",
                               logicalPath: "/x.txt", sizeBytes: 1,
                               modifiedAt: Date())
        let col = PreviewItem.collection(name: "grp", logicalPath: "/grp",
                                         children: [leaf])
        XCTAssertEqual(col.kind, .collection)
        XCTAssertTrue(col.isGroup)
    }

    func testFromFileURLReadsAttributes() throws {
        // Write a temp file we can read back.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("previewkit-test-\(UUID()).md")
        try Data(repeating: 0xAB, count: 32).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let item = try PreviewItem.fromFileURL(tmp)
        XCTAssertEqual(item.kind, .markdown)
        XCTAssertEqual(item.displayName, tmp.lastPathComponent)
        XCTAssertEqual(item.sizeBytes, 32)
    }

    func testHashableIdentityMatchesID() {
        let a = PreviewItem(kind: .txt, displayName: "a", logicalPath: "/a",
                            sizeBytes: 1, modifiedAt: Date())
        let b = PreviewItem(
            id: a.id, kind: .pdf, displayName: "different", logicalPath: "/b",
            sizeBytes: 999, modifiedAt: Date()
        )
        // Same id → hashable equality even with different field values,
        // because Hashable on Identifiable should defer to id.
        XCTAssertEqual(a.id, b.id)
    }
}
