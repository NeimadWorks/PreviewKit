// ArchiveNavigatorView — the root sidebar of PreviewSplitView.
//
// Hosts the search field, the Tree/Flat segmented control, and the
// currently-selected sub-view. Selection lives in the parent
// (PreviewSplitView) via a binding so the renderer column can react
// without the navigator having to know about it.

import SwiftUI

public struct ArchiveNavigatorView: View {

    public let dataSource: any NavigatorDataSource
    @Binding public var selectedID: UUID?
    public let onDoubleTap: ((PreviewItem) -> Void)?
    public let onHoverItem: ((PreviewItem?) -> Void)?

    @State private var filter: String = ""
    @AppStorage("previewkit.navigator.mode") private var modeRaw: String = Mode.tree.rawValue

    public enum Mode: String, CaseIterable, Sendable {
        case tree, flat
        public var label: String {
            switch self {
            case .tree: return "Tree"
            case .flat: return "Flat"
            }
        }
    }

    public init(
        dataSource: any NavigatorDataSource,
        selectedID: Binding<UUID?>,
        onDoubleTap: ((PreviewItem) -> Void)? = nil,
        onHoverItem: ((PreviewItem?) -> Void)? = nil
    ) {
        self.dataSource = dataSource
        self._selectedID = selectedID
        self.onDoubleTap = onDoubleTap
        self.onHoverItem = onHoverItem
    }

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .tree }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchField
            Divider().opacity(0.3)
            modePicker
            Divider().opacity(0.3)
            content
        }
        .frame(minWidth: PreviewTokens.navigatorMinWidth,
               idealWidth: PreviewTokens.navigatorDefaultWidth,
               maxWidth: PreviewTokens.navigatorMaxWidth)
        .background(PreviewTokens.bgTertiary)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(PreviewTokens.textMuted)
            TextField("Filter", text: $filter)
                .textFieldStyle(.plain)
                .font(PreviewTokens.fontBodyLarge)
            if !filter.isEmpty {
                Button {
                    filter = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(PreviewTokens.textGhost)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { mode },
            set: { modeRaw = $0.rawValue }
        )) {
            ForEach(Mode.allCases, id: \.self) { m in
                Text(m.label).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let roots = dataSource.rootItems
        switch mode {
        case .tree:
            CollectionTreeView(
                roots: roots,
                selectedID: selectedID,
                filter: filter,
                onSelect: { selectedID = $0.isGroup ? selectedID : $0.id },
                onDoubleTap: onDoubleTap,
                onHoverItem: onHoverItem
            )
            .id(dataSource.refreshToken)
        case .flat:
            FlatListView(
                roots: roots,
                selectedID: selectedID,
                filter: filter,
                onSelect: { selectedID = $0.id },
                onDoubleTap: onDoubleTap,
                onHoverItem: onHoverItem
            )
            .id(dataSource.refreshToken)
        }
    }
}
