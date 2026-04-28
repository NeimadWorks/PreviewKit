// CairnMeta — the single Cairn-specific payload that can ride along on
// any `PreviewItem`. Every field is optional on the renderer side so the
// same views render correctly when CairnMeta is nil (Canopy case).

import Foundation

public struct CairnMeta: Sendable, Hashable {

    /// Pipeline description — e.g. "zstd-19 + dict-swift-source",
    /// "store (pass-through)", "libjxl + zstd".
    public let codec: String

    /// Stored / raw ratio in [0, 1]. 0.18 means "stored at 18% of
    /// original size". Use `Double.nan` when the ratio is not
    /// meaningful (group nodes, empty chunks).
    public let ratio: Double

    public let originalSizeBytes: Int64
    public let storedSizeBytes: Int64

    public let chunkCount: Int
    public let dedupedChunkCount: Int

    public let firstCommit: CairnCommitRef?
    public let lastCommit: CairnCommitRef?

    public let relations: [CairnRelation]

    public init(
        codec: String,
        ratio: Double,
        originalSizeBytes: Int64,
        storedSizeBytes: Int64,
        chunkCount: Int = 0,
        dedupedChunkCount: Int = 0,
        firstCommit: CairnCommitRef? = nil,
        lastCommit: CairnCommitRef? = nil,
        relations: [CairnRelation] = []
    ) {
        self.codec = codec
        self.ratio = ratio
        self.originalSizeBytes = originalSizeBytes
        self.storedSizeBytes = storedSizeBytes
        self.chunkCount = chunkCount
        self.dedupedChunkCount = dedupedChunkCount
        self.firstCommit = firstCommit
        self.lastCommit = lastCommit
        self.relations = relations
    }

    /// `true` when the ratio is a finite positive number that can be
    /// rendered as a percentage. Guards against NaN/inf in ring charts.
    public var hasUsableRatio: Bool {
        ratio.isFinite && ratio >= 0 && ratio <= 4
    }
}

public struct CairnCommitRef: Sendable, Hashable {
    public let shortHash: String
    public let message: String?
    public let timestamp: Date

    public init(shortHash: String, message: String?, timestamp: Date) {
        self.shortHash = shortHash
        self.message = message
        self.timestamp = timestamp
    }
}

public struct CairnRelation: Identifiable, Sendable, Hashable {

    public let id: UUID
    public let type: RelationType
    public let targetDisplayName: String
    /// Optional navigator target — when present, tapping the relation
    /// chip selects that item.
    public let targetItemID: UUID?

    public init(
        id: UUID = UUID(),
        type: RelationType,
        targetDisplayName: String,
        targetItemID: UUID? = nil
    ) {
        self.id = id
        self.type = type
        self.targetDisplayName = targetDisplayName
        self.targetItemID = targetItemID
    }

    /// Every relation PreviewKit surfaces has a short label, a verb, and
    /// a colour — these are intentionally kept here next to the type so
    /// renderers don't have to build their own vocabulary.
    public enum RelationType: String, Sendable, Hashable, CaseIterable {
        case imports
        case derivedFrom
        case hasSidecar
        case references
        case wikiLinksTo
        case partOfCollection
        case sharesChunks
        case supersedes

        public var verb: String {
            switch self {
            case .imports:            return "imports"
            case .derivedFrom:        return "derived from"
            case .hasSidecar:         return "sidecar"
            case .references:         return "references"
            case .wikiLinksTo:        return "links to"
            case .partOfCollection:   return "in"
            case .sharesChunks:       return "shares with"
            case .supersedes:         return "supersedes"
            }
        }
    }
}
