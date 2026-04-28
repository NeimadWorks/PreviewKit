// CompressionRing — concentric ring chart.
//
// Outer ring = Cairn ratio (present only in Cairn; nil in Canopy).
// Inner ring = the artifact's own intrinsic compression (archive entry
// ratio, codec efficiency, etc.). Both fractions are clamped to [0, 1];
// "compressed to 18% of original" means fraction 0.18.

import SwiftUI

public struct CompressionRing: View {

    public let outerFraction: Double?
    public let innerFraction: Double
    public let centerLabel: String
    public let subtitle: String
    public let diameter: CGFloat

    public init(
        outerFraction: Double?,
        innerFraction: Double,
        centerLabel: String,
        subtitle: String,
        diameter: CGFloat = 120
    ) {
        self.outerFraction = outerFraction
        self.innerFraction = innerFraction
        self.centerLabel = centerLabel
        self.subtitle = subtitle
        self.diameter = diameter
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let outer = outerFraction {
                    ringPath(fraction: clamp(outer), trackColor: PreviewTokens.borderFaint,
                             color: PreviewTokens.cairnTeal, lineWidth: 6)
                        .frame(width: diameter, height: diameter)
                }
                ringPath(fraction: clamp(innerFraction),
                         trackColor: PreviewTokens.borderFaint,
                         color: Color.secondary,
                         lineWidth: 6)
                    .frame(width: diameter - (outerFraction == nil ? 0 : 16),
                           height: diameter - (outerFraction == nil ? 0 : 16))
                VStack(spacing: 0) {
                    Text(centerLabel)
                        .font(PreviewTokens.fontKPIValue)
                        .foregroundStyle(PreviewTokens.textPrimary)
                    Text(subtitle)
                        .font(PreviewTokens.fontLabel)
                        .tracking(PreviewTokens.labelLetterSpacing)
                        .foregroundStyle(PreviewTokens.textMuted)
                        .textCase(.uppercase)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(subtitle): \(centerLabel)"))
    }

    private func ringPath(
        fraction: Double,
        trackColor: Color,
        color: Color,
        lineWidth: CGFloat
    ) -> some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }

    private func clamp(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(1, max(0, v))
    }
}
