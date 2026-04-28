// OfficeRenderer — handles DOCX / XLSX / PPTX + iWork + RTF.
//
// Visual preview comes from QuickLook (native system renderer —
// byte-identical to what Finder shows). Inspector column reads from
// our OOXML parser for KPIs + badges. iWork / RTF render through
// QuickLook without OOXML stats (iWork is .iwa, not OOXML).
//
// QuickLook requires a URL on disk; the renderer writes `data` to a
// temp file when the host returned only bytes. We don't leak temp
// files — they're created inside `FileManager.default.temporaryDirectory`
// and cleaned up when the view disappears.

import SwiftUI
import AppKit
import Quartz

public struct OfficeRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> {
        [.docx, .xlsx, .pptx, .pages, .numbers, .keynote, .rtf]
    }
    public static var priority: Int { 0 }
    public static func make() -> OfficeRenderer { OfficeRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(OfficeRendererBody(item: item, data: data, url: url))
    }
}

private struct OfficeRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var previewURL: URL?
    @State private var ownedTempURL: URL?
    @State private var summary: OOXMLSummary?
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

    // MARK: - Left: QLPreviewView

    @ViewBuilder
    private var leftPane: some View {
        if let previewURL {
            QuickLookHost(url: previewURL)
        } else if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't render document",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else {
            ProgressView("Preparing preview…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Right: KPIs + badges

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let summary {
                    KPITileRow(kpis(for: summary), columns: 2)
                    if !badges(for: summary).isEmpty {
                        SemanticBadgeRow(badges(for: summary))
                    }
                    summaryPanel(for: summary)
                } else if OfficeKind(extension: item.fileExtension ?? "") == .unknown {
                    // iWork / RTF — no OOXML stats.
                    VStack(alignment: .leading, spacing: 8) {
                        Text("QuickLook preview")
                            .font(PreviewTokens.fontLabel)
                            .tracking(PreviewTokens.labelLetterSpacing)
                            .foregroundStyle(PreviewTokens.textMuted)
                        Text("This format doesn't expose machine-readable metadata from its container, so the inspector is minimal.")
                            .font(PreviewTokens.fontBody)
                            .foregroundStyle(PreviewTokens.textSecondary)
                    }
                    .padding(PreviewTokens.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                            .fill(PreviewTokens.bgSecondary)
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private func kpis(for s: OOXMLSummary) -> [KPITile] {
        switch s.kind {
        case .docx:
            return [
                KPITile(value: "\(s.wordCount)",         label: "Words"),
                KPITile(value: "\(s.paragraphCount)",    label: "Paragraphs"),
                KPITile(value: "\(s.trackedChangeCount)", label: "Changes"),
                KPITile(value: "\(s.commentCount)",      label: "Comments"),
            ]
        case .xlsx:
            return [
                KPITile(value: "\(s.sheetCount)",       label: "Sheets"),
                KPITile(value: "\(s.formulaCount)",     label: "Formulas"),
                KPITile(value: "\(s.namedRangeCount)",  label: "Named"),
                KPITile(value: s.hasMacros ? "yes" : "no", label: "Macros",
                        badge: s.hasMacros ? .warning : nil),
            ]
        case .pptx:
            return [
                KPITile(value: "\(s.slideCount)",           label: "Slides"),
                KPITile(value: "\(s.slideLayoutCount)",     label: "Layouts"),
                KPITile(value: s.hasSpeakerNotes ? "yes" : "no", label: "Notes"),
                KPITile(value: s.hasMacros ? "yes" : "no",  label: "Macros",
                        badge: s.hasMacros ? .warning : nil),
            ]
        case .unknown:
            return []
        }
    }

    private func badges(for s: OOXMLSummary) -> [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        if s.hasMacros {
            out.append(.init(text: "Macros", style: .warning, icon: "bolt.shield"))
        }
        switch s.kind {
        case .docx:
            if s.trackedChangeCount > 0 {
                out.append(.init(text: "Tracked changes", style: .info,
                                 icon: "pencil.and.list.clipboard"))
            }
            if s.commentCount > 0 {
                out.append(.init(text: "\(s.commentCount) comments", style: .info,
                                 icon: "bubble.left"))
            }
        case .xlsx:
            if s.formulaCount > 0 {
                out.append(.init(text: "\(s.formulaCount) formulas", style: .info,
                                 icon: "function"))
            }
        case .pptx:
            if s.hasSpeakerNotes {
                out.append(.init(text: "Speaker notes", style: .info,
                                 icon: "text.bubble"))
            }
        case .unknown:
            break
        }
        return out
    }

    private func summaryPanel(for s: OOXMLSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(s.kind.displayLabel.uppercased())
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            Text(item.displayName)
                .font(PreviewTokens.fontHeader)
                .foregroundStyle(PreviewTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        previewURL = nil
        summary = nil
        loadError = nil
        cleanupTemp()

        let resolved = await resolvePreviewURL()
        guard let resolved else {
            loadError = "The data source didn't provide a URL or bytes."
            return
        }
        self.previewURL = resolved

        // Only parse OOXML for the office kinds — iWork / RTF aren't
        // OOXML containers. Parsing runs off the main actor because
        // unzip+XMLParser is meaningful work for large files.
        let ext = item.fileExtension ?? ""
        if OfficeKind(extension: ext) != .unknown {
            let parsed = await Task.detached(priority: .userInitiated) {
                try? OOXMLParser.summarise(fileURL: resolved)
            }.value
            self.summary = parsed
        }
    }

    @MainActor
    private func resolvePreviewURL() async -> URL? {
        if let url { return url }
        guard let data else { return nil }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("previewkit-office", isDirectory: true)
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
}

// MARK: - QuickLookHost (NSViewRepresentable)

/// Wraps Quartz's `QLPreviewView`. The view owns a URL; when the URL
/// changes we swap `previewItem`. QLPreviewView is documented as a
/// main-thread-only API; that's enforced implicitly by the
/// `@MainActor` surrounding context.
private struct QuickLookHost: NSViewRepresentable {

    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        view.shouldCloseWithWindow = false
        view.previewItem = url as QLPreviewItem
        return view
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        if (nsView.previewItem as? URL) != url {
            nsView.previewItem = url as QLPreviewItem
        }
    }
}
