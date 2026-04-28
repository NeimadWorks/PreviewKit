// NavigatorItemRow — one row in the navigator. Same row shape is used
// for both tree and flat modes; group vs. leaf is inferred from the item
// kind and an optional disclosure binding supplied by the tree.

import SwiftUI

public struct NavigatorItemRow: View {

    public let item: PreviewItem
    public let isSelected: Bool
    public let showRatio: Bool
    /// Non-nil when this row represents a disclosable group. Tapping the
    /// chevron toggles the binding; tapping the row body still selects.
    public let disclosure: Binding<Bool>?
    public let onTap: () -> Void
    public let onDoubleTap: (() -> Void)?
    public let onHoverChange: ((Bool) -> Void)?

    @State private var isHovering: Bool = false

    public init(
        item: PreviewItem,
        isSelected: Bool,
        showRatio: Bool = true,
        disclosure: Binding<Bool>? = nil,
        onTap: @escaping () -> Void,
        onDoubleTap: (() -> Void)? = nil,
        onHoverChange: ((Bool) -> Void)? = nil
    ) {
        self.item = item
        self.isSelected = isSelected
        self.showRatio = showRatio
        self.disclosure = disclosure
        self.onTap = onTap
        self.onDoubleTap = onDoubleTap
        self.onHoverChange = onHoverChange
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let disclosure {
                Button {
                    withAnimation(.easeInOut(duration: PreviewTokens.foldAnimationDuration)) {
                        disclosure.wrappedValue.toggle()
                    }
                } label: {
                    Image(systemName: disclosure.wrappedValue ? "chevron.down" : "chevron.right")
                        .imageScale(.small)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .frame(width: 10)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 10)
            }

            Image(systemName: item.kind.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(iconColor)
                .frame(width: 16, alignment: .center)

            Text(item.displayName)
                .font(PreviewTokens.fontBodyLarge)
                .foregroundStyle(PreviewTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if item.isGroup, let count = item.children?.count {
                Text("\(count)")
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textGhost)
            }

            if !item.isGroup {
                Text(shortSize)
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textGhost)
            }

            if showRatio, let r = item.cairnMeta?.ratio, item.cairnMeta?.hasUsableRatio == true {
                Text(formatRatio(r))
                    .font(PreviewTokens.fontLabel.monospacedDigit())
                    .foregroundStyle(ratioColor(r))
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                .fill(isSelected
                      ? PreviewTokens.bgSelected
                      : (isHovering ? PreviewTokens.bgHover : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onDoubleTap?() }
        .onTapGesture { onTap() }
        .onHover { hovering in
            isHovering = hovering
            onHoverChange?(hovering)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.displayName))
    }

    // MARK: - Derived display

    private var iconColor: Color {
        if item.isGroup { return PreviewTokens.accentOrange }
        return PreviewTokens.mimeColor(for: item.kind.family)
    }

    private var shortSize: String {
        guard item.sizeBytes >= 0 else { return "" }
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        bcf.allowedUnits = [.useKB, .useMB, .useGB]
        return bcf.string(fromByteCount: item.sizeBytes)
    }

    private func formatRatio(_ r: Double) -> String {
        String(format: "%.0f%%", min(1, max(0, r)) * 100)
    }

    private func ratioColor(_ r: Double) -> Color {
        if r < 0.25 { return Color.green }
        if r < 0.60 { return Color.orange.opacity(0.9) }
        return PreviewTokens.textMuted
    }
}
