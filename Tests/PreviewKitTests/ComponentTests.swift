// Behavioural tests for the shared components that have pure logic
// alongside their SwiftUI surface: HexDumpView's renderer, MIMEBar's
// normalisation, OverviewGrid's tiling, StructureOutlineView's
// flattening, CollectionTreeView's filter + flatten, FlatListView's
// sort/collect, and BinaryRenderer's entropy math.

import XCTest
@testable import PreviewKit

@MainActor
final class ComponentTests: XCTestCase {

    // MARK: - HexDumpView.render

    func testHexDumpRendersKnownInputToKnownOutput() {
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])      // "Hello"
        let out = HexDumpView.render(data: data, maxBytes: 16, bytesPerRow: 16)
        XCTAssertTrue(out.contains("000000"))
        XCTAssertTrue(out.contains("48 65 6C 6C 6F"))
        XCTAssertTrue(out.contains("Hello"))
    }

    func testHexDumpTruncatesAndAnnotatesRemainder() {
        let data = Data(repeating: 0xFF, count: 512)
        let out = HexDumpView.render(data: data, maxBytes: 64, bytesPerRow: 16)
        XCTAssertTrue(out.contains("more bytes truncated"))
    }

    func testHexDumpNonPrintableAsDot() {
        let data = Data([0x00, 0x01, 0x02])
        let out = HexDumpView.render(data: data, maxBytes: 3, bytesPerRow: 16)
        XCTAssertTrue(out.contains("···"))
    }

    // MARK: - MIMEBar normalisation

    func testMIMEBarNormaliseScalesToOne() {
        let raw = [
            MIMESegment(label: "a", fraction: 2, family: .code),
            MIMESegment(label: "b", fraction: 3, family: .data),
        ]
        let out = MIMEBar.normalise(raw)
        XCTAssertEqual(out.map(\.fraction).reduce(0, +), 1, accuracy: 1e-6)
    }

    func testMIMEBarNormalisePreservesAlreadyUnitInput() {
        let raw = [
            MIMESegment(label: "a", fraction: 0.6, family: .code),
            MIMESegment(label: "b", fraction: 0.4, family: .data),
        ]
        let out = MIMEBar.normalise(raw)
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].fraction, 0.6, accuracy: 1e-9)
    }

    func testMIMEBarZeroInputPassesThrough() {
        let raw = [MIMESegment(label: "z", fraction: 0, family: .data)]
        let out = MIMEBar.normalise(raw)
        XCTAssertEqual(out.first?.fraction, 0)
    }

    // MARK: - OverviewGrid tiling

    func testOverviewGridTilesFromItems() {
        let now = Date()
        let items: [PreviewItem] = [
            PreviewItem(kind: .sourceSwift, displayName: "a.swift",
                        logicalPath: "/a.swift", sizeBytes: 1000, modifiedAt: now),
            PreviewItem(kind: .jpeg, displayName: "b.jpg",
                        logicalPath: "/b.jpg", sizeBytes: 2000, modifiedAt: now),
            PreviewItem.collection(name: "grp", logicalPath: "/grp", children: [
                PreviewItem(kind: .png, displayName: "c.png",
                            logicalPath: "/grp/c.png", sizeBytes: 3000, modifiedAt: now)
            ])
        ]
        let tiles = OverviewGrid.tiles(from: items)
        let images = tiles.first(where: { $0.family == .images })
        let code = tiles.first(where: { $0.family == .code })
        XCTAssertNotNil(images)
        XCTAssertEqual(images?.leafCount, 2)
        XCTAssertEqual(images?.totalBytes, 5000)
        XCTAssertNotNil(code)
        XCTAssertEqual(code?.leafCount, 1)
    }

    // MARK: - StructureOutlineView flattening

    func testOutlineFlattenExpandsOnlyMarkedNodes() {
        let child1 = OutlineEntry(title: "Child A", depth: 1)
        let child2 = OutlineEntry(title: "Child B", depth: 1)
        let parent = OutlineEntry(title: "Parent", depth: 0,
                                  children: [child1, child2])
        let leaf = OutlineEntry(title: "Lonely", depth: 0)

        let collapsed = StructureOutlineView.flatten([parent, leaf])
        XCTAssertEqual(collapsed.map(\.title), ["Parent", "Lonely"])

        let expanded = StructureOutlineView.flatten(
            [parent, leaf],
            expansion: [parent.id: true]
        )
        XCTAssertEqual(expanded.map(\.title), ["Parent", "Child A", "Child B", "Lonely"])
    }

    // MARK: - CollectionTreeView filter

    func testTreeFilterKeepsMatchingLeavesInsideGroup() {
        let now = Date()
        let tree: [PreviewItem] = [
            PreviewItem.collection(name: "project", logicalPath: "/project", children: [
                PreviewItem(kind: .sourceSwift, displayName: "Foo.swift",
                            logicalPath: "/project/Foo.swift", sizeBytes: 10, modifiedAt: now),
                PreviewItem(kind: .sourceSwift, displayName: "Bar.swift",
                            logicalPath: "/project/Bar.swift", sizeBytes: 20, modifiedAt: now),
            ])
        ]
        let filtered = CollectionTreeView.filtered(tree, query: "Foo")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].children?.count, 1)
        XCTAssertEqual(filtered[0].children?[0].displayName, "Foo.swift")
    }

    func testTreeFilterRemovesEmptyGroups() {
        let now = Date()
        let tree: [PreviewItem] = [
            PreviewItem.collection(name: "empty", logicalPath: "/empty", children: [
                PreviewItem(kind: .sourceSwift, displayName: "Foo.swift",
                            logicalPath: "/empty/Foo.swift", sizeBytes: 10, modifiedAt: now),
            ])
        ]
        XCTAssertTrue(CollectionTreeView.filtered(tree, query: "Nope").isEmpty)
    }

    // MARK: - FlatListView collect + sort

    func testFlatListCollectsAllLeavesIgnoringGroups() {
        let now = Date()
        let tree: [PreviewItem] = [
            PreviewItem.collection(name: "g", logicalPath: "/g", children: [
                PreviewItem(kind: .sourceSwift, displayName: "Z.swift",
                            logicalPath: "/g/Z.swift", sizeBytes: 10, modifiedAt: now),
            ]),
            PreviewItem(kind: .pdf, displayName: "A.pdf",
                        logicalPath: "/A.pdf", sizeBytes: 100, modifiedAt: now),
        ]
        let leaves = FlatListView.collectLeaves(tree)
        XCTAssertEqual(leaves.count, 2)
        XCTAssertEqual(Set(leaves.map(\.displayName)), ["Z.swift", "A.pdf"])
    }

    func testFlatListSortByNameAscending() {
        let now = Date()
        let items: [PreviewItem] = [
            PreviewItem(kind: .pdf, displayName: "B",
                        logicalPath: "/B", sizeBytes: 1, modifiedAt: now),
            PreviewItem(kind: .pdf, displayName: "A",
                        logicalPath: "/A", sizeBytes: 1, modifiedAt: now),
        ]
        let out = FlatListView.sorted(items, by: .name, ascending: true)
        XCTAssertEqual(out.map(\.displayName), ["A", "B"])
    }

    func testFlatListSortBySizeDescending() {
        let now = Date()
        let items: [PreviewItem] = [
            PreviewItem(kind: .pdf, displayName: "small",
                        logicalPath: "/s", sizeBytes: 1, modifiedAt: now),
            PreviewItem(kind: .pdf, displayName: "big",
                        logicalPath: "/b", sizeBytes: 1_000_000, modifiedAt: now),
        ]
        let out = FlatListView.sorted(items, by: .size, ascending: false)
        XCTAssertEqual(out.map(\.displayName), ["big", "small"])
    }

    // MARK: - BinaryRenderer entropy

    func testEntropyOfUniformDataIsMax() {
        let data = Data((0..<256).map { UInt8($0) })
        let e = PreviewKit.shannonEntropy(of: data)
        XCTAssertEqual(e, 8, accuracy: 0.01)
    }

    func testEntropyOfAllZerosIsZero() {
        let data = Data(repeating: 0, count: 1024)
        XCTAssertEqual(PreviewKit.shannonEntropy(of: data), 0, accuracy: 0.001)
    }

    func testEntropyOfEmptyDataIsZero() {
        XCTAssertEqual(PreviewKit.shannonEntropy(of: Data()), 0)
    }

    // MARK: - Mach-O parse smoke

    func testMachOParseRecognises64BitExecutable() {
        // Synthetic 32-byte header: magic FEEDFACF, cputype ARM64, filetype 2 (executable), ncmds 7
        var header = Data()
        header.append(contentsOf: [0xCF, 0xFA, 0xED, 0xFE])      // magic LE
        header.append(contentsOf: withBytes(Int32(0x0100000C)))  // arm64
        header.append(contentsOf: withBytes(Int32(0)))           // cpusubtype
        header.append(contentsOf: withBytes(UInt32(2)))          // filetype (executable)
        header.append(contentsOf: withBytes(UInt32(7)))          // ncmds
        header.append(contentsOf: [UInt8](repeating: 0, count: 32 - header.count))

        let summary = MachOSummary.parse(data: header)
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary?.archLabel, "arm64")
        XCTAssertTrue(summary?.typeLabel.contains("Executable") == true)
        XCTAssertEqual(summary?.loadCommandCount, 7)
    }

    private func withBytes<T: FixedWidthInteger>(_ v: T) -> [UInt8] {
        var v = v.littleEndian
        return withUnsafeBytes(of: &v) { Array($0) }
    }
}

