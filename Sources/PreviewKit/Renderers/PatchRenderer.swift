// PatchRenderer — unified-diff viewer for `.patch` / `.diff` files.
//
// Left pane: the first N lines, line-classified and tinted (success for
// additions, danger for deletions, info for hunk headers, muted for
// meta). Right pane: KPIs (files changed, additions, deletions, hunks),
// semantic badges (binary / rename / new / deleted), the files list,
// and the CairnMetaBlock.

import SwiftUI

public struct PatchRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.patch] }
    public static var priority: Int { 0 }
    public static func make() -> PatchRenderer { PatchRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(PatchRendererBody(item: item, data: data, url: url))
    }
}

private struct PatchRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    private static let maxPreviewLines = 400

    private var source: String {
        if let data, let s = String(data: data, encoding: .utf8) { return s }
        if let url, let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        return ""
    }

    private var stats: PatchStats { PatchAnalyzer.parse(source) }

    var body: some View {
        HSplitView {
            renderPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
    }

    // MARK: - Left: colorised diff

    private var renderPane: some View {
        ScrollView([.vertical, .horizontal]) {
            VStack(alignment: .leading, spacing: 0) {
                let lines = Array(source
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .prefix(Self.maxPreviewLines))
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    diffLine(String(line))
                }
                if source.split(separator: "\n").count > Self.maxPreviewLines {
                    Text("… \(source.split(separator: "\n").count - Self.maxPreviewLines) more lines")
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .padding(8)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func diffLine(_ raw: String) -> some View {
        let kind = PatchAnalyzer.classify(raw)
        Text(raw.isEmpty ? " " : raw)
            .font(PreviewTokens.fontMonoLarge)
            .foregroundStyle(foreground(for: kind))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(background(for: kind))
    }

    private func foreground(for kind: PatchLineKind) -> Color {
        switch kind {
        case .addition:   return PreviewTokens.semanticText(.success)
        case .deletion:   return PreviewTokens.semanticText(.danger)
        case .hunkHeader: return PreviewTokens.semanticText(.info)
        case .fileHeader: return PreviewTokens.textPrimary
        case .meta:       return PreviewTokens.textMuted
        case .context:    return PreviewTokens.textPrimary
        }
    }

    private func background(for kind: PatchLineKind) -> Color {
        switch kind {
        case .addition:   return PreviewTokens.semanticFill(.success)
        case .deletion:   return PreviewTokens.semanticFill(.danger)
        case .hunkHeader: return PreviewTokens.semanticFill(.info).opacity(0.5)
        default:          return .clear
        }
    }

    // MARK: - Right: inspector

    private var inspectorPane: some View {
        let s = stats
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                header
                KPITileRow(kpis(s), columns: 2)
                if !badges(s).isEmpty {
                    SemanticBadgeRow(badges(s))
                }
                if !s.files.isEmpty {
                    fileList(s.files)
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
            Text(item.displayName)
                .font(PreviewTokens.fontHeader)
            Spacer()
        }
    }

    private func kpis(_ s: PatchStats) -> [KPITile] {
        [
            KPITile(value: "\(s.filesChanged)", label: "Files"),
            KPITile(value: "+\(s.additions)",   label: "Added",
                    badge: s.additions > 0 ? .success : nil),
            KPITile(value: "-\(s.deletions)",   label: "Removed",
                    badge: s.deletions > 0 ? .danger : nil),
            KPITile(value: "\(s.hunks)",        label: "Hunks"),
        ]
    }

    private func badges(_ s: PatchStats) -> [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        if s.hasBinaryPatch {
            out.append(.init(text: "Binary patch", style: .warning, icon: "doc.zipper"))
        }
        if s.hasRename {
            out.append(.init(text: "Rename", style: .info, icon: "arrow.left.arrow.right"))
        }
        if s.hasNewFile {
            out.append(.init(text: "New file", style: .success, icon: "plus.circle"))
        }
        if s.hasDeletedFile {
            out.append(.init(text: "Deleted file", style: .danger, icon: "minus.circle"))
        }
        return out
    }

    private func fileList(_ files: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FILES")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            ForEach(files.prefix(24), id: \.self) { name in
                Text(name)
                    .font(PreviewTokens.fontMonoLarge)
                    .foregroundStyle(PreviewTokens.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if files.count > 24 {
                Text("+ \(files.count - 24) more")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
    }
}
