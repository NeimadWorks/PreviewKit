// Tests for small model types: KPITile placeholder, OutlineEntry
// clamping, SemanticBadgeModel defaulting, CairnMeta ratio guards.

import XCTest
@testable import PreviewKit

final class ModelTests: XCTestCase {

    func testKPITilePlaceholder() {
        let tile = KPITile.placeholder(label: "Pages")
        XCTAssertEqual(tile.value, "…")
        XCTAssertEqual(tile.label, "Pages")
        XCTAssertNil(tile.badge)
    }

    func testKPITileWithBadge() {
        let tile = KPITile(value: "24", label: "Pages", badge: .info)
        XCTAssertEqual(tile.badge, .info)
    }

    func testOutlineEntryClampsWeightFraction() {
        let under = OutlineEntry(title: "x", weightFraction: -5)
        let over = OutlineEntry(title: "y", weightFraction: 2)
        XCTAssertEqual(under.weightFraction, 0)
        XCTAssertEqual(over.weightFraction, 1)
    }

    func testOutlineEntryDefaults() {
        let e = OutlineEntry(title: "Chapter 1")
        XCTAssertEqual(e.depth, 0)
        XCTAssertEqual(e.kind, .generic)
        XCTAssertTrue(e.children.isEmpty)
    }

    func testSemanticBadgeModelDefaultStyle() {
        let m = SemanticBadgeModel(text: "Signed")
        XCTAssertEqual(m.style, .neutral)
        XCTAssertNil(m.icon)
    }

    func testCairnMetaRatioUsability() {
        let ok = CairnMeta(codec: "zstd", ratio: 0.18,
                           originalSizeBytes: 1000, storedSizeBytes: 180)
        XCTAssertTrue(ok.hasUsableRatio)

        let nan = CairnMeta(codec: "?", ratio: .nan,
                            originalSizeBytes: 0, storedSizeBytes: 0)
        XCTAssertFalse(nan.hasUsableRatio)

        let inf = CairnMeta(codec: "?", ratio: .infinity,
                            originalSizeBytes: 0, storedSizeBytes: 0)
        XCTAssertFalse(inf.hasUsableRatio)

        let absurd = CairnMeta(codec: "?", ratio: 10,
                               originalSizeBytes: 0, storedSizeBytes: 0)
        XCTAssertFalse(absurd.hasUsableRatio)
    }

    func testCairnRelationVerbs() {
        XCTAssertEqual(CairnRelation.RelationType.imports.verb, "imports")
        XCTAssertEqual(CairnRelation.RelationType.derivedFrom.verb, "derived from")
        XCTAssertEqual(CairnRelation.RelationType.hasSidecar.verb, "sidecar")
    }

    func testArtifactKindDisplayLabels() {
        XCTAssertEqual(ArtifactKind.sourceSwift.displayLabel, "Swift")
        XCTAssertEqual(ArtifactKind.machO.displayLabel, "Mach-O")
        XCTAssertEqual(ArtifactKind.sourceTS.displayLabel, "TypeScript")
    }
}
