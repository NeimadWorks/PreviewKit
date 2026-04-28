// MediaAnalyzer — AVFoundation-backed helpers for MediaRenderer.
// Frame extraction and PCM sampling run on detached tasks so the UI
// thread stays responsive even for 4K 60fps media.

import Foundation
import AVFoundation
import AppKit

public struct MediaStats: Sendable, Hashable {
    public let durationSeconds: Double
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let fps: Double?
    public let videoCodec: String?
    public let audioCodec: String?
    public let audioChannels: Int?
    public let audioSampleRate: Double?
    public let audioBitDepth: Int?
    public let hasHDR: Bool
    public let isProRes: Bool
    public let hasSubtitles: Bool
    public let hasCoverArt: Bool
    public let tags: [String: String]

    public init(
        durationSeconds: Double, pixelWidth: Int?, pixelHeight: Int?,
        fps: Double?, videoCodec: String?, audioCodec: String?,
        audioChannels: Int?, audioSampleRate: Double?, audioBitDepth: Int?,
        hasHDR: Bool, isProRes: Bool, hasSubtitles: Bool,
        hasCoverArt: Bool, tags: [String: String]
    ) {
        self.durationSeconds = durationSeconds
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fps = fps
        self.videoCodec = videoCodec
        self.audioCodec = audioCodec
        self.audioChannels = audioChannels
        self.audioSampleRate = audioSampleRate
        self.audioBitDepth = audioBitDepth
        self.hasHDR = hasHDR
        self.isProRes = isProRes
        self.hasSubtitles = hasSubtitles
        self.hasCoverArt = hasCoverArt
        self.tags = tags
    }

    public var isVideo: Bool { pixelWidth != nil && pixelHeight != nil }
}

public enum MediaAnalyzer {

    public static func stats(at url: URL) async -> MediaStats? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }

        let video = (try? await asset.loadTracks(withMediaType: .video))?.first
        let audio = (try? await asset.loadTracks(withMediaType: .audio))?.first
        let subtitle = (try? await asset.loadTracks(withMediaType: .subtitle)) ?? []

        var stats = MediaStats(
            durationSeconds: CMTimeGetSeconds(duration),
            pixelWidth: nil, pixelHeight: nil, fps: nil,
            videoCodec: nil, audioCodec: nil,
            audioChannels: nil, audioSampleRate: nil, audioBitDepth: nil,
            hasHDR: false, isProRes: false, hasSubtitles: !subtitle.isEmpty,
            hasCoverArt: false, tags: [:]
        )

        if let track = video {
            let size = (try? await track.load(.naturalSize)) ?? .zero
            let fps = Double((try? await track.load(.nominalFrameRate)) ?? 0)
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            let codec = descriptions.first.map { fourCCString(CMFormatDescriptionGetMediaSubType($0)) }
            let isProRes = codec?.hasPrefix("ap") == true
            let hdr = (try? await track.load(.hasAudioSampleDependencies)) == false
            stats = MediaStats(
                durationSeconds: stats.durationSeconds,
                pixelWidth: Int(size.width),
                pixelHeight: Int(size.height),
                fps: fps,
                videoCodec: codec,
                audioCodec: stats.audioCodec,
                audioChannels: stats.audioChannels,
                audioSampleRate: stats.audioSampleRate,
                audioBitDepth: stats.audioBitDepth,
                hasHDR: hdr,
                isProRes: isProRes,
                hasSubtitles: stats.hasSubtitles,
                hasCoverArt: stats.hasCoverArt,
                tags: stats.tags
            )
        }

        if let track = audio {
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            let codec = descriptions.first.map { fourCCString(CMFormatDescriptionGetMediaSubType($0)) }
            var sampleRate: Double?
            var channels: Int?
            var bitDepth: Int?
            if let desc = descriptions.first,
               let basic = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                sampleRate = basic.pointee.mSampleRate
                channels = Int(basic.pointee.mChannelsPerFrame)
                bitDepth = Int(basic.pointee.mBitsPerChannel)
            }
            stats = MediaStats(
                durationSeconds: stats.durationSeconds,
                pixelWidth: stats.pixelWidth,
                pixelHeight: stats.pixelHeight,
                fps: stats.fps,
                videoCodec: stats.videoCodec,
                audioCodec: codec,
                audioChannels: channels,
                audioSampleRate: sampleRate,
                audioBitDepth: bitDepth,
                hasHDR: stats.hasHDR,
                isProRes: stats.isProRes,
                hasSubtitles: stats.hasSubtitles,
                hasCoverArt: stats.hasCoverArt,
                tags: stats.tags
            )
        }

        let metadata = (try? await asset.load(.metadata)) ?? []
        let (tags, hasCover) = await extractTags(metadata)
        return MediaStats(
            durationSeconds: stats.durationSeconds,
            pixelWidth: stats.pixelWidth,
            pixelHeight: stats.pixelHeight,
            fps: stats.fps,
            videoCodec: stats.videoCodec,
            audioCodec: stats.audioCodec,
            audioChannels: stats.audioChannels,
            audioSampleRate: stats.audioSampleRate,
            audioBitDepth: stats.audioBitDepth,
            hasHDR: stats.hasHDR,
            isProRes: stats.isProRes,
            hasSubtitles: stats.hasSubtitles,
            hasCoverArt: hasCover,
            tags: tags
        )
    }

    public static func videoThumbnails(at url: URL, count: Int = 8,
                                       size: CGSize = .init(width: 96, height: 54)) async -> [NSImage] {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        guard let duration = try? await asset.load(.duration) else { return [] }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0, count > 0 else { return [] }
        var images: [NSImage] = []
        for i in 0..<count {
            let t = CMTime(seconds: seconds * (Double(i) + 0.5) / Double(count), preferredTimescale: 600)
            if let cg = try? await imageAtTime(generator, time: t) {
                images.append(NSImage(cgImage: cg, size: size))
            }
        }
        return images
    }

    public static func coverArt(at url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        let md = (try? await asset.load(.commonMetadata)) ?? []
        for item in md where item.commonKey == .commonKeyArtwork {
            if let data = try? await item.load(.dataValue),
               let image = NSImage(data: data) {
                return image
            }
        }
        return nil
    }

    public static func waveformSamples(at url: URL, count: Int = 800) async -> [Float] {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return []
        }
        guard let reader = try? AVAssetReader(asset: asset) else { return [] }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        )
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { return [] }

        var samples = [Float](repeating: 0, count: count)
        var buckets = [Int](repeating: 0, count: count)
        var totalSampleCount: Int64 = 0

        let duration = (try? await asset.load(.duration)) ?? .zero
        let totalSeconds = CMTimeGetSeconds(duration)
        let expectedRate = (try? await track.load(.naturalTimeScale)).map { Double($0) } ?? 44_100
        let expectedTotal = Int64(totalSeconds * expectedRate)
        guard expectedTotal > 0 else { return [] }

        while let buffer = output.copyNextSampleBuffer() {
            if let block = CMSampleBufferGetDataBuffer(buffer) {
                let length = CMBlockBufferGetDataLength(block)
                var data = Data(count: length)
                data.withUnsafeMutableBytes { raw in
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length,
                                                   destination: raw.baseAddress!)
                }
                data.withUnsafeBytes { raw in
                    let ptr = raw.bindMemory(to: Int16.self)
                    let n = ptr.count
                    for i in 0..<n {
                        let bucket = Int(Double(totalSampleCount + Int64(i))
                                         / Double(expectedTotal) * Double(count))
                        let clamped = min(count - 1, max(0, bucket))
                        let amp = abs(Float(ptr[i])) / 32_768
                        if amp > samples[clamped] { samples[clamped] = amp }
                        buckets[clamped] += 1
                    }
                    totalSampleCount += Int64(n)
                }
            }
        }
        return samples
    }

    // MARK: - Helpers

    private static func imageAtTime(_ generator: AVAssetImageGenerator, time: CMTime) async throws -> CGImage {
        try await withCheckedThrowingContinuation { cont in
            generator.generateCGImageAsynchronously(for: time) { cg, _, err in
                if let cg { cont.resume(returning: cg) }
                else if let err { cont.resume(throwing: err) }
                else { cont.resume(throwing: NSError(domain: "MediaAnalyzer", code: -1)) }
            }
        }
    }

    private static func extractTags(_ md: [AVMetadataItem]) async -> (tags: [String: String], hasCover: Bool) {
        var tags: [String: String] = [:]
        var hasCover = false
        for item in md {
            if item.commonKey == .commonKeyArtwork { hasCover = true; continue }
            guard let key = item.commonKey?.rawValue else { continue }
            if let str = try? await item.load(.stringValue) {
                tags[key] = str
            } else if let num = try? await item.load(.numberValue) {
                tags[key] = num.stringValue
            }
        }
        return (tags, hasCover)
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8)  & 0xFF),
            UInt8(code         & 0xFF),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "?"
    }
}
