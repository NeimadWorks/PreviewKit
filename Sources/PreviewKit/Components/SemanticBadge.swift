// SemanticBadge — one small pill used throughout the inspector column.
//
// Keep this view logic-free: it reads a `SemanticBadgeModel` and renders
// it. Callers build the model; renderers never compose styling from
// primitives.

import SwiftUI

public struct SemanticBadge: View {

    public let model: SemanticBadgeModel

    public init(_ model: SemanticBadgeModel) {
        self.model = model
    }

    public init(text: String, style: BadgeStyle = .neutral, icon: String? = nil) {
        self.model = SemanticBadgeModel(text: text, style: style, icon: icon)
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let icon = model.icon {
                Image(systemName: icon)
                    .imageScale(.small)
            }
            Text(model.text)
        }
        .font(.system(size: 9, weight: .medium))
        .padding(.vertical, 2)
        .padding(.horizontal, 7)
        .foregroundStyle(PreviewTokens.semanticText(model.style))
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                .fill(PreviewTokens.semanticFill(model.style))
        )
        .accessibilityLabel(Text(model.text))
    }
}

/// Horizontal wrap row of badges, used across every renderer's inspector.
public struct SemanticBadgeRow: View {

    public let badges: [SemanticBadgeModel]

    public init(_ badges: [SemanticBadgeModel]) {
        self.badges = badges
    }

    public var body: some View {
        FlowLayout(spacing: 6, runSpacing: 6) {
            ForEach(badges) { SemanticBadge($0) }
        }
    }
}

// MARK: - Flow layout (shared wrap helper)

/// Simple wrapping horizontal layout. Public because it's used outside
/// SemanticBadgeRow too (LeadBlock footer, relation chips).
public struct FlowLayout: Layout {

    public var spacing: CGFloat
    public var runSpacing: CGFloat

    public init(spacing: CGFloat = 6, runSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.runSpacing = runSpacing
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rows: [[CGSize]] = [[]]
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var currentRowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let needed = size.width + (rows[rows.count - 1].isEmpty ? 0 : spacing)
            if rowWidth + needed > width && !rows[rows.count - 1].isEmpty {
                totalHeight += currentRowHeight + runSpacing
                rows.append([size])
                rowWidth = size.width
                currentRowHeight = size.height
            } else {
                rows[rows.count - 1].append(size)
                rowWidth += needed
                currentRowHeight = max(currentRowHeight, size.height)
            }
        }
        totalHeight += currentRowHeight
        return CGSize(width: width == .infinity ? rowWidth : width, height: totalHeight)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + runSpacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
