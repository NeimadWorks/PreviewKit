// SemanticBadgeModel — data for a `SemanticBadge` view.
//
// Split from the view itself so renderers can build arrays of badges
// off-main, test them without SwiftUI, and pass them around as
// Sendable values.

import Foundation

public struct SemanticBadgeModel: Identifiable, Sendable, Hashable {

    public let id: UUID
    public let text: String
    public let style: BadgeStyle
    public let icon: String?

    public init(
        id: UUID = UUID(),
        text: String,
        style: BadgeStyle = .neutral,
        icon: String? = nil
    ) {
        self.id = id
        self.text = text
        self.style = style
        self.icon = icon
    }
}
