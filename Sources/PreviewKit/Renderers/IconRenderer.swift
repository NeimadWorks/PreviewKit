// IconRenderer — `.icns` (Apple Icon Image).
//
// Left pane: largest representation rendered on a checkerboard tile so
// transparency is visible, plus a 7-slot presence grid. Right pane:
// KPIs (representations count, largest dimension, has retina, file size),
// semantic badges (App Store ready, missing sizes).

import SwiftUI
import AppKit

public struct IconRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.icns] }
    public static var priority: Int { 0 }
    public static func make() -> IconRenderer { IconRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(IconRendererBody(item: item, data: data, url: url))
    }
}

private struct IconRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    private var image: NSImage? {
        if let data { return NSImage(data: data) }
        if let url  { return NSImage(contentsOf: url) }
        return nil
    }

    private var specimen: IconSpecimen? {
        if let data { return IconAnalyzer.specimen(data: data) }
        if let url  { return IconAnalyzer.specimen(url: url) }
        return nil
    }

    var body: some View {
        HSplitView {
            renderPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
    }

    // MARK: - Left

    private var renderPane: some View {
        VStack(spacing: 20) {
            Spacer()
            iconTile
            if let s = specimen {
                slotGrid(for: s)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var iconTile: some View {
        ZStack {
            checkerboard
                .frame(width: 160, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
            } else {
                Image(systemName: "app.gift")
                    .font(.system(size: 48))
                    .foregroundStyle(PreviewTokens.textGhost)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                .strokeBorder(PreviewTokens.borderFaint, lineWidth: PreviewTokens.borderWidth)
        )
    }

    private var checkerboard: some View {
        Canvas { ctx, size in
            let step: CGFloat = 8
            let cols = Int(ceil(size.width / step))
            let rows = Int(ceil(size.height / step))
            for r in 0..<rows {
                for c in 0..<cols {
                    let dark = (r + c).isMultiple(of: 2)
                    let rect = CGRect(x: CGFloat(c) * step, y: CGFloat(r) * step,
                                      width: step, height: step)
                    ctx.fill(Path(rect),
                             with: .color(dark
                                ? Color.gray.opacity(0.12)
                                : Color.gray.opacity(0.05)))
                }
            }
        }
    }

    private func slotGrid(for s: IconSpecimen) -> some View {
        HStack(spacing: 10) {
            ForEach(IconSpecimen.standardSlots, id: \.self) { px in
                VStack(spacing: 4) {
                    Circle()
                        .fill(s.hasSlot(px) ? PreviewTokens.semanticText(.success)
                                            : PreviewTokens.textGhost)
                        .frame(width: 10, height: 10)
                    Text("\(px)")
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                }
            }
        }
    }

    // MARK: - Right

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                header
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if let s = specimen, !s.representations.isEmpty {
                    repsList(s)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer()
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(PreviewTokens.mimeColor(for: item.kind.family))
            Text(item.displayName).font(PreviewTokens.fontHeader)
            Spacer()
        }
    }

    private var kpis: [KPITile] {
        guard let s = specimen else {
            return [
                KPITile(value: "—", label: "Reps"),
                KPITile(value: formatBytes(Int64(data?.count ?? 0)), label: "Size"),
            ]
        }
        return [
            KPITile(value: "\(s.representations.count)", label: "Reps"),
            KPITile(value: "\(s.largestPixelDimension) px", label: "Largest"),
            KPITile(value: formatBytes(Int64(s.byteSize)), label: "Size"),
            KPITile(value: s.hasAppStoreSize ? "Yes" : "No",
                    label: "1024",
                    badge: s.hasAppStoreSize ? .success : .warning),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        guard let s = specimen else { return [] }
        var out: [SemanticBadgeModel] = []
        if s.hasAppStoreSize {
            out.append(.init(text: "App Store ready", style: .success, icon: "checkmark.seal"))
        }
        let missing = IconSpecimen.standardSlots.filter { !s.hasSlot($0) }
        if !missing.isEmpty {
            out.append(.init(text: "Missing sizes: \(missing.map(String.init).joined(separator: ", "))",
                             style: .warning, icon: "exclamationmark.triangle"))
        }
        return out
    }

    private func repsList(_ s: IconSpecimen) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("REPRESENTATIONS")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            ForEach(Array(s.representations.enumerated()), id: \.offset) { _, r in
                Text("\(r.pixelWidth) × \(r.pixelHeight)  ·  \(r.bitsPerSample) bps")
                    .font(PreviewTokens.fontMonoLarge)
                    .foregroundStyle(PreviewTokens.textPrimary)
            }
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
    }

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }
}
