// KPITileRow — horizontal row of small value/label tiles.
//
// Tiles wrap to a second row when the column budget is exceeded.
// Loading values render as a redacted shimmer so the row height is
// stable across the first-paint → resolved transition.

import SwiftUI

public struct KPITileRow: View {

    public let tiles: [KPITile]
    public let columns: Int

    public init(_ tiles: [KPITile], columns: Int = 4) {
        self.tiles = tiles
        self.columns = max(1, columns)
    }

    public var body: some View {
        let c = min(columns, max(1, tiles.count))
        let gridItems = Array(repeating: GridItem(.flexible(minimum: PreviewTokens.kpiTileMinWidth),
                                                  spacing: PreviewTokens.kpiRowGap),
                              count: c)
        LazyVGrid(columns: gridItems, alignment: .leading, spacing: PreviewTokens.kpiRowGap) {
            ForEach(tiles) { KPITileView(tile: $0) }
        }
    }
}

/// One tile. Exposed for callers that need a single KPI in a custom
/// layout (e.g., the overview grid cells).
public struct KPITileView: View {

    public let tile: KPITile

    public init(tile: KPITile) { self.tile = tile }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(tile.value)
                    .font(PreviewTokens.fontKPIValue)
                    .foregroundStyle(PreviewTokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .redacted(reason: isPlaceholder ? .placeholder : [])
                if let badge = tile.badge {
                    Circle()
                        .fill(PreviewTokens.semanticText(badge))
                        .frame(width: 6, height: 6)
                }
            }
            Text(tile.label)
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
                .textCase(.uppercase)
                .tracking(PreviewTokens.labelLetterSpacing)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .strokeBorder(PreviewTokens.borderFaint, lineWidth: PreviewTokens.borderWidth)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(tile.label): \(tile.value)"))
        .accessibilityHint(Text(tile.accessibilityHint ?? ""))
    }

    private var isPlaceholder: Bool {
        tile.value == "…"
    }
}
