// MediaRenderer — video + audio.
//
// Video: AVPlayer-backed view + 8-frame thumbnail strip.
// Audio: cover art (if present) or WaveformView + playback controls.
// Both flavours share the right-pane KPI / tag / CairnMeta layout.

import SwiftUI
import AVKit
import AVFoundation

public struct MediaRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.video, .audio] }
    public static var priority: Int { 0 }
    public static func make() -> MediaRenderer { MediaRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(MediaRendererBody(item: item, data: data, url: url))
    }
}

private struct MediaRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var resolvedURL: URL?
    @State private var ownedTempURL: URL?
    @State private var stats: MediaStats?
    @State private var thumbnails: [NSImage] = []
    @State private var coverArt: NSImage?
    @State private var waveform: [Float] = []
    @State private var player: AVPlayer?
    @State private var loadError: String?

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
        .task(id: item.id) { await load() }
        .onDisappear { cleanupTemp() }
    }

    // MARK: - Left

    @ViewBuilder
    private var leftPane: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't decode media",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else if let player {
            if item.kind == .video {
                VStack(spacing: 0) {
                    VideoPlayer(player: player)
                        .frame(maxHeight: .infinity)
                    videoThumbnailStrip
                }
            } else {
                audioPane(player: player)
            }
        } else {
            ProgressView("Preparing player…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var videoThumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, image in
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: PreviewTokens.filmstripHeight)
                        .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(height: PreviewTokens.filmstripHeight + 8)
        .background(PreviewTokens.bgTertiary)
    }

    @ViewBuilder
    private func audioPane(player: AVPlayer) -> some View {
        VStack(spacing: 16) {
            if let coverArt {
                Image(nsImage: coverArt)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg))
                    .padding(.horizontal, 60)
                    .padding(.top, 24)
            } else if !waveform.isEmpty {
                WaveformView(samples: waveform, color: PreviewTokens.cairnTeal)
                    .frame(height: 160)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
            }
            Spacer()
            VideoPlayer(player: player)
                .frame(height: 44)   // audio-only → just the transport bar
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PreviewTokens.bgPrimary)
    }

    // MARK: - Right

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if !tagRows.isEmpty {
                    tagsBlock
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
                .placeholder(label: "Duration"),
                .placeholder(label: "Codec"),
                .placeholder(label: "Rate"),
                .placeholder(label: "Size"),
            ]
        }
        if stats.isVideo {
            return [
                KPITile(value: formatDuration(stats.durationSeconds),
                        label: "Duration"),
                KPITile(value: "\(stats.pixelWidth ?? 0)×\(stats.pixelHeight ?? 0)",
                        label: "Resolution"),
                KPITile(value: String(format: "%.1f fps", stats.fps ?? 0),
                        label: "FPS"),
                KPITile(value: stats.videoCodec ?? "—",
                        label: "Codec"),
            ]
        } else {
            return [
                KPITile(value: formatDuration(stats.durationSeconds),
                        label: "Duration"),
                KPITile(value: (stats.audioSampleRate ?? 0) > 0
                        ? String(format: "%.1f kHz", (stats.audioSampleRate ?? 0) / 1000)
                        : "—",
                        label: "Sample rate"),
                KPITile(value: stats.audioBitDepth.map { "\($0)-bit" } ?? "—",
                        label: "Bit depth"),
                KPITile(value: stats.audioCodec ?? "—",
                        label: "Codec"),
            ]
        }
    }

    private var badges: [SemanticBadgeModel] {
        guard let stats else { return [] }
        var out: [SemanticBadgeModel] = []
        if stats.hasHDR { out.append(.init(text: "HDR", style: .info, icon: "sun.max")) }
        if stats.isProRes { out.append(.init(text: "ProRes", style: .info, icon: "film")) }
        if stats.hasSubtitles { out.append(.init(text: "Subtitles", style: .info, icon: "captions.bubble")) }
        if stats.hasCoverArt { out.append(.init(text: "Cover art", style: .info, icon: "photo")) }
        if !stats.isVideo, !stats.tags.isEmpty {
            if let bitrate = stats.audioBitDepth, bitrate >= 16 {
                out.append(.init(text: "Lossless", style: .success, icon: "waveform"))
            }
        }
        return out
    }

    private var tagRows: [(String, String)] {
        guard let stats else { return [] }
        return [
            ("title",  stats.tags["title"]),
            ("artist", stats.tags["artist"]),
            ("album",  stats.tags["albumName"] ?? stats.tags["album"]),
            ("year",   stats.tags["creationDate"]),
        ].compactMap { label, value -> (String, String)? in
            guard let v = value, !v.isEmpty else { return nil }
            return (label, v)
        }
    }

    private var tagsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TAGS")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(tagRows, id: \.0) { pair in
                    HStack(alignment: .firstTextBaseline) {
                        Text(pair.0.uppercased())
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

    // MARK: - Loading

    @MainActor
    private func load() async {
        resolvedURL = nil
        stats = nil
        thumbnails = []
        coverArt = nil
        waveform = []
        player = nil
        loadError = nil
        cleanupTemp()

        let resolved = await resolveURL()
        guard let resolved else {
            loadError = "The data source didn't provide a URL or bytes."
            return
        }
        self.resolvedURL = resolved

        let asset = AVURLAsset(url: resolved)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)

        // Kick async metadata + frame/waveform pulls in parallel.
        async let s = MediaAnalyzer.stats(at: resolved)
        if item.kind == .video {
            async let t = MediaAnalyzer.videoThumbnails(at: resolved, count: 8)
            self.stats = await s
            self.thumbnails = await t
        } else {
            async let c = MediaAnalyzer.coverArt(at: resolved)
            async let w = MediaAnalyzer.waveformSamples(at: resolved, count: 800)
            self.stats = await s
            self.coverArt = await c
            self.waveform = await w
        }
    }

    @MainActor
    private func resolveURL() async -> URL? {
        if let url { return url }
        guard let data else { return nil }
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("previewkit-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let destination = tmpDir.appendingPathComponent(item.displayName)
        do {
            try data.write(to: destination, options: .atomic)
            self.ownedTempURL = destination
            return destination
        } catch {
            loadError = "\(error)"
            return nil
        }
    }

    private func cleanupTemp() {
        if let ownedTempURL {
            try? FileManager.default.removeItem(at: ownedTempURL)
            self.ownedTempURL = nil
        }
        player?.pause()
    }

    // MARK: - Formatting

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
