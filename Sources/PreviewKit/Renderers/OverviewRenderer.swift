// OverviewRenderer — shown when nothing is selected. Renders the family
// grid plus a headline row of global KPIs aggregated from the navigator.
//
// This isn't triggered by kind dispatch — `PreviewSplitView` mounts it
// directly when `selectedItem == nil`. It's modeled as a RendererProtocol
// anyway so hosts that want to replace the empty-state (custom branding,
// tutorial content) can register an override.

import SwiftUI

public struct OverviewRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [] }
    public static var priority: Int { 0 }
    public static func make() -> OverviewRenderer { OverviewRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        // This path is only used if a host explicitly registers it for a
        // kind — on the empty-state path `PreviewSplitView` calls
        // `render(dataSource:)` directly.
        AnyView(Text(item.displayName))
    }

    /// Empty-state entry point. Pulls tiles from the navigator's root
    /// items; wires the family tap-through into the caller's selection
    /// closure.
    @ViewBuilder
    public static func render(
        dataSource: any NavigatorDataSource,
        onFamilyTap: ((ArtifactKind.Family) -> Void)? = nil
    ) -> some View {
        OverviewRendererBody(dataSource: dataSource, onFamilyTap: onFamilyTap)
    }
}

private struct OverviewRendererBody: View {

    let dataSource: any NavigatorDataSource
    let onFamilyTap: ((ArtifactKind.Family) -> Void)?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                headline
                OverviewGrid(
                    tiles: OverviewGrid.tiles(from: dataSource.rootItems),
                    columns: 3,
                    onSelect: onFamilyTap
                )
                Spacer(minLength: 20)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PreviewTokens.bgPrimary)
        .id(dataSource.refreshToken)
    }

    private var headline: some View {
        let leaves = FlatListView.collectLeaves(dataSource.rootItems)
        let totalBytes = leaves.reduce(Int64(0)) { $0 + max(0, $1.sizeBytes) }
        let kinds = Set(leaves.map(\.kind.family)).count
        let tiles: [KPITile] = [
            KPITile(value: "\(leaves.count)", label: "Artifacts"),
            KPITile(value: "\(kinds)",        label: "Families"),
            KPITile(value: formatBytes(totalBytes), label: "Total"),
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Nothing selected")
                .font(.title2.weight(.semibold))
                .foregroundStyle(PreviewTokens.textPrimary)
            Text("Pick a file in the navigator, or jump into a family below.")
                .font(PreviewTokens.fontBodyLarge)
                .foregroundStyle(PreviewTokens.textMuted)
            KPITileRow(tiles, columns: 3)
                .padding(.top, 4)
        }
    }

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }
}
