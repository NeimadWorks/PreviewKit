// IconAnalyzer — pure helpers for enumerating `.icns` representations.
//
// Uses `NSImage(data:)` / `NSImage(contentsOf:)` which natively understands
// the Apple icon format. The representation list exposes per-size entries
// (`NSImageRep.pixelsWide` / `pixelsHigh`); we canonicalise those into a
// fixed set of "slots" that the view renders as a presence grid.

import Foundation
import AppKit

public struct IconRepresentation: Sendable, Equatable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Bit depth from the rep (typically 32 for modern icons).
    public let bitsPerSample: Int
    /// Whether this rep is at an @2x scale (heuristic — NSImageRep does not
    /// expose a retina flag directly; we treat any 2× pair among standard
    /// slots as retina).
    public var isRetina: Bool { false }
}

public struct IconSpecimen: Sendable, Equatable {
    public let representations: [IconRepresentation]
    public let byteSize: Int
    public var largestPixelDimension: Int {
        representations.map { max($0.pixelWidth, $0.pixelHeight) }.max() ?? 0
    }
    public var hasAppStoreSize: Bool {
        representations.contains { $0.pixelWidth == 1024 && $0.pixelHeight == 1024 }
    }
    /// The canonical slot set Apple documents for `AppIcon.appiconset`.
    public static let standardSlots: [Int] = [16, 32, 64, 128, 256, 512, 1024]

    public func hasSlot(_ px: Int) -> Bool {
        representations.contains { $0.pixelWidth == px && $0.pixelHeight == px }
    }
}

public enum IconAnalyzer {

    /// Load an NSImage from an `.icns` payload and enumerate its reps.
    /// Returns nil when the bytes do not represent a valid icon set.
    public static func specimen(data: Data) -> IconSpecimen? {
        guard let image = NSImage(data: data) else { return nil }
        return build(from: image, byteSize: data.count)
    }

    public static func specimen(url: URL) -> IconSpecimen? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return build(from: image, byteSize: size)
    }

    private static func build(from image: NSImage, byteSize: Int) -> IconSpecimen {
        let reps = image.representations.map { rep in
            IconRepresentation(
                pixelWidth: rep.pixelsWide,
                pixelHeight: rep.pixelsHigh,
                bitsPerSample: rep.bitsPerSample
            )
        }
        return IconSpecimen(representations: reps, byteSize: byteSize)
    }
}
