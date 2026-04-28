// OutlineEntry — one node in `StructureOutlineView` (TOC).
//
// `weightFraction` is the visual signal that lets a reader scan a
// document's "shape" at a glance — a tall heading with many sub-entries
// gets a long bar, a trivial one gets a short bar. Renderers compute
// this from whatever they have (PDF: page count delta; Markdown:
// character count; Source: LOC in a function body).

import Foundation

public struct OutlineEntry: Identifiable, Sendable, Hashable {

    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let depth: Int
    public let weightFraction: Double
    public var children: [OutlineEntry]
    public let kind: OutlineKind

    public init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        depth: Int = 0,
        weightFraction: Double = 0,
        children: [OutlineEntry] = [],
        kind: OutlineKind = .generic
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.depth = depth
        self.weightFraction = max(0, min(1, weightFraction))
        self.children = children
        self.kind = kind
    }
}

/// Kind drives the colour of the trailing weight bar and the optional
/// leading glyph in the outline row. `generic` is the fallback.
public enum OutlineKind: String, Sendable, Hashable, CaseIterable {
    case generic
    case heading
    case function
    case type
    case `protocol`
    case `extension`
    case property
    case slide
    case sheet
    case page
    case section
    case table
    case chapter
}
