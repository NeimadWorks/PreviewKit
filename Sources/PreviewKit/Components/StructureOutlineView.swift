// StructureOutlineView — TOC view with three display modes
// (compact / scroll / full). Mode persists per storage key.
//
// Rendering is iterative (flat list, depth-indented) to avoid recursive
// opaque return types — each row carries its own depth, and children of
// an expanded node are spliced into the list at render time.

import SwiftUI

public struct StructureOutlineView: View {

    public let entries: [OutlineEntry]
    public let storageKey: String
    public let onSelect: ((OutlineEntry) -> Void)?

    public enum Mode: String, CaseIterable, Sendable {
        case compact, scroll, full
    }

    @AppStorage private var modeRaw: String
    @State private var expansion: [UUID: Bool] = [:]

    public init(
        entries: [OutlineEntry],
        storageKey: String,
        defaultMode: Mode = .compact,
        onSelect: ((OutlineEntry) -> Void)? = nil
    ) {
        self.entries = entries
        self.storageKey = storageKey
        self.onSelect = onSelect
        self._modeRaw = AppStorage(
            wrappedValue: defaultMode.rawValue,
            "previewkit.outline.mode.\(storageKey)"
        )
    }

    private var mode: Mode {
        Mode(rawValue: modeRaw) ?? .compact
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            content
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            Text("OUTLINE")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            Spacer()
            Picker("", selection: Binding(
                get: { mode },
                set: { modeRaw = $0.rawValue }
            )) {
                ForEach(Mode.allCases, id: \.self) { m in
                    Text(m.rawValue.capitalized).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
            .controlSize(.mini)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            Text("No outline available")
                .font(PreviewTokens.fontBody)
                .foregroundStyle(PreviewTokens.textGhost)
                .padding(.vertical, 8)
        } else {
            let flat = Self.flatten(entries, expansion: expansion)
            switch mode {
            case .compact:
                let visible = Array(flat.prefix(PreviewTokens.outlineCompactMaxItems))
                let remaining = max(0, flat.count - visible.count)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visible) { outlineRow($0) }
                    if remaining > 0 {
                        Button {
                            modeRaw = Mode.scroll.rawValue
                        } label: {
                            Text("Show all \(flat.count) →")
                                .font(PreviewTokens.fontBody)
                                .foregroundStyle(PreviewTokens.textMuted)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            case .scroll:
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(flat) { outlineRow($0) }
                    }
                    .padding(.trailing, 4)
                }
                .frame(height: PreviewTokens.outlineScrollHeight)
            case .full:
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(flat) { outlineRow($0) }
                }
            }
        }
    }

    // MARK: - Row

    private func outlineRow(_ entry: OutlineEntry) -> some View {
        let hasKids = !entry.children.isEmpty
        let expanded = expansion[entry.id] ?? false
        let indent = CGFloat(min(entry.depth, 3)) * PreviewTokens.outlineIndentStep
        let kindColor = PreviewTokens.outlineKindColor(entry.kind)

        return HStack(spacing: 6) {
            Spacer().frame(width: indent)
            Button {
                if hasKids {
                    withAnimation(.easeInOut(duration: PreviewTokens.foldAnimationDuration)) {
                        expansion[entry.id] = !expanded
                    }
                }
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(hasKids ? PreviewTokens.textMuted : Color.clear)
                    .frame(width: 10)
            }
            .buttonStyle(.plain)
            .disabled(!hasKids)

            Button {
                onSelect?(entry)
            } label: {
                HStack(spacing: 4) {
                    Text(entry.title)
                        .font(PreviewTokens.fontBodyLarge)
                        .foregroundStyle(PreviewTokens.textPrimary)
                        .lineLimit(1)
                    if let subtitle = entry.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(PreviewTokens.fontBody)
                            .foregroundStyle(PreviewTokens.textGhost)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                }
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(kindColor)
                .frame(width: PreviewTokens.outlineWeightBarMaxWidth * entry.weightFraction,
                       height: PreviewTokens.outlineWeightBarHeight)
                .clipShape(Capsule())
                .opacity(entry.weightFraction > 0 ? 1 : 0)
        }
        .frame(height: PreviewTokens.outlineRowHeight)
        .contentShape(Rectangle())
    }

    // MARK: - Flattening

    /// Walk the tree in DFS order, splicing children of expanded nodes
    /// into the flat list. Exposed for tests.
    public static func flatten(
        _ entries: [OutlineEntry],
        expansion: [UUID: Bool] = [:]
    ) -> [OutlineEntry] {
        var out: [OutlineEntry] = []
        out.reserveCapacity(entries.count)
        for e in entries {
            out.append(e)
            if !e.children.isEmpty && (expansion[e.id] ?? false) {
                out.append(contentsOf: flatten(e.children, expansion: expansion))
            }
        }
        return out
    }
}
