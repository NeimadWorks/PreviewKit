// PDFRenderer — the flagship document renderer.
//
// Left pane: native `PDFView` (scroll/zoom/select are all free via
// PDFKit) with a page indicator + zoom controls below; above that sits
// the filmstrip — up to twelve thumbnails scaled to fit, plus a
// "+N more" pill when the document has more pages.
// Right pane: lead paragraph, KPI tiles, badges, outline, CairnMeta.

import SwiftUI
import PDFKit
import QuickLookThumbnailing

public struct PDFRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.pdf] }
    public static var priority: Int { 0 }
    public static func make() -> PDFRenderer { PDFRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(PDFRendererBody(item: item, data: data, url: url))
    }
}

// MARK: - Body

private struct PDFRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var document: PDFDocument?
    @State private var stats: PDFStats?
    @State private var wordCount: Int?
    @State private var outline: [OutlineEntry] = []
    @State private var lead: String?
    @State private var thumbnails: [NSImage] = []
    @State private var currentPage: Int = 0
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
        .onReceive(NotificationCenter.default.publisher(for: .PDFViewPageChanged)) { note in
            // SwiftUI's `.onReceive` delivers on the main actor. Read
            // the active page out of the PDFView that posted the
            // notification and update our state for the filmstrip.
            guard let view = note.object as? PDFView,
                  let page = view.currentPage,
                  let doc = view.document else { return }
            let index = doc.index(for: page)
            if index != currentPage { currentPage = index }
        }
    }

    // MARK: - Left pane: PDFView + filmstrip

    @ViewBuilder
    private var leftPane: some View {
        VStack(spacing: 0) {
            if let document {
                PDFKitView(
                    document: document,
                    currentPageIndex: $currentPage
                )
                filmstrip(document: document)
            } else if let loadError {
                ContentUnavailableMessage(
                    title: "Couldn't open PDF",
                    subtitle: loadError,
                    symbol: "exclamationmark.triangle"
                )
                .padding(24)
            } else {
                ProgressView("Loading PDF…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func filmstrip(document: PDFDocument) -> some View {
        let visible = Array(thumbnails.prefix(12))
        let remaining = max(0, document.pageCount - visible.count)
        return VStack(spacing: 4) {
            Divider().opacity(0.3)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { idx, image in
                        filmstripThumb(image: image, pageIndex: idx)
                    }
                    if remaining > 0 {
                        Text("+\(remaining) more")
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                            .padding(.horizontal, 8)
                            .frame(height: PreviewTokens.filmstripHeight)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .frame(height: PreviewTokens.filmstripHeight + 6)
            .background(PreviewTokens.bgTertiary)
        }
    }

    private func filmstripThumb(image: NSImage, pageIndex: Int) -> some View {
        Button {
            currentPage = pageIndex
        } label: {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: PreviewTokens.filmstripHeight)
                .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                        .strokeBorder(
                            pageIndex == currentPage
                                ? Color.accentColor
                                : PreviewTokens.borderFaint,
                            lineWidth: pageIndex == currentPage ? 2 : PreviewTokens.borderWidth
                        )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right pane

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let lead, !lead.isEmpty {
                    LeadBlock(text: lead)
                }
                KPITileRow(kpiTiles, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if !outline.isEmpty {
                    StructureOutlineView(
                        entries: outline,
                        storageKey: "pdf",
                        defaultMode: .compact
                    )
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private var kpiTiles: [KPITile] {
        let pages = stats?.pageCount.description ?? "…"
        let words = wordCount.map(formatNumber) ?? "…"
        let images = stats?.imageCount.description ?? "…"
        let annotations = stats?.annotationCount.description ?? "…"
        return [
            KPITile(value: pages,       label: "Pages"),
            KPITile(value: words,       label: "Words"),
            KPITile(value: images,      label: "Embedded"),
            KPITile(value: annotations, label: "Annotations"),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        guard let stats else { return [] }
        var out: [SemanticBadgeModel] = []
        if stats.isSearchable {
            out.append(.init(text: "Searchable", style: .success, icon: "magnifyingglass"))
        } else {
            out.append(.init(text: "Image-only", style: .warning, icon: "photo"))
        }
        if stats.hasForm {
            out.append(.init(text: "Form fields", style: .info, icon: "checkmark.rectangle"))
        }
        if stats.isEncrypted {
            out.append(.init(text: "Encrypted", style: .warning, icon: "lock"))
        }
        return out
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        document = nil
        stats = nil
        wordCount = nil
        outline = []
        lead = nil
        thumbnails = []
        currentPage = 0
        loadError = nil

        let doc: PDFDocument? = {
            if let url { return PDFDocument(url: url) }
            if let data { return PDFDocument(data: data) }
            return nil
        }()
        guard let doc else {
            loadError = "The data source didn't provide PDF bytes."
            return
        }
        self.document = doc
        self.stats = PDFAnalyzer.quickStats(document: doc)
        self.outline = PDFAnalyzer.extractOutline(document: doc)
        self.lead = PDFAnalyzer.extractLeadParagraph(document: doc)

        // Generate filmstrip thumbnails + compute word count off-main.
        // `PDFDocument` isn't Sendable, so the detached task re-opens
        // the document from its URL inside its own isolation domain.
        if let url {
            let urlForTask = url
            let count = doc.pageCount
            async let thumbs = Self.generateThumbnails(url: urlForTask,
                                                      pageCount: min(count, 12))
            let wordTask: Task<Int, Never> = Task.detached(priority: .userInitiated) {
                guard let workDoc = PDFDocument(url: urlForTask) else { return 0 }
                return PDFAnalyzer.computeWordCount(document: workDoc)
            }
            self.thumbnails = await thumbs
            self.wordCount = await wordTask.value
        } else {
            // No URL → skip filmstrip (QLThumbnail needs a URL) and
            // compute word count on main; data-only path is small
            // archives / fixtures.
            self.wordCount = PDFAnalyzer.computeWordCount(document: doc)
        }
    }

    /// Generate up to `pageCount` thumbnails via QLThumbnailGenerator.
    /// Nonisolated so the caller can `async let` it concurrently with
    /// the word-count task.
    private static func generateThumbnails(url: URL, pageCount: Int) async -> [NSImage] {
        var out: [NSImage] = []
        for index in 0..<pageCount {
            let req = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 72, height: 96),
                scale: 2,
                representationTypes: .thumbnail
            )
            req.iconMode = false
            req.minimumDimension = 36
            // QLThumbnailGenerator doesn't expose a direct per-page API in
            // public SDK; for a single-page PDF (rare) we fall through to
            // page-0 only. Multi-page filmstrip reaches the remaining pages
            // via PDFKit's direct thumbnail render instead.
            if index == 0 {
                if let generated = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req) {
                    out.append(generated.nsImage)
                    continue
                }
            }
            if let doc = PDFDocument(url: url),
               let page = doc.page(at: index) {
                let bounds = page.bounds(for: .cropBox)
                let aspect = bounds.width / max(1, bounds.height)
                let size = CGSize(width: PreviewTokens.filmstripHeight * aspect,
                                  height: PreviewTokens.filmstripHeight)
                let image = page.thumbnail(of: size, for: .cropBox)
                out.append(image)
            }
        }
        return out
    }

    // MARK: - Helpers

    private func formatNumber(_ n: Int) -> String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.usesGroupingSeparator = true
        return fmt.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - PDFKitView (NSViewRepresentable)

/// Thin wrapper around `PDFView`. The body view handles page-change
/// notifications via SwiftUI's `.onReceive`, which delivers on the
/// main actor already — no Coordinator selector dance needed, and no
/// data-race warnings under Swift 6 strict concurrency.
private struct PDFKitView: NSViewRepresentable {

    let document: PDFDocument
    @Binding var currentPageIndex: Int

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = NSColor.textBackgroundColor
        view.document = document
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document !== document {
            nsView.document = document
        }
        if let page = nsView.document?.page(at: currentPageIndex),
           nsView.currentPage !== page {
            nsView.go(to: page)
        }
    }
}
