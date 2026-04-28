// End-to-end integration tests. Drive a `StaticPreviewDataSource`
// through the full navigator → renderer chain without SwiftUI, to
// catch plumbing regressions between the foundation, helpers, and
// renderer roster.

import XCTest
@testable import PreviewKit

@MainActor
final class IntegrationTests: XCTestCase {

    // MARK: - Setup

    private func buildArchive() -> ([PreviewItem], [UUID: Data]) {
        // Three items: a Swift source, a JSON blob, a README.
        let swiftItem = PreviewItem(
            kind: .sourceSwift, displayName: "Main.swift",
            logicalPath: "/src/Main.swift", sizeBytes: 128,
            modifiedAt: Date()
        )
        let jsonItem = PreviewItem(
            kind: .json, displayName: "config.json",
            logicalPath: "/config.json", sizeBytes: 32,
            modifiedAt: Date()
        )
        let markdownItem = PreviewItem(
            kind: .markdown, displayName: "README.md",
            logicalPath: "/README.md", sizeBytes: 64,
            modifiedAt: Date()
        )
        let col = PreviewItem.collection(
            name: "source",
            logicalPath: "/src",
            children: [swiftItem]
        )
        let items = [col, jsonItem, markdownItem]
        let bytes: [UUID: Data] = [
            swiftItem.id: Data("import Foundation\nfunc main() {}\n".utf8),
            jsonItem.id: Data(#"{"name":"demo","n":1}"#.utf8),
            markdownItem.id: Data("# Demo\nThis is a readme.".utf8),
        ]
        return (items, bytes)
    }

    // MARK: - Navigator plumbing

    func testNavigatorFilterFindsSwiftFile() {
        let (items, bytes) = buildArchive()
        let ds = StaticPreviewDataSource(items: items, bytes: bytes)
        let filtered = CollectionTreeView.filtered(ds.rootItems, query: "Main")
        let flat = CollectionTreeView.flatten(filtered, expansion: [:])
        XCTAssertTrue(flat.contains { $0.item.displayName == "source" })
    }

    func testFlatListCollectsLeavesAcrossCollections() {
        let (items, _) = buildArchive()
        let leaves = FlatListView.collectLeaves(items)
        XCTAssertEqual(leaves.count, 3)
    }

    // MARK: - Data source round-trip

    func testDataSourceReturnsStoredBytes() async throws {
        let (items, bytes) = buildArchive()
        let ds = StaticPreviewDataSource(items: items, bytes: bytes)

        let jsonLeaf = FlatListView.collectLeaves(items)
            .first(where: { $0.kind == .json })!
        let data = try await ds.data(for: jsonLeaf)
        XCTAssertEqual(String(data: data, encoding: .utf8),
                       #"{"name":"demo","n":1}"#)
    }

    func testRefreshTokenBumpsOnSetItems() {
        let ds = StaticPreviewDataSource()
        let original = ds.refreshToken
        let (items, _) = buildArchive()
        ds.setItems(items)
        XCTAssertNotEqual(ds.refreshToken, original)
    }

    // MARK: - Renderer dispatch via bootstrap

    func testBootstrapRoutesKindsThroughSpecialistRenderers() {
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)

        // Spot-check the Session 2–4 roster.
        for kind: ArtifactKind in [
            .pdf, .markdown, .docx, .xlsx, .pptx,
            .sourceSwift, .json, .csv, .font,
            .jpeg, .png, .raw, .video, .audio, .archive,
        ] {
            let renderer = reg.renderer(for: kind)
            XCTAssertFalse(
                String(describing: type(of: renderer)).contains("BinaryRenderer"),
                "\(kind) should resolve to a specialist renderer, not the fallback"
            )
        }
    }

    func testBootstrapFallbackCatchesEveryKind() {
        // Even after reset + re-bootstrap, every ArtifactKind should
        // resolve to something (even if it's just BinaryRenderer).
        let reg = RendererRegistry()
        PreviewKit.bootstrap(registry: reg)
        for kind in ArtifactKind.allCases {
            let renderer = reg.renderer(for: kind)
            XCTAssertNotNil(renderer, "\(kind) yielded no renderer")
        }
    }

    // MARK: - Context menu availability in real environments

    func testContextMenuHidesCairnCopiesWithoutMeta() {
        let item = PreviewItem(
            kind: .markdown,
            displayName: "x",
            logicalPath: "/x",
            sizeBytes: 0,
            modifiedAt: Date()
        )
        let env = PreviewContextEnvironment(
            focusedItem: item,
            hasCairnMeta: false
        )
        XCTAssertFalse(PreviewContextAction.copyBLAKE3.isAvailable(in: env))
    }
}
