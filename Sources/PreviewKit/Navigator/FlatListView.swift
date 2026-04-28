// FlatListView — flat, sortable list of every leaf in the archive.
// Group nodes are walked into and discarded; leaves keep their logical
// path for display. Sort is applied after filtering.

import SwiftUI

public struct FlatListView: View {

    public let roots: [PreviewItem]
    public let selectedID: UUID?
    public let filter: String
    public let onSelect: (PreviewItem) -> Void
    public let onDoubleTap: ((PreviewItem) -> Void)?
    public let onHoverItem: ((PreviewItem?) -> Void)?

    @State private var sort: SortKey = .name
    @State private var ascending: Bool = true

    public enum SortKey: String, CaseIterable, Sendable {
        case name, size, ratio, modified, kind
        public var label: String {
            switch self {
            case .name:     return "Name"
            case .size:     return "Size"
            case .ratio:    return "Ratio"
            case .modified: return "Modified"
            case .kind:     return "Kind"
            }
        }
    }

    public init(
        roots: [PreviewItem],
        selectedID: UUID?,
        filter: String,
        onSelect: @escaping (PreviewItem) -> Void,
        onDoubleTap: ((PreviewItem) -> Void)? = nil,
        onHoverItem: ((PreviewItem?) -> Void)? = nil
    ) {
        self.roots = roots
        self.selectedID = selectedID
        self.filter = filter
        self.onSelect = onSelect
        self.onDoubleTap = onDoubleTap
        self.onHoverItem = onHoverItem
    }

    public var body: some View {
        let items = Self.sorted(
            Self.filterLeaves(Self.collectLeaves(roots), query: filter),
            by: sort,
            ascending: ascending
        )
        VStack(alignment: .leading, spacing: 0) {
            sortBar
            Divider().opacity(0.3)
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(items) { item in
                        NavigatorItemRow(
                            item: item,
                            isSelected: item.id == selectedID,
                            disclosure: nil,
                            onTap: { onSelect(item) },
                            onDoubleTap: { onDoubleTap?(item) },
                            onHoverChange: { hovering in
                                onHoverItem?(hovering ? item : nil)
                            }
                        )
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Sort bar

    private var sortBar: some View {
        HStack(spacing: 4) {
            ForEach(SortKey.allCases, id: \.self) { key in
                Button {
                    if sort == key {
                        ascending.toggle()
                    } else {
                        sort = key
                        ascending = true
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(key.label)
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(sort == key
                                ? PreviewTokens.textPrimary
                                : PreviewTokens.textMuted)
                        if sort == key {
                            Image(systemName: ascending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(PreviewTokens.textMuted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                        .fill(sort == key ? PreviewTokens.bgHover : Color.clear)
                )
            }
            Spacer()
        }
        .padding(6)
    }

    // MARK: - Collection helpers

    public static func collectLeaves(_ roots: [PreviewItem]) -> [PreviewItem] {
        var out: [PreviewItem] = []
        func walk(_ list: [PreviewItem]) {
            for it in list {
                if it.isGroup, let kids = it.children { walk(kids) }
                else if !it.isGroup { out.append(it) }
            }
        }
        walk(roots)
        return out
    }

    public static func filterLeaves(_ leaves: [PreviewItem], query: String) -> [PreviewItem] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return leaves }
        return leaves.filter {
            $0.displayName.lowercased().contains(needle)
            || $0.logicalPath.lowercased().contains(needle)
        }
    }

    public static func sorted(_ items: [PreviewItem], by key: SortKey, ascending: Bool)
        -> [PreviewItem]
    {
        let cmp: (PreviewItem, PreviewItem) -> Bool = { a, b in
            switch key {
            case .name:
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .size:
                return a.sizeBytes < b.sizeBytes
            case .ratio:
                let ra = a.cairnMeta?.ratio ?? Double.infinity
                let rb = b.cairnMeta?.ratio ?? Double.infinity
                return ra < rb
            case .modified:
                return a.modifiedAt < b.modifiedAt
            case .kind:
                return a.kind.rawValue < b.kind.rawValue
            }
        }
        let sorted = items.sorted(by: cmp)
        return ascending ? sorted : sorted.reversed()
    }
}
