// ResponsiveSplit — stable single-column container that stacks the
// preview (left) on top of the inspector pane (right).
//
// Why this exists: PreviewKit renderers were originally a Cairn
// invention with an internal `HSplitView` (preview pane | inspector
// pane), under the assumption they'd always live inside Cairn's
// `PreviewSplitView` which itself supplies a 800+ px column. When
// embedded in a narrower host (Canopy's inspector hero card,
// hover popover, drawer panel...), the side-by-side layout
// clamps below its minimums and silently clips content.
//
// Earlier attempts used `ViewThatFits` to swap between HSplitView
// and a vertical stack. That caused visible flicker because
// renderer content sizes change asynchronously during load
// (PDF document, image dimensions, audio waveform, etc.) — each
// resize made `ViewThatFits` re-evaluate which branch fits and
// occasionally flip back, producing a blink.
//
// Current strategy: ALWAYS render as a single vertical column.
// The preview content goes on top (fills available width, capped
// height to give the inspector room), the inspector content
// scrolls below. Cairn's `PreviewSplitView` already wraps the
// renderer in its own outer split (navigator | renderer column),
// so renderers don't need a third-level horizontal split.
//
// Hosts that want a true side-by-side layout (e.g. a future
// "wide PDF reader" mode) can call HSplitView directly around the
// renderer body — but that's a host concern, not a renderer one.

import SwiftUI

public struct ResponsiveSplit<Left: View, Inspector: View>: View {

    /// Maximum height reserved for the preview (left) pane. Tuned so
    /// the inspector below it still has visible room for KPIs and
    /// outline. Renderers with naturally tall content (PDF, source
    /// code) will scroll within this height; renderers with short
    /// content (icon, mobileprovision header) won't fill it.
    public let previewHeight: CGFloat

    @ViewBuilder public let left: () -> Left
    @ViewBuilder public let inspector: () -> Inspector

    public init(
        previewHeight: CGFloat = 380,
        @ViewBuilder left: @escaping () -> Left,
        @ViewBuilder inspector: @escaping () -> Inspector
    ) {
        self.previewHeight = previewHeight
        self.left = left
        self.inspector = inspector
    }

    public var body: some View {
        VStack(spacing: 0) {
            left()
                .frame(maxWidth: .infinity)
                .frame(height: previewHeight)
                .clipped()
            Divider()
            inspector()
                .frame(maxWidth: .infinity)
        }
    }
}
