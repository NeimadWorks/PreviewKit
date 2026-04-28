// Tests for `PreviewContextAction` — group membership, availability
// predicate, canonical ordering. Keeps the menu vocabulary stable.

import XCTest
@testable import PreviewKit

final class ContextMenuTests: XCTestCase {

    private func leaf() -> PreviewItem {
        PreviewItem(
            kind: .markdown,
            displayName: "README.md",
            logicalPath: "/README.md",
            sizeBytes: 1024,
            modifiedAt: Date()
        )
    }

    // MARK: - Group membership

    func testActionGroupAssignments() {
        XCTAssertEqual(PreviewContextAction.preview.group, .inspection)
        XCTAssertEqual(PreviewContextAction.openWithDefault.group, .manipulation)
        XCTAssertEqual(PreviewContextAction.copyName.group, .copy)
        XCTAssertEqual(PreviewContextAction.exportSelection.group, .selection)
        XCTAssertEqual(PreviewContextAction.revealInFinder.group, .archive)
    }

    func testCanonicalOrderCoversAllCases() {
        let all: [PreviewContextAction] = [
            .preview, .showInHistory, .showInVitals, .showInSearch,
            .openWithDefault, .exportTo, .exportAsZIP,
            .copyName, .copyLogicalPath, .copyBLAKE3,
            .exportSelection, .computeSelectionTotal,
            .revealInFinder, .showArchiveInfo,
        ]
        XCTAssertEqual(Set(PreviewContextAction.canonicalOrder), Set(all))
    }

    func testCanonicalOrderIsGroupedInAscendingGroupOrder() {
        let groups = PreviewContextAction.canonicalOrder.map { $0.group.rawValue }
        var last = 0
        for g in groups {
            XCTAssertGreaterThanOrEqual(g, last)
            last = g
        }
    }

    // MARK: - Availability

    func testCopyBLAKE3RequiresCairnMeta() {
        let item = leaf()
        let envWithout = PreviewContextEnvironment(
            focusedItem: item, hasCairnMeta: false
        )
        XCTAssertFalse(PreviewContextAction.copyBLAKE3.isAvailable(in: envWithout))

        let envWith = PreviewContextEnvironment(
            focusedItem: item, hasCairnMeta: true
        )
        XCTAssertTrue(PreviewContextAction.copyBLAKE3.isAvailable(in: envWith))
    }

    func testSelectionActionsRequireMultiSelect() {
        let item = leaf()
        let single = PreviewContextEnvironment(focusedItem: item, selectedItems: [item])
        XCTAssertFalse(PreviewContextAction.exportSelection.isAvailable(in: single))
        XCTAssertFalse(PreviewContextAction.computeSelectionTotal.isAvailable(in: single))

        let two = PreviewContextEnvironment(focusedItem: item, selectedItems: [item, item])
        XCTAssertTrue(PreviewContextAction.exportSelection.isAvailable(in: two))
    }

    func testArchiveActionsRequireArchiveOpen() {
        let item = leaf()
        let closed = PreviewContextEnvironment(focusedItem: item, archiveOpen: false)
        XCTAssertFalse(PreviewContextAction.revealInFinder.isAvailable(in: closed))
        XCTAssertFalse(PreviewContextAction.showArchiveInfo.isAvailable(in: closed))

        let open = PreviewContextEnvironment(focusedItem: item, archiveOpen: true)
        XCTAssertTrue(PreviewContextAction.revealInFinder.isAvailable(in: open))
    }

    func testDefaultActionsAreAlwaysAvailable() {
        let env = PreviewContextEnvironment(
            focusedItem: leaf(),
            selectedItems: [],
            archiveOpen: false,
            hasCairnMeta: false
        )
        XCTAssertTrue(PreviewContextAction.preview.isAvailable(in: env))
        XCTAssertTrue(PreviewContextAction.copyName.isAvailable(in: env))
        XCTAssertTrue(PreviewContextAction.copyLogicalPath.isAvailable(in: env))
    }

    // MARK: - Display labels

    func testDisplayLabelsAreNonEmpty() {
        for action in PreviewContextAction.canonicalOrder {
            XCTAssertFalse(action.displayLabel.isEmpty,
                           "\(action) missing display label")
        }
    }
}
