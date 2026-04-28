// OverviewGrid — the adaptive grid shown when nothing is selected.
//
// Each cell represents an `ArtifactKind.Family` (Code, Images, Documents,
// Media, Data, Design, System) and shows a large glyph, the family
// label, the number of leaves in that family, and a total size +
// average ratio line (when Cairn meta is present).

import SwiftUI

public struct OverviewGrid: View {

    public struct Tile: Identifiable, Sendable, Hashable {
        public let id: ArtifactKind.Family
        public let family: ArtifactKind.Family
        public let leafCount: Int
        public let totalBytes: Int64
        public let averageRatio: Double?   // nil in Canopy; 0..1 in Cairn

        public init(
            family: ArtifactKind.Family,
            leafCount: Int,
            totalBytes: Int64,
            averageRatio: Double? = nil
        ) {
            self.id = family
            self.family = family
            self.leafCount = leafCount
            self.totalBytes = totalBytes
            self.averageRatio = averageRatio
        }
    }

    public let tiles: [Tile]
    public let columns: Int
    public let onSelect: ((ArtifactKind.Family) -> Void)?

    public init(
        tiles: [Tile],
        columns: Int = 4,
        onSelect: ((ArtifactKind.Family) -> Void)? = nil
    ) {
        self.tiles = tiles
        self.columns = max(1, columns)
        self.onSelect = onSelect
    }

    public var body: some View {
        let gridItems = Array(repeating: GridItem(.flexible(), spacing: 12),
                              count: columns)
        LazyVGrid(columns: gridItems, spacing: 12) {
            ForEach(tiles) { tile in
                cell(for: tile)
            }
        }
    }

    // MARK: - Cell

    private func cell(for tile: Tile) -> some View {
        Button {
            onSelect?(tile.family)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: tile.family.symbolName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(PreviewTokens.mimeColor(for: tile.family))
                    Spacer()
                    Text("\(tile.leafCount)")
                        .font(PreviewTokens.fontKPIValue)
                        .foregroundStyle(PreviewTokens.textPrimary)
                }
                Text(tile.family.displayLabel)
                    .font(PreviewTokens.fontBodyLarge.weight(.medium))
                    .foregroundStyle(PreviewTokens.textPrimary)
                HStack(spacing: 4) {
                    Text(formatBytes(tile.totalBytes))
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                    if let r = tile.averageRatio, r.isFinite {
                        Text("·")
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textGhost)
                        Text(String(format: "%.0f%% avg", r * 100))
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                    .fill(PreviewTokens.bgSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                    .strokeBorder(PreviewTokens.borderFaint, lineWidth: PreviewTokens.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }
}

public extension OverviewGrid {

    /// Convenience factory: tally a flat list of `PreviewItem`s by
    /// family, excluding group nodes. Callers that want custom bucketing
    /// can construct `Tile`s directly.
    static func tiles(from items: [PreviewItem]) -> [Tile] {
        var leavesByFamily: [ArtifactKind.Family: (count: Int, bytes: Int64,
                                                   ratios: [Double])] = [:]
        func walk(_ list: [PreviewItem]) {
            for it in list {
                if it.isGroup, let kids = it.children {
                    walk(kids)
                } else if !it.isGroup {
                    let fam = it.kind.family
                    var entry = leavesByFamily[fam] ?? (0, 0, [])
                    entry.count += 1
                    entry.bytes += max(0, it.sizeBytes)
                    if let r = it.cairnMeta?.ratio, r.isFinite {
                        entry.ratios.append(r)
                    }
                    leavesByFamily[fam] = entry
                }
            }
        }
        walk(items)
        return leavesByFamily
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { (fam, v) in
                let avg: Double? = v.ratios.isEmpty
                    ? nil
                    : v.ratios.reduce(0, +) / Double(v.ratios.count)
                return Tile(family: fam, leafCount: v.count,
                            totalBytes: v.bytes, averageRatio: avg)
            }
    }
}
