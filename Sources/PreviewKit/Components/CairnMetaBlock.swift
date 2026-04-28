// CairnMetaBlock — Cairn-specific metadata panel at the bottom of each
// renderer's inspector column. Renders nothing when meta is nil so the
// same renderer code runs unchanged inside Canopy.

import SwiftUI

public struct CairnMetaBlock: View {

    public let meta: CairnMeta?
    public let onRelationTap: ((CairnRelation) -> Void)?

    public init(
        meta: CairnMeta?,
        onRelationTap: ((CairnRelation) -> Void)? = nil
    ) {
        self.meta = meta
        self.onRelationTap = onRelationTap
    }

    public var body: some View {
        if let meta {
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader
                grid(for: meta)
                if !meta.relations.isEmpty {
                    Divider().opacity(0.3)
                    relationChips(for: meta.relations)
                }
            }
            .padding(PreviewTokens.cardPadding)
            .background(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                    .fill(PreviewTokens.accentOrangeTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                    .strokeBorder(PreviewTokens.accentOrangeBorder, lineWidth: PreviewTokens.borderWidth)
            )
        } else {
            EmptyView()
        }
    }

    // MARK: - Subviews

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text("CAIRN")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.accentOrange)
            Spacer(minLength: 0)
        }
    }

    private func grid(for meta: CairnMeta) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Codec",  meta.codec)
            row("Ratio",  formatRatio(meta.ratio))
            row("Stored", formatBytes(meta.storedSizeBytes))
            row("Raw",    formatBytes(meta.originalSizeBytes))
            if meta.chunkCount > 0 {
                row("Chunks", "\(meta.chunkCount) · \(meta.dedupedChunkCount) deduped")
            }
            if let first = meta.firstCommit {
                row("First", first.shortHash)
            }
            if let last = meta.lastCommit {
                row("Last", last.shortHash)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(PreviewTokens.fontMonoLarge)
                .foregroundStyle(PreviewTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func relationChips(for relations: [CairnRelation]) -> some View {
        FlowLayout(spacing: 6, runSpacing: 6) {
            ForEach(relations) { r in
                Button {
                    onRelationTap?(r)
                } label: {
                    HStack(spacing: 4) {
                        Text(r.type.verb)
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                        Text(r.targetDisplayName)
                            .font(PreviewTokens.fontMonoLarge)
                            .foregroundStyle(PreviewTokens.accentOrange)
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 7)
                    .background(
                        RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .disabled(r.targetItemID == nil && onRelationTap == nil)
            }
        }
    }

    // MARK: - Formatting

    private func formatRatio(_ r: Double) -> String {
        guard r.isFinite else { return "—" }
        return String(format: "%.1f%%  (%.2fx)", r * 100, r == 0 ? 0 : 1 / r)
    }

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }
}
