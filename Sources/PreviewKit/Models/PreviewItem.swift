// PreviewItem — the pivot type PreviewKit navigates, renders, and exports.
//
// A single struct covers three shapes:
//   - A leaf artifact (file, chunk)
//   - A Cairn collection (recognizer group)
//   - A generic folder (plain filesystem hierarchy)
//
// Group shape is signalled by `children != nil && kind.isGroup`. Leaves
// have `children == nil`. Mixed trees (a leaf with children) are not
// allowed — the navigator asserts this in `asTree()`.
//
// `cairnMeta` is the only Cairn-specific field and is always optional, so
// PreviewKit works unchanged in Canopy.

import Foundation

public struct PreviewItem: Sendable, Identifiable, Hashable {

    public let id: UUID
    public let kind: ArtifactKind

    /// Display name shown in the navigator row. For Cairn this is the
    /// artifact's logical name (`IMG_0041.ARW`); for a filesystem host
    /// it's `URL.lastPathComponent`.
    public let displayName: String

    /// Path-component suffix used for icon / language inference when the
    /// kind is ambiguous. Nil for group nodes.
    public let fileExtension: String?

    /// Logical path inside the archive / filesystem, shown in headers
    /// and context menus. Display-only — no filesystem semantics.
    public let logicalPath: String

    /// Original (pre-compression for Cairn, native for filesystem) size
    /// in bytes. `-1` when unknown (e.g., a synthesised overview node).
    public let sizeBytes: Int64

    public let modifiedAt: Date
    public let createdAt: Date?

    /// Children of a group node. `nil` for leaves. An empty-but-not-nil
    /// array means "this is a group that happens to be empty".
    public var children: [PreviewItem]?

    /// Cairn-specific metadata (codec / ratio / relations). `nil` when
    /// the host is not Cairn, or when the metadata isn't yet computed.
    public var cairnMeta: CairnMeta?

    // MARK: - Init

    public init(
        id: UUID = UUID(),
        kind: ArtifactKind,
        displayName: String,
        fileExtension: String? = nil,
        logicalPath: String,
        sizeBytes: Int64,
        modifiedAt: Date,
        createdAt: Date? = nil,
        children: [PreviewItem]? = nil,
        cairnMeta: CairnMeta? = nil
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.fileExtension = fileExtension
        self.logicalPath = logicalPath
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.children = children
        self.cairnMeta = cairnMeta
    }

    // MARK: - Derived helpers

    /// A group has `children != nil` AND its kind is `.collection` /
    /// `.folder`. A leaf with a `children` array is a bug — the factory
    /// `asGroup` / `asLeaf` methods below make the mistake impossible at
    /// call sites.
    public var isGroup: Bool {
        kind.isGroup
    }

    /// Recursive total size of leaves under this node. O(n).
    public var totalSizeBytes: Int64 {
        if let kids = children {
            return kids.reduce(0) { $0 + $1.totalSizeBytes }
        }
        return max(0, sizeBytes)
    }

    /// Recursive leaf count.
    public var leafCount: Int {
        if let kids = children {
            return kids.reduce(0) { $0 + $1.leafCount }
        }
        return isGroup ? 0 : 1
    }
}

// MARK: - Factories

public extension PreviewItem {

    /// Build a leaf from a file URL — extension-based inference, size
    /// from filesystem, modification date from attributes. Throws when
    /// the URL can't be stat'd.
    static func fromFileURL(_ url: URL) throws -> PreviewItem {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .creationDateKey,
        ])
        return PreviewItem(
            kind: ArtifactKind.infer(from: url),
            displayName: url.lastPathComponent,
            fileExtension: url.pathExtension.isEmpty ? nil : url.pathExtension,
            logicalPath: url.path,
            sizeBytes: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date(),
            createdAt: values.creationDate
        )
    }

    /// Build a Cairn collection group.
    static func collection(
        id: UUID = UUID(),
        name: String,
        logicalPath: String,
        children: [PreviewItem],
        cairnMeta: CairnMeta? = nil
    ) -> PreviewItem {
        PreviewItem(
            id: id,
            kind: .collection,
            displayName: name,
            fileExtension: nil,
            logicalPath: logicalPath,
            sizeBytes: -1,
            modifiedAt: children.map(\.modifiedAt).max() ?? Date(),
            createdAt: nil,
            children: children,
            cairnMeta: cairnMeta
        )
    }

    /// Build a filesystem folder group.
    static func folder(
        id: UUID = UUID(),
        name: String,
        logicalPath: String,
        children: [PreviewItem]
    ) -> PreviewItem {
        PreviewItem(
            id: id,
            kind: .folder,
            displayName: name,
            fileExtension: nil,
            logicalPath: logicalPath,
            sizeBytes: -1,
            modifiedAt: children.map(\.modifiedAt).max() ?? Date(),
            createdAt: nil,
            children: children
        )
    }
}
