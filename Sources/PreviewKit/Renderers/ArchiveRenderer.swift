// ArchiveRenderer — nested ZIP / TAR inspection.
//
// Left pane: entry list (up to 200 rows, plus "+N more").
// Right pane: dual `CompressionRing` (outer Cairn ratio / inner
// archive ratio) + `MIMEBar` + password / nested / total entries.

import SwiftUI

public struct ArchiveRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.archive] }
    public static var priority: Int { 0 }
    public static func make() -> ArchiveRenderer { ArchiveRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(ArchiveRendererBody(item: item, data: data, url: url))
    }
}

private struct ArchiveRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var summary: ArchiveSummary?
    @State private var ownedTempURL: URL?
    @State private var loadError: String?

    var body: some View {
        ResponsiveSplit {
            leftPane
        } inspector: {
            inspectorPane
        }
        .task(id: item.id) { await load() }
        .onDisappear { cleanupTemp() }
    }

    // MARK: - Left: entry list

    @ViewBuilder
    private var leftPane: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't list archive",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else if let summary {
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Divider().opacity(0.3)
                    ForEach(summary.topEntries) { entry in
                        entryRow(entry)
                    }
                    let remaining = summary.entryCount - summary.topEntries.count
                    if remaining > 0 {
                        Text("+ \(remaining) more entries")
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                            .padding(10)
                    }
                }
            }
            .background(PreviewTokens.bgPrimary)
        } else {
            ProgressView("Listing archive…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("NAME")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("SIZE")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 84, alignment: .trailing)
            Text("RATIO")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(PreviewTokens.bgHover)
    }

    private func entryRow(_ entry: ArchiveEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ArtifactKind.infer(fromExtension: entry.fileExtension).symbolName)
                .foregroundStyle(PreviewTokens.mimeColor(for: entry.family))
                .frame(width: 14)
            Text(entry.name)
                .font(PreviewTokens.fontMonoLarge)
                .foregroundStyle(PreviewTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatBytes(entry.uncompressedBytes))
                .font(PreviewTokens.fontMonoLarge.monospacedDigit())
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 84, alignment: .trailing)
            Text(entry.ratio > 0 ? String(format: "%.0f%%", entry.ratio * 100) : "—")
                .font(PreviewTokens.fontMonoLarge.monospacedDigit())
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PreviewTokens.borderFaint)
                .frame(height: 0.5)
        }
    }

    // MARK: - Right

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let summary {
                    ringRow(summary)
                    KPITileRow(kpis(for: summary), columns: 2)
                    if !badges(for: summary).isEmpty {
                        SemanticBadgeRow(badges(for: summary))
                    }
                    if !summary.mimeSegments.isEmpty {
                        mimeBlock(summary)
                    }
                } else {
                    KPITileRow([
                        .placeholder(label: "Entries"),
                        .placeholder(label: "Size"),
                        .placeholder(label: "Ratio"),
                        .placeholder(label: "Format"),
                    ], columns: 2)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private func ringRow(_ summary: ArchiveSummary) -> some View {
        HStack {
            Spacer()
            CompressionRing(
                outerFraction: item.cairnMeta?.ratio,
                innerFraction: summary.ratio,
                centerLabel: String(format: "%.0f%%", summary.ratio * 100),
                subtitle: "archive ratio",
                diameter: 120
            )
            Spacer()
        }
    }

    private func kpis(for summary: ArchiveSummary) -> [KPITile] {
        [
            KPITile(value: "\(summary.entryCount)",
                    label: "Entries"),
            KPITile(value: formatBytes(summary.uncompressedBytes),
                    label: "Uncompressed"),
            KPITile(value: formatBytes(summary.compressedBytes),
                    label: "Compressed"),
            KPITile(value: summary.format,
                    label: "Format"),
        ]
    }

    private func badges(for summary: ArchiveSummary) -> [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        if summary.hasPasswordProtection {
            out.append(.init(text: "Encrypted", style: .warning, icon: "lock"))
        }
        if summary.hasNested {
            out.append(.init(text: "Nested archives", style: .info, icon: "archivebox"))
        }
        return out
    }

    private func mimeBlock(_ summary: ArchiveSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTENTS")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            MIMEBar(segments: summary.mimeSegments)
        }
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        summary = nil
        loadError = nil
        cleanupTemp()

        let resolved = await resolveURL()
        guard let resolved else {
            loadError = "The data source didn't provide a URL or bytes."
            return
        }

        self.summary = await Task.detached(priority: .userInitiated) {
            try? ArchiveInspector.summarise(fileURL: resolved, maxListed: 200)
        }.value
        if summary == nil {
            loadError = "Couldn't list the archive — neither `unzip` nor `tar` produced usable output."
        }
    }

    @MainActor
    private func resolveURL() async -> URL? {
        if let url { return url }
        guard let data else { return nil }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("previewkit-archive", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let destination = tmpDir.appendingPathComponent(item.displayName)
        do {
            try data.write(to: destination, options: .atomic)
            self.ownedTempURL = destination
            return destination
        } catch {
            loadError = "\(error)"
            return nil
        }
    }

    private func cleanupTemp() {
        if let ownedTempURL {
            try? FileManager.default.removeItem(at: ownedTempURL)
            self.ownedTempURL = nil
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }
}
