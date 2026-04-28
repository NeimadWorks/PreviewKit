// LeadBlock — first-paragraph emphasis block. Used by Markdown, PDF, and
// office renderers to surface the document's "lead" prominently at the
// top of the inspector, styled like a pull-quote.

import SwiftUI

public struct LeadBlock: View {

    public let text: String
    public let maxLines: Int
    @State private var expanded: Bool = false

    public init(text: String, maxLines: Int = 3) {
        self.text = text
        self.maxLines = max(1, maxLines)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .padding(.vertical, 2)
                Text(text.isEmpty ? "—" : text)
                    .font(PreviewTokens.fontBodyLarge)
                    .foregroundStyle(PreviewTokens.textSecondary)
                    .lineLimit(expanded ? nil : maxLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !expanded && shouldTruncate {
                Button("Read more") { expanded = true }
                    .buttonStyle(.plain)
                    .font(PreviewTokens.fontLabel)
                    .foregroundStyle(PreviewTokens.textMuted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
    }

    /// Rough heuristic — expose "Read more" when the paragraph is longer
    /// than ~80 chars × maxLines, to avoid a dead button on short leads.
    private var shouldTruncate: Bool {
        text.count > 80 * maxLines
    }
}
