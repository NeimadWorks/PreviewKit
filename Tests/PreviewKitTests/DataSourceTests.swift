// Tests for `StaticPreviewDataSource` — the fixture-backed data source
// used by previews + hosts that want a read-only set of items.

import XCTest
@testable import PreviewKit

@MainActor
final class DataSourceTests: XCTestCase {

    func testEmptyDataSourceExposesEmptyRoots() {
        let ds = StaticPreviewDataSource()
        XCTAssertTrue(ds.rootItems.isEmpty)
    }

    func testSettingItemsBumpsRefreshToken() {
        let ds = StaticPreviewDataSource()
        let before = ds.refreshToken
        ds.setItems([
            PreviewItem(kind: .txt, displayName: "a.txt", logicalPath: "/a.txt",
                        sizeBytes: 1, modifiedAt: Date())
        ])
        XCTAssertNotEqual(ds.refreshToken, before)
        XCTAssertEqual(ds.rootItems.count, 1)
    }

    func testDataLookupThrowsForMissingItem() async {
        let ds = StaticPreviewDataSource()
        let item = PreviewItem(kind: .txt, displayName: "ghost.txt",
                               logicalPath: "/ghost.txt", sizeBytes: 0,
                               modifiedAt: Date())
        do {
            _ = try await ds.data(for: item)
            XCTFail("expected throw")
        } catch {
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("Item not available"))
        }
    }

    func testDataLookupReturnsStoredBytes() async throws {
        let item = PreviewItem(kind: .txt, displayName: "a.txt",
                               logicalPath: "/a.txt", sizeBytes: 5,
                               modifiedAt: Date())
        let bytes = Data("hello".utf8)
        let ds = StaticPreviewDataSource(items: [item], bytes: [item.id: bytes])
        let out = try await ds.data(for: item)
        XCTAssertEqual(out, bytes)
    }

    func testInMemoryLimitDefault() {
        let ds = StaticPreviewDataSource()
        XCTAssertEqual(ds.inMemoryLimitBytes, 64 * 1024 * 1024)
    }
}
