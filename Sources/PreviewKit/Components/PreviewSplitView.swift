// PreviewSplitView — the public root view consumers mount.
//
// Layout:
//   ┌──────────────┬─────────────────────────────────────────────┐
//   │ Navigator    │ Renderer                                    │
//   │ (search +    │ ┌─ header ─────────────────────────────────┐│
//   │ tree/flat)   │ │ name · kind · toolbar (export / open …)  ││
//   │              │ ├──────────────────────────────────────────┤│
//   │              │ │ renderer body (dispatched by kind)       ││
//   │              │ └──────────────────────────────────────────┘│
//   └──────────────┴─────────────────────────────────────────────┘
//
// The split view owns the selection + loading ticket and bridges
// navigator (what's selected) to renderer (what to draw). A host
// supplies the data source + an optional `cairnMetaProvider` for
// Cairn-specific metadata injection.

import SwiftUI
import AppKit

public struct PreviewSplitView: View {

    public let dataSource: any PreviewDataSource
    public let cairnMetaProvider: ((PreviewItem) -> CairnMeta?)?
    public let navigatorWidth: CGFloat
    public let onExport: ((PreviewItem) -> Void)?
    public let onOpenWithDefault: ((PreviewItem) -> Void)?
    public let onNavigate: ((PreviewNavigationTarget) -> Void)?
    public let archiveIsOpen: Bool

    @State private var selectedID: UUID?
    @State private var loadedData: Data?
    @State private var loadedURL: URL?
    @State private var isLoading: Bool = false
    @State private var loadError: String?
    @State private var lastLoadedID: UUID?
    @State private var hoverPreview: PreviewItem?

    public init(
        dataSource: any PreviewDataSource,
        cairnMetaProvider: ((PreviewItem) -> CairnMeta?)? = nil,
        navigatorWidth: CGFloat = PreviewTokens.navigatorDefaultWidth,
        onExport: ((PreviewItem) -> Void)? = nil,
        onOpenWithDefault: ((PreviewItem) -> Void)? = nil,
        onNavigate: ((PreviewNavigationTarget) -> Void)? = nil,
        archiveIsOpen: Bool = true
    ) {
        self.dataSource = dataSource
        self.cairnMetaProvider = cairnMetaProvider
        self.navigatorWidth = navigatorWidth
        self.onExport = onExport
        self.onOpenWithDefault = onOpenWithDefault
        self.onNavigate = onNavigate
        self.archiveIsOpen = archiveIsOpen
    }

    public var body: some View {
        HSplitView {
            ArchiveNavigatorView(
                dataSource: dataSource,
                selectedID: $selectedID,
                onDoubleTap: { onOpenWithDefault?($0) },
                onHoverItem: { scheduleHoverPreview(for: $0) }
            )
            .frame(minWidth: PreviewTokens.navigatorMinWidth,
                   idealWidth: navigatorWidth,
                   maxWidth: PreviewTokens.navigatorMaxWidth)

            rendererColumn
                .frame(minWidth: PreviewTokens.rendererMinWidth
                              + PreviewTokens.inspectorMinWidth)
        }
        .task(id: selectedID) {
            await loadSelectionIfNeeded()
        }
        .background(
            // Invisible button owns the ␣-to-Quick-Look shortcut for
            // the currently-loaded item. Placing it in `.background`
            // keeps it inside the split-view's focus chain without
            // disturbing layout.
            Button("") { quickLookCurrentSelection() }
                .keyboardShortcut(.space, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .disabled(loadedURL == nil)
        )
    }

    /// Throttles the hover preview to the `hoverPreviewDelay` window
    /// so a quick pass across rows doesn't flash the popover. Clearing
    /// hover cancels any pending schedule.
    private func scheduleHoverPreview(for item: PreviewItem?) {
        guard let item else {
            hoverPreview = nil
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(PreviewTokens.hoverPreviewDelay * 1_000_000_000))
            // Only publish if the hover is still on the same item.
            hoverPreview = item
        }
    }

    private func quickLookCurrentSelection() {
        guard let url = loadedURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Renderer column

    @ViewBuilder
    private var rendererColumn: some View {
        if let item = resolvedSelected {
            VStack(spacing: 0) {
                toolbar(for: item)
                Divider().opacity(0.3)
                rendererBody(for: item)
            }
            .background(PreviewTokens.bgPrimary)
            .contextMenu { contextMenu(for: item) }
        } else {
            OverviewRenderer.render(
                dataSource: dataSource,
                onFamilyTap: { _ in /* v1: no-op. Session 5 wires this to filter. */ }
            )
        }
    }

    @ViewBuilder
    private func rendererBody(for item: PreviewItem) -> some View {
        if isLoading && lastLoadedID != item.id {
            loadingView
        } else if let loadError, lastLoadedID == item.id {
            ContentUnavailableMessage(
                title: "Couldn't load this item",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else {
            let renderer = RendererRegistry.shared.renderer(for: item.kind)
            renderer.body(for: item, data: loadedData, url: loadedURL)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Loading…")
                .font(PreviewTokens.fontBody)
                .foregroundStyle(PreviewTokens.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    private func toolbar(for item: PreviewItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(PreviewTokens.mimeColor(for: item.kind.family))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.displayName)
                    .font(PreviewTokens.fontHeader)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.logicalPath)
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if onExport != nil {
                Button {
                    onExport?(item)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)
            }
            if onOpenWithDefault != nil {
                Button {
                    onOpenWithDefault?(item)
                } label: {
                    Label("Open", systemImage: "arrow.up.forward.app")
                }
                .controlSize(.small)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.logicalPath, forType: .string)
            } label: {
                Label("Copy path", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
            .help("Copy logical path to clipboard")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenu(for item: PreviewItem) -> some View {
        let env = PreviewContextEnvironment(
            focusedItem: item,
            selectedItems: [],      // multi-select threaded in a later revision
            archiveOpen: archiveIsOpen,
            hasCairnMeta: item.cairnMeta != nil
        )
        PreviewContextMenu(environment: env) { action in
            handle(action: action, on: item)
        }
        if item.cairnMeta != nil {
            Divider()
            Button("Copy archive metadata JSON") {
                PreviewContextHandler.copyString(Self.metaJSON(for: item))
            }
        }
    }

    /// Dispatch: pure actions land in `PreviewContextHandler`; impure
    /// ones route through host closures.
    private func handle(action: PreviewContextAction, on item: PreviewItem) {
        if PreviewContextHandler.handleLocally(action, for: item, resolvedURL: loadedURL) {
            return
        }
        switch action {
        case .preview:
            selectedID = item.id
        case .showInHistory:
            onNavigate?(.history(itemID: item.id))
        case .showInVitals:
            onNavigate?(.vitals(itemID: item.id))
        case .showInSearch:
            onNavigate?(.search(itemID: item.id))
        case .exportTo:
            onExport?(item)
        case .exportAsZIP:
            onExport?(item)   // host can special-case the kind
        case .exportSelection, .computeSelectionTotal:
            onExport?(item)
        case .showArchiveInfo:
            onNavigate?(.vitals(itemID: nil))
        default:
            break
        }
    }

    // MARK: - Loading

    private var resolvedSelected: PreviewItem? {
        guard let id = selectedID else { return nil }
        var raw = find(id: id, in: dataSource.rootItems)
        if let r = raw, let provider = cairnMetaProvider, r.cairnMeta == nil {
            raw?.cairnMeta = provider(r)
        }
        return raw
    }

    private func find(id: UUID, in items: [PreviewItem]) -> PreviewItem? {
        for it in items {
            if it.id == id { return it }
            if let kids = it.children, let hit = find(id: id, in: kids) {
                return hit
            }
        }
        return nil
    }

    @MainActor
    private func loadSelectionIfNeeded() async {
        guard let id = selectedID,
              let item = find(id: id, in: dataSource.rootItems),
              !item.isGroup else {
            loadedData = nil
            loadedURL = nil
            loadError = nil
            lastLoadedID = nil
            return
        }
        isLoading = true
        loadError = nil
        loadedData = nil
        loadedURL = nil

        do {
            // Prefer a temp URL for items over the in-memory limit so large
            // PDFs / video don't eat RAM.
            if item.sizeBytes > dataSource.inMemoryLimitBytes,
               let url = try await dataSource.temporaryURL(for: item) {
                self.loadedURL = url
            } else if let url = try? await dataSource.temporaryURL(for: item) {
                self.loadedURL = url
                self.loadedData = try await dataSource.data(for: item)
            } else {
                self.loadedData = try await dataSource.data(for: item)
            }
        } catch {
            self.loadError = "\(error)"
        }

        self.isLoading = false
        self.lastLoadedID = id
    }

    // MARK: - Utilities

    // MARK: - Navigation targets

    /// Shared vocabulary for host-driven navigation out of the preview
    /// column (context-menu "Show in …" actions).
    public enum PreviewNavigationTarget: Sendable, Hashable {
        case history(itemID: UUID?)
        case vitals(itemID: UUID?)
        case search(itemID: UUID?)
    }

    private static func metaJSON(for item: PreviewItem) -> String {
        guard let meta = item.cairnMeta else { return "{}" }
        var dict: [String: Any] = [
            "displayName": item.displayName,
            "logicalPath": item.logicalPath,
            "kind": item.kind.rawValue,
            "codec": meta.codec,
            "ratio": meta.ratio,
            "originalSizeBytes": meta.originalSizeBytes,
            "storedSizeBytes": meta.storedSizeBytes,
        ]
        if meta.chunkCount > 0 {
            dict["chunks"] = [
                "total": meta.chunkCount,
                "deduped": meta.dedupedChunkCount,
            ]
        }
        let data = (try? JSONSerialization.data(
            withJSONObject: dict,
            options: [.prettyPrinted, .sortedKeys]
        )) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
