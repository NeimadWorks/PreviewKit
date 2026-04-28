// WaveformView — Canvas-drawn stereo-collapsed PCM waveform.
//
// Moved from Session 1's "skipped" list to Session 4 where the
// `MediaRenderer` consumes it. Kept in the shared Components folder
// because a host might want to embed a waveform outside the audio
// renderer (e.g., a podcast timeline view).

import SwiftUI

public struct WaveformView: View {

    public let samples: [Float]
    public let color: Color
    public let lineWidth: CGFloat

    public init(samples: [Float], color: Color = .accentColor, lineWidth: CGFloat = 1) {
        self.samples = samples
        self.color = color
        self.lineWidth = lineWidth
    }

    public var body: some View {
        Canvas { ctx, size in
            guard !samples.isEmpty else { return }
            let w = size.width
            let h = size.height
            let midY = h / 2
            let step = w / CGFloat(max(1, samples.count - 1))

            var top = Path()
            var bottom = Path()
            var bottomReversePoints: [CGPoint] = []
            for (i, s) in samples.enumerated() {
                let x = CGFloat(i) * step
                let amp = CGFloat(max(0, min(1, s))) * (h / 2 - 1)
                let topPt = CGPoint(x: x, y: midY - amp)
                let botPt = CGPoint(x: x, y: midY + amp)
                if i == 0 {
                    top.move(to: topPt)
                    bottom.move(to: botPt)
                } else {
                    top.addLine(to: topPt)
                    bottom.addLine(to: botPt)
                }
                bottomReversePoints.append(botPt)
            }
            var fill = top
            // Walk the bottom edge in reverse to close the fill region.
            for pt in bottomReversePoints.reversed() {
                fill.addLine(to: pt)
            }
            fill.closeSubpath()
            ctx.fill(fill, with: .color(color.opacity(0.25)))
            ctx.stroke(top, with: .color(color), lineWidth: lineWidth)
            ctx.stroke(bottom, with: .color(color), lineWidth: lineWidth)

            // Centre baseline.
            var base = Path()
            base.move(to: CGPoint(x: 0, y: midY))
            base.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(base, with: .color(color.opacity(0.35)), lineWidth: 0.5)
        }
        .accessibilityLabel(Text("Audio waveform"))
    }
}
