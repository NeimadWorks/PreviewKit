// PreviewDataSource — the host-supplied contract PreviewKit depends on.
//
// The host (Cairn's `InspectDataSource`, Canopy's file-system source) is
// responsible for:
//   - Producing the flat/tree list of `PreviewItem`s that populate the
//     navigator
//   - Lazily materialising bytes when an item is selected (decompressing a
//     chunk from the Cairn container, reading a file from disk, etc.)
//   - Optionally providing a temp-file URL for large binaries so renderers
//     like `QLPreviewController` and `AVPlayer` don't force everything
//     through RAM
//
// The protocol is MainActor because SwiftUI reads `rootItems` and
// `refreshToken` from the render path. Data methods are `async throws` and
// hop off-main inside the implementation where needed.

import Foundation

/// Contract the host implements to feed PreviewKit. Extends
/// `NavigatorDataSource` with data-loading responsibilities so the same
/// instance drives both the navigator and the renderer column.
/// No CairnCore dependency — PreviewKit never touches an archive
/// directly.
@MainActor
public protocol PreviewDataSource: NavigatorDataSource {

    /// Read the bytes of a single leaf artifact. Called when the user
    /// selects an item. Implementations are expected to be fast for
    /// already-cached items and to throw a descriptive error when
    /// decompression / decryption / disk read fails.
    ///
    /// For items larger than `inMemoryLimitBytes`, prefer `temporaryURL`.
    func data(for item: PreviewItem) async throws -> Data

    /// Materialise the item as a temp file on disk. Returns `nil` when the
    /// host has no reasonable way to produce one (e.g., in-memory fixture
    /// sources) — callers must then fall back to `data(for:)`. The
    /// returned URL should remain valid for at least the lifetime of the
    /// current selection; the host owns cleanup.
    func temporaryURL(for item: PreviewItem) async throws -> URL?

    /// Threshold at which PreviewKit prefers `temporaryURL` over `data`.
    /// Implementations can override with an archive-specific value; the
    /// default below suits typical desktop machines.
    var inMemoryLimitBytes: Int64 { get }
}

public extension PreviewDataSource {
    /// Default: 64 MB. Under this, renderers prefer in-memory `Data` for
    /// predictable lifetime; over, they ask for a temp URL to let the OS
    /// handle paging (video, large PDFs, big archives).
    var inMemoryLimitBytes: Int64 { 64 * 1024 * 1024 }
}

// MARK: - Static data source (fixtures, tests)

/// Convenience data source backed by an in-memory array. Used by
/// PreviewKit's previews, tests, and by hosts that want to present a
/// static set of items (e.g., a pasteboard importer).
@MainActor
public final class StaticPreviewDataSource: PreviewDataSource {

    public private(set) var rootItems: [PreviewItem]
    public private(set) var refreshToken: UUID = UUID()

    /// Map of item.id → raw bytes. Items not in the map throw on `data`.
    private var bytesByID: [UUID: Data]

    /// Map of item.id → temp URL. Items not in the map return `nil`.
    private var urlByID: [UUID: URL]

    public init(
        items: [PreviewItem] = [],
        bytes: [UUID: Data] = [:],
        urls: [UUID: URL] = [:]
    ) {
        self.rootItems = items
        self.bytesByID = bytes
        self.urlByID = urls
    }

    public func setItems(_ items: [PreviewItem]) {
        self.rootItems = items
        self.refreshToken = UUID()
    }

    public func setBytes(_ data: Data, for id: UUID) {
        bytesByID[id] = data
    }

    public func data(for item: PreviewItem) async throws -> Data {
        guard let d = bytesByID[item.id] else {
            throw PreviewDataSourceError.itemNotAvailable(item.displayName)
        }
        return d
    }

    public func temporaryURL(for item: PreviewItem) async throws -> URL? {
        urlByID[item.id]
    }
}

/// Errors that can surface from a `PreviewDataSource`. Hosts may throw
/// their own error types; renderers pattern-match by message, not by
/// concrete type.
public enum PreviewDataSourceError: Error, CustomStringConvertible, Sendable {
    case itemNotAvailable(String)
    case decompressionFailed(String)
    case underlying(String)

    public var description: String {
        switch self {
        case .itemNotAvailable(let name):   return "Item not available: \(name)"
        case .decompressionFailed(let msg): return "Decompression failed: \(msg)"
        case .underlying(let msg):          return msg
        }
    }
}
