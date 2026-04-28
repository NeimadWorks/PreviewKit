// MIMEBar — proportional horizontal bar + legend, used by the archive
// and overview renderers to show entry distribution by MIME family.

import SwiftUI

public struct MIMESegment: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let label: String
    public let fraction: Double
    public let family: ArtifactKind.Family

    public init(
        id: UUID = UUID(),
        label: String,
        fraction: Double,
        family: ArtifactKind.Family
    ) {
        self.id = id
        self.label = label
        self.fraction = max(0, fraction)
        self.family = family
    }
}

public struct MIMEBar: View {

    public let segments: [MIMESegment]
    public let barHeight: CGFloat

    public init(segments: [MIMESegment], barHeight: CGFloat = 6) {
        self.segments = Self.normalise(segments)
        self.barHeight = barHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments) { seg in
                        Rectangle()
                            .fill(PreviewTokens.mimeColor(for: seg.family))
                            .frame(width: geo.size.width * seg.fraction)
                    }
                }
            }
            .frame(height: barHeight)
            .clipShape(Capsule())

            FlowLayout(spacing: 10, runSpacing: 4) {
                ForEach(segments) { seg in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(PreviewTokens.mimeColor(for: seg.family))
                            .frame(width: 6, height: 6)
                        Text(seg.label)
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                        Text(String(format: "%.0f%%", seg.fraction * 100))
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textGhost)
                    }
                }
            }
        }
    }

    /// Normalise a potentially-unnormalised set to fractions that sum to
    /// 1.0. If the input sum is zero we return the input unchanged — the
    /// bar will render empty, which is the correct visual signal.
    public static func normalise(_ input: [MIMESegment]) -> [MIMESegment] {
        let sum = input.reduce(0.0) { $0 + $1.fraction }
        guard sum > 0 else { return input }
        if abs(sum - 1.0) < 1e-6 { return input }
        return input.map {
            MIMESegment(id: $0.id, label: $0.label,
                        fraction: $0.fraction / sum, family: $0.family)
        }
    }
}
