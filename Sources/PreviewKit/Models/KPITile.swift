// KPITile — a single value/label pair rendered by `KPITileRow`.
//
// Kept tiny and Sendable so renderers can build arrays of these
// off-main and hand them to the view at layout time.

import Foundation

public struct KPITile: Identifiable, Sendable, Hashable {

    public let id: UUID
    public let value: String
    public let label: String
    public let accessibilityHint: String?
    public let badge: BadgeStyle?

    public init(
        id: UUID = UUID(),
        value: String,
        label: String,
        accessibilityHint: String? = nil,
        badge: BadgeStyle? = nil
    ) {
        self.id = id
        self.value = value
        self.label = label
        self.accessibilityHint = accessibilityHint
        self.badge = badge
    }

    /// Placeholder tile used while the real value is being computed —
    /// rendered as a redacted shimmer. The tile still participates in
    /// layout so the row height doesn't pop when the real value lands.
    public static func placeholder(label: String) -> KPITile {
        KPITile(value: "…", label: label)
    }
}

/// Colour accent for a KPI tile's corner dot. Same palette as
/// `SemanticBadge.Style` — kept as a sibling type so renderers can
/// use the same vocabulary across tiles and badges.
public enum BadgeStyle: String, Sendable, Hashable, CaseIterable {
    case success, warning, danger, info, neutral
}
