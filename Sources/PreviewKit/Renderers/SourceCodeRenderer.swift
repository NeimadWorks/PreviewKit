// SourceCodeRenderer — handles all 14 source kinds. Uses the language-
// dispatch tables in `SourceLanguage`, the one-pass tokenizer in
// `SourceTokenizer`, and the regex-based outline in `SourceOutline`.

import SwiftUI

public struct SourceCodeRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> {
        [
            .sourceSwift, .sourceJS, .sourceTS, .sourcePython, .sourceRust,
            .sourceGo, .sourceC, .sourceCpp, .sourceRuby, .sourceKotlin,
            .sourceJava, .sourceShell, .sourceHTML, .sourceCSS,
        ]
    }
    public static var priority: Int { 0 }
    public static func make() -> SourceCodeRenderer { SourceCodeRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(SourceCodeRendererBody(item: item, data: data, url: url))
    }
}

private struct SourceCodeRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var source: String?
    @State private var colorized: AttributedString?
    @State private var summary: SourceSummary?
    @State private var outline: [OutlineEntry] = []
    @State private var showAll: Bool = false
    @State private var loadError: String?

    private var language: SourceLanguage {
        SourceLanguage(kind: item.kind)
    }

    var body: some View {
        ResponsiveSplit {
            leftPane
        } inspector: {
            inspectorPane
        }
        .task(id: item.id) { await load() }
    }

    // MARK: - Left

    @ViewBuilder
    private var leftPane: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't read source",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else if let source {
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 0) {
                    lineNumbers(for: source)
                    Spacer().frame(width: 10)
                    codeBody(source: source)
                        .padding(.trailing, 12)
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(PreviewTokens.bgPrimary)
        } else {
            ProgressView("Reading source…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func lineNumbers(for source: String) -> some View {
        let totalLines = max(1, source.components(separatedBy: .newlines).count)
        let rendered = showAll ? totalLines : min(totalLines, 50)
        let digits = max(2, String(rendered).count)
        return VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...rendered, id: \.self) { n in
                Text(String(format: "%\(digits)d", n))
                    .font(PreviewTokens.fontMono)
                    .foregroundStyle(PreviewTokens.textGhost)
            }
        }
    }

    @ViewBuilder
    private func codeBody(source: String) -> some View {
        let visible = showAll
            ? source
            : firstLines(of: source, count: 50)
        let clipped = !showAll && source != visible
        VStack(alignment: .leading, spacing: 0) {
            if let colorized, !clipped {
                Text(colorized)
                    .font(Font.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                // Fresh tokenize for the visible slice — cheaper than
                // colorising a 10k-line file up-front.
                Text(SourceTokenizer.colorize(visible, language: language))
                    .font(Font.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
            if clipped {
                HStack {
                    Text("\(source.components(separatedBy: .newlines).count) lines total")
                        .font(PreviewTokens.fontLabel)
                        .foregroundStyle(PreviewTokens.textMuted)
                    Button("Show all") { showAll = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.top, 10)
            }
        }
    }

    private func firstLines(of source: String, count: Int) -> String {
        let lines = source.components(separatedBy: "\n")
        if lines.count <= count { return source }
        return lines.prefix(count).joined(separator: "\n")
    }

    // MARK: - Inspector

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                headerCard
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if !outline.isEmpty {
                    StructureOutlineView(
                        entries: outline,
                        storageKey: "source-code",
                        defaultMode: .compact
                    )
                }
                CairnMetaBlock(meta: effectiveMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .font(.system(size: 20))
                .foregroundStyle(PreviewTokens.mimeColor(for: item.kind.family))
            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)
                    .font(PreviewTokens.fontHeader)
                Text(item.displayName)
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var kpis: [KPITile] {
        guard let summary else {
            return [
                .placeholder(label: "Lines"),
                .placeholder(label: "Functions"),
                .placeholder(label: "Types"),
                .placeholder(label: "TODOs"),
            ]
        }
        return [
            KPITile(value: "\(summary.lineCount)",     label: "Lines"),
            KPITile(value: "\(summary.functionCount)", label: "Functions"),
            KPITile(value: "\(summary.typeCount)",     label: "Types"),
            KPITile(value: "\(summary.todoCount)",     label: "TODOs",
                    badge: summary.todoCount > 0 ? .warning : nil),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        guard let summary else { return [] }
        var out: [SemanticBadgeModel] = []
        if summary.hasAsync {
            out.append(.init(text: "async/await", style: .info, icon: "arrow.triangle.2.circlepath"))
        }
        if summary.hasMainActor {
            out.append(.init(text: "@MainActor", style: .info, icon: "cpu"))
        }
        if summary.hasTests {
            out.append(.init(text: "Tests", style: .success, icon: "checkmark.seal"))
        }
        if summary.importCount > 0 {
            out.append(.init(text: "\(summary.importCount) imports", style: .neutral,
                             icon: "arrow.down.to.line"))
        }
        return out
    }

    /// Add import relations into the meta block so clicking a chip can
    /// later (Session 5) jump to the imported module if it exists in
    /// the archive.
    private var effectiveMeta: CairnMeta? {
        guard let existing = item.cairnMeta else { return nil }
        guard let summary, !summary.importNames.isEmpty else { return existing }
        let rels = summary.importNames.map { name in
            CairnRelation(type: .imports, targetDisplayName: name)
        }
        return CairnMeta(
            codec: existing.codec,
            ratio: existing.ratio,
            originalSizeBytes: existing.originalSizeBytes,
            storedSizeBytes: existing.storedSizeBytes,
            chunkCount: existing.chunkCount,
            dedupedChunkCount: existing.dedupedChunkCount,
            firstCommit: existing.firstCommit,
            lastCommit: existing.lastCommit,
            relations: existing.relations + rels
        )
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        source = nil
        colorized = nil
        summary = nil
        outline = []
        showAll = false
        loadError = nil

        let decoded: String? = {
            if let data { return String(data: data, encoding: .utf8) }
            if let url { return try? String(contentsOf: url, encoding: .utf8) }
            return nil
        }()
        guard let decoded else {
            loadError = "The data source didn't return UTF-8 text."
            return
        }
        self.source = decoded

        let lang = language
        let precomputed = await Task.detached(priority: .userInitiated) { () -> (AttributedString, SourceSummary, [OutlineEntry]) in
            let colour = SourceTokenizer.colorize(firstPrefix(of: decoded, lines: 50), language: lang)
            let summary = SourceOutline.summarise(source: decoded, language: lang)
            let outline = SourceOutline.extractOutline(source: decoded, language: lang)
            return (colour, summary, outline)
        }.value

        self.colorized = precomputed.0
        self.summary = precomputed.1
        self.outline = precomputed.2
    }
}

/// Top-of-file tokenize prefix — shared between main thread view and
/// the detached warm-up task. Nonisolated free function so the task
/// can call it without capturing MainActor state.
private func firstPrefix(of source: String, lines: Int) -> String {
    let split = source.components(separatedBy: "\n")
    if split.count <= lines { return source }
    return split.prefix(lines).joined(separator: "\n")
}
