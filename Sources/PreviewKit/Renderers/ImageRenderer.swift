// ImageRenderer — stills (JPEG / PNG / HEIC / WEBP / TIFF / GIF / BMP /
// SVG). Left: zoom+pan image view. Right: EXIF / GPS summary, RGB
// histogram, 5-swatch dominant palette, CairnMeta.

import SwiftUI
import AppKit
import ImageIO

public struct ImageRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> {
        [.jpeg, .png, .heic, .webp, .tiff, .gif, .bmp, .svg]
    }
    public static var priority: Int { 0 }
    public static func make() -> ImageRenderer { ImageRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(ImageRendererBody(item: item, data: data, url: url))
    }
}

struct ImageRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var image: NSImage?
    @State private var stats: ImageStats?
    @State private var histogram: RGBHistogram?
    @State private var dominantColors: [SRGBColor] = []
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var loadError: String?

    var body: some View {
        ResponsiveSplit {
            leftPane
        } inspector: {
            inspectorPane
        }
        .task(id: item.id) { await load() }
    }

    // MARK: - Left

    @ViewBuilder
    private var leftPane: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't decode image",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else if let image {
            GeometryReader { geo in
                ZStack {
                    Color(nsColor: .textBackgroundColor)
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(pan)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    zoom = max(0.1, min(12, scale))
                                }
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { v in pan = v.translation }
                        )
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .overlay(alignment: .topTrailing) {
                    zoomBar
                }
            }
        } else {
            ProgressView("Loading image…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var zoomBar: some View {
        HStack(spacing: 6) {
            Button { zoom = max(0.1, zoom / 1.25); pan = .zero } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            Text(String(format: "%.0f%%", zoom * 100))
                .font(PreviewTokens.fontLabel.monospacedDigit())
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(minWidth: 38)
            Button { zoom = min(12, zoom * 1.25) } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            Button { zoom = 1; pan = .zero } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .help("Fit")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary.opacity(0.92))
        )
        .padding(10)
    }

    // MARK: - Right

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if let s = stats, let gps = s.gps {
                    gpsBlock(latitude: gps.latitude, longitude: gps.longitude)
                }
                if !exifRows.isEmpty {
                    exifBlock
                }
                if let h = histogram {
                    histogramBlock(h)
                }
                if !dominantColors.isEmpty {
                    paletteBlock
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private var kpis: [KPITile] {
        guard let stats else {
            return [
                .placeholder(label: "Width"),
                .placeholder(label: "Height"),
                .placeholder(label: "DPI"),
                .placeholder(label: "Color"),
            ]
        }
        return [
            KPITile(value: "\(stats.pixelWidth)",  label: "Width"),
            KPITile(value: "\(stats.pixelHeight)", label: "Height"),
            KPITile(value: String(format: "%.0f",  stats.dpi), label: "DPI"),
            KPITile(value: stats.colorSpace,       label: "Color"),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        guard let stats else { return [] }
        var out: [SemanticBadgeModel] = []
        if stats.gps != nil {
            out.append(.init(text: "GPS", style: .info, icon: "location.fill"))
        }
        if !stats.exif.isEmpty {
            out.append(.init(text: "EXIF", style: .info, icon: "text.magnifyingglass"))
        }
        if stats.hasAlpha {
            out.append(.init(text: "Alpha", style: .info, icon: "square.fill.on.square"))
        }
        if stats.isHDR {
            out.append(.init(text: "HDR", style: .info, icon: "sun.max"))
        }
        if stats.hasICCProfile {
            out.append(.init(text: "ICC", style: .info, icon: "paintpalette"))
        }
        return out
    }

    private var exifRows: [(String, String)] {
        guard let stats else { return [] }
        var rows: [(String, String)] = []
        if let camera = stats.cameraModel      { rows.append(("Camera", camera)) }
        if let lens   = stats.lensModel        { rows.append(("Lens", lens)) }
        if let mm     = stats.focalLengthMM    { rows.append(("Focal", String(format: "%.0fmm", mm))) }
        if let iso    = stats.iso              { rows.append(("ISO", "\(iso)")) }
        if let ss     = stats.shutterSpeed     { rows.append(("Shutter", ss)) }
        if let ap     = stats.aperture         { rows.append(("Aperture", String(format: "ƒ/%.1f", ap))) }
        if let t      = stats.colorTempKelvin  { rows.append(("Kelvin", "\(t)K")) }
        return rows
    }

    private var exifBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EXIF")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(exifRows, id: \.0) { pair in
                    HStack(alignment: .firstTextBaseline) {
                        Text(pair.0)
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                            .frame(width: 58, alignment: .leading)
                        Text(pair.1)
                            .font(PreviewTokens.fontMonoLarge)
                            .foregroundStyle(PreviewTokens.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                    .fill(PreviewTokens.bgSecondary)
            )
        }
    }

    private func gpsBlock(latitude: Double, longitude: Double) -> some View {
        Button {
            if let url = URL(string: "maps://?q=\(latitude),\(longitude)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Location")
                        .font(PreviewTokens.fontLabel)
                        .tracking(PreviewTokens.labelLetterSpacing)
                        .foregroundStyle(PreviewTokens.textMuted)
                    Text(String(format: "%.5f, %.5f", latitude, longitude))
                        .font(PreviewTokens.fontMonoLarge)
                        .foregroundStyle(PreviewTokens.textPrimary)
                }
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(PreviewTokens.textMuted)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                    .fill(PreviewTokens.bgSecondary)
            )
        }
        .buttonStyle(.plain)
    }

    private func histogramBlock(_ h: RGBHistogram) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HISTOGRAM")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            Canvas { ctx, size in
                let maxCount = max(1, h.maxBucket)
                func drawChannel(_ buckets: [Int], _ color: Color) {
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: size.height))
                    for (i, n) in buckets.enumerated() {
                        let x = CGFloat(i) / 255 * size.width
                        let y = size.height - CGFloat(n) / CGFloat(maxCount) * size.height
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: size.width, y: size.height))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(color.opacity(0.30)))
                }
                drawChannel(h.red,   .red)
                drawChannel(h.green, .green)
                drawChannel(h.blue,  .blue)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd))
            .overlay(
                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                    .strokeBorder(PreviewTokens.borderFaint, lineWidth: PreviewTokens.borderWidth)
            )
        }
    }

    private var paletteBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PALETTE")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            HStack(spacing: 4) {
                ForEach(dominantColors, id: \.hexTriplet) { c in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                            .fill(Color(red: c.r, green: c.g, blue: c.b))
                            .frame(height: 32)
                        Text(c.hexTriplet)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(PreviewTokens.textGhost)
                    }
                }
            }
        }
    }

    // MARK: - Loading

    @MainActor
    func load() async {
        image = nil
        stats = nil
        histogram = nil
        dominantColors = []
        zoom = 1
        pan = .zero
        loadError = nil

        let bytes: Data? = {
            if let data { return data }
            if let url { return try? Data(contentsOf: url) }
            return nil
        }()
        guard let bytes else {
            loadError = "The data source didn't return image bytes."
            return
        }
        self.image = NSImage(data: bytes)
        let sidecar = hasXMPSidecar()

        let computed: (ImageStats?, RGBHistogram?, [SRGBColor]) = await Task.detached(priority: .userInitiated) {
            let stats = ImageAnalyzer.stats(from: bytes, xmpSidecarExists: sidecar)
            let hist = ImageAnalyzer.histogram(from: bytes)
            let colors = ImageAnalyzer.dominantColors(from: bytes, k: 5)
            return (stats, hist, colors)
        }.value
        self.stats = computed.0
        self.histogram = computed.1
        self.dominantColors = computed.2
    }

    /// Naive XMP-sidecar detection: if `url` is set and a sibling
    /// `.xmp` file is reachable, treat the sidecar as present. This
    /// only fires on file-system hosts; Cairn passes URL through its
    /// temp cache so the check still works for archived RAWs.
    private func hasXMPSidecar() -> Bool {
        guard let url else { return false }
        let sidecar = url.deletingPathExtension().appendingPathExtension("xmp")
        return (try? sidecar.checkResourceIsReachable()) == true
    }
}
