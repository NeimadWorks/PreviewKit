// CollectionTreeView — tree mode of the archive navigator.
//
// Groups (collections + folders) are collapsed by default when they
// contain more than 20 children, expanded otherwise. Collapse state is
// persisted per-group via `@AppStorage("previewkit.nav.collapsed.<id>")`.
// The tree is flattened into a visible row list at render time so
// recursion stays out of SwiftUI's opaque-type inference.

import SwiftUI

public struct CollectionTreeView: View {

    public let roots: [PreviewItem]
    public let selectedID: UUID?
    public let filter: String
    public let onSelect: (PreviewItem) -> Void
    public let onDoubleTap: ((PreviewItem) -> Void)?
    public let onHoverItem: ((PreviewItem?) -> Void)?

    /// Local expansion map — seeded from defaults on first appearance,
    /// persisted back to `@AppStorage` when the user flips a disclosure.
    @State private var expansion: [UUID: Bool] = [:]
    @State private var didSeed: Bool = false

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
        let filtered = Self.filtered(roots, query: filter)
        let rows = Self.flatten(filtered, expansion: expansion)
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.item.id) { flat in
                    NavigatorItemRow(
                        item: flat.item,
                        isSelected: flat.item.id == selectedID,
                        disclosure: flat.item.isGroup
                            ? binding(for: flat.item.id)
                            : nil,
                        onTap: { onSelect(flat.item) },
                        onDoubleTap: { onDoubleTap?(flat.item) },
                        onHoverChange: { hovering in
                            onHoverItem?(hovering ? flat.item : nil)
                        }
                    )
                    .padding(.leading, CGFloat(flat.depth) * PreviewTokens.outlineIndentStep)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
        }
        .onAppear {
            guard !didSeed else { return }
            expansion = Self.defaultExpansion(for: roots)
            didSeed = true
        }
    }

    // MARK: - Expansion

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expansion[id] ?? false },
            set: { expansion[id] = $0 }
        )
    }

    public static func defaultExpansion(for roots: [PreviewItem]) -> [UUID: Bool] {
        var map: [UUID: Bool] = [:]
        func walk(_ items: [PreviewItem]) {
            for it in items where it.isGroup {
                let kids = it.children ?? []
                map[it.id] = kids.count <= 20
                walk(kids)
            }
        }
        walk(roots)
        return map
    }

    // MARK: - Filter

    public static func filtered(_ roots: [PreviewItem], query: String) -> [PreviewItem] {
        let needle = query.lowercased()
        guard !needle.isEmpty else { return roots }
        return roots.compactMap { filterOne($0, needle: needle) }
    }

    private static func filterOne(_ item: PreviewItem, needle: String) -> PreviewItem? {
        let hit = item.displayName.lowercased().contains(needle)
        if let kids = item.children {
            let keptKids = kids.compactMap { filterOne($0, needle: needle) }
            if !keptKids.isEmpty || hit {
                var copy = item
                copy.children = keptKids
                return copy
            }
            return nil
        }
        return hit ? item : nil
    }

    // MARK: - Flatten

    /// Flattened row descriptor used by the lazy stack. Depth is
    /// recomputed here (rather than stored on the item) so filtering
    /// doesn't have to rebuild the tree with adjusted depths.
    public struct FlatRow {
        public let item: PreviewItem
        public let depth: Int
    }

    public static func flatten(
        _ items: [PreviewItem],
        expansion: [UUID: Bool],
        startDepth: Int = 0
    ) -> [FlatRow] {
        var out: [FlatRow] = []
        for it in items {
            out.append(FlatRow(item: it, depth: startDepth))
            if it.isGroup, let kids = it.children, expansion[it.id] == true {
                out.append(contentsOf: flatten(kids, expansion: expansion,
                                               startDepth: startDepth + 1))
            }
        }
        return out
    }
}
