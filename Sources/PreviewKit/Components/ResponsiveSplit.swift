// ResponsiveSplit — adaptive container that swaps between side-by-side
// (wide host) and stacked-vertical (narrow host).
//
// Why this exists: PreviewKit renderers were originally designed for
// `PreviewSplitView`, which gives them ~800 px to play with — leftPane
// 420 px (preview) + inspectorPane 320 px (KPIs / badges / outline).
// When a host like Canopy embeds a renderer into a narrow Zone-A hero
// card (~300-700 px), an internal `HSplitView` clamps both panes below
// their minimums and content gets clipped or hidden entirely.
//
// Implementation: `ViewThatFits` first proposes the wide HSplitView
// (with its declared min widths). If the host can't satisfy those, it
// falls back to a vertical stack: preview on top (capped height so
// the inspector still has room), inspector below. The user sees both
// the rendered content AND the metadata in any width — narrow hosts
// just lose the side-by-side layout, not the data.
//
// `ViewThatFits` is reliable inside a ScrollView because, unlike
// GeometryReader, it doesn't collapse to zero height when the parent
// has unspecified height — it propagates child intrinsic sizes.

import SwiftUI

public struct ResponsiveSplit<Left: View, Inspector: View>: View {

    /// Maximum height reserved for the preview (left) pane in the
    /// narrow / vertical fallback. Tuned so the inspector pane still
    /// has room to surface its KPIs and outline below the preview.
    public let narrowPreviewHeight: CGFloat

    @ViewBuilder public let left: () -> Left
    @ViewBuilder public let inspector: () -> Inspector

    public init(
        narrowPreviewHeight: CGFloat = 380,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        self.narrowPreviewHeight = narrowPreviewHeight
        self.left = left
        self.inspector = inspector
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {

            // Wide path — original Cairn-style side-by-side.
            HSplitView {
                left()
                    .frame(minWidth: PreviewTokens.rendererMinWidth)
                inspector()
                    .frame(minWidth: PreviewTokens.inspectorMinWidth,
                           idealWidth: PreviewTokens.inspectorIdealWidth)
            }

            // Narrow fallback — vertical stack. Preview gets a fixed
            // height so the inspector below still surfaces its content.
            // Both panes remain visible regardless of host width.
            VStack(spacing: 0) {
                left()
                    .frame(maxWidth: .infinity)
                    .frame(height: narrowPreviewHeight)
                    .clipped()
                Divider()
                inspector()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}
