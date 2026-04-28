// MarkdownRenderer — renders Markdown via Foundation's native
// `AttributedString(markdown:)` pipeline (TextKit 2 under the hood).
// No WebKit, no external markdown parser.
//
// A source/rendered toggle in the top bar lets users flip between
// the pretty-rendered view and the raw monospaced source. Wikilinks
// (Obsidian-style `[[target]]`) surface as relations in the
// CairnMetaBlock when meta is present; tapping a chip fires
// `onRelationTap` so the host can select the target in the navigator.

import SwiftUI

public struct MarkdownRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.markdown, .txt, .rtf] }
    public static var priority: Int { 0 }
    public static func make() -> MarkdownRenderer { MarkdownRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(MarkdownRendererBody(item: item, data: data, url: url))
    }
}

private struct MarkdownRendererBody: View {

    enum Mode: String, CaseIterable {
        case rendered, source
        var label: String { rawValue.capitalized }
    }

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var source: String?
    @State private var stats: MarkdownStats?
    @State private var outline: [OutlineEntry] = []
    @State private var wikilinks: [CairnRelation] = []
    @State private var lead: String?
    @State private var rendered: AttributedString?
    @State private var mode: Mode = .rendered
    @State private var loadError: String?

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
        .task(id: item.id) { await load() }
    }

    // MARK: - Left

    @ViewBuilder
    private var leftPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            modeBar
            Divider().opacity(0.3)
            contentView
        }
    }

    private var modeBar: some View {
        HStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            Spacer()
            if let count = stats?.wordCount {
                Text("\(count) words")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var contentView: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't read Markdown",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else if let source {
            ScrollView(.vertical) {
                Group {
                    switch mode {
                    case .rendered:
                        if let rendered {
                            Text(rendered)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ProgressView()
                        }
                    case .source:
                        Text(source)
                            .font(PreviewTokens.fontMonoBody)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(20)
            }
            .background(PreviewTokens.bgPrimary)
        } else {
            ProgressView("Reading file…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Inspector

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let lead, !lead.isEmpty {
                    LeadBlock(text: lead)
                }
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if !outline.isEmpty {
                    StructureOutlineView(
                        entries: outline,
                        storageKey: "markdown",
                        defaultMode: .compact
                    )
                }
                CairnMetaBlock(
                    meta: effectiveMeta,
                    onRelationTap: nil   // Session 5 wires this to navigator selection
                )
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    /// Combine the item's own meta with the wikilinks we discovered so
    /// the relations chips show up even when the host didn't provide
    /// pre-computed relations.
    private var effectiveMeta: CairnMeta? {
        guard let existing = item.cairnMeta else { return nil }
        guard !wikilinks.isEmpty else { return existing }
        return CairnMeta(
            codec: existing.codec,
            ratio: existing.ratio,
            originalSizeBytes: existing.originalSizeBytes,
            storedSizeBytes: existing.storedSizeBytes,
            chunkCount: existing.chunkCount,
            dedupedChunkCount: existing.dedupedChunkCount,
            firstCommit: existing.firstCommit,
            lastCommit: existing.lastCommit,
            relations: existing.relations + wikilinks
        )
    }

    private var kpis: [KPITile] {
        guard let stats else {
            return [
                .placeholder(label: "Words"),
                .placeholder(label: "Headings"),
                .placeholder(label: "Links"),
                .placeholder(label: "Read time"),
            ]
        }
        return [
            KPITile(value: "\(stats.wordCount)",          label: "Words"),
            KPITile(value: "\(stats.headingCount)",       label: "Headings"),
            KPITile(value: "\(stats.linkCount)",          label: "Links"),
            KPITile(value: "~\(stats.readTimeMinutes) min", label: "Read time"),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        guard let stats else { return [] }
        var out: [SemanticBadgeModel] = []
        if stats.hasFrontmatter {
            out.append(.init(text: "Frontmatter", style: .info, icon: "text.alignleft"))
        }
        if stats.taskCount > 0 {
            out.append(.init(text: "\(stats.taskCount) tasks", style: .info, icon: "checklist"))
        }
        if stats.hasMath {
            out.append(.init(text: "Math", style: .info, icon: "function"))
        }
        if !wikilinks.isEmpty {
            out.append(.init(
                text: "\(wikilinks.count) wikilinks",
                style: .info,
                icon: "link"
            ))
        }
        return out
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        source = nil
        stats = nil
        outline = []
        wikilinks = []
        lead = nil
        rendered = nil
        loadError = nil

        let rawSource: String? = {
            if let data { return String(data: data, encoding: .utf8) }
            if let url { return try? String(contentsOf: url, encoding: .utf8) }
            return nil
        }()
        guard let rawSource else {
            loadError = "The data source didn't return readable text."
            return
        }
        self.source = rawSource
        self.stats = MarkdownAnalyzer.summarise(source: rawSource)
        self.outline = MarkdownAnalyzer.extractHeadings(from: rawSource)
        self.wikilinks = MarkdownAnalyzer.extractWikilinks(from: rawSource)
        self.lead = MarkdownAnalyzer.firstParagraph(in: rawSource)

        // Let AttributedString do the rendering — it handles headings,
        // bold, italic, links, inline code, and ordered/unordered lists
        // for free. For anything it doesn't support (images, tables,
        // code fences) it falls back gracefully to the raw text.
        let (body, _) = MarkdownAnalyzer.stripFrontmatter(rawSource)
        var options = AttributedString.MarkdownParsingOptions()
        options.allowsExtendedAttributes = true
        options.interpretedSyntax = .full
        self.rendered = (try? AttributedString(markdown: body, options: options))
            ?? AttributedString(body)
    }
}
