// ImageAnalyzer — ImageIO + vImage helpers. Pure logic; off-main
// callers hop to an actor that owns the heavy lifting.

import Foundation
import ImageIO
import CoreGraphics
import AppKit
import Accelerate

public struct ImageStats: Sendable, Hashable {
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let dpi: Double
    public let colorSpace: String
    public let hasAlpha: Bool
    public let bitDepth: Int
    public let isHDR: Bool
    public let hasICCProfile: Bool
    public let exif: [String: String]
    public let gps: (latitude: Double, longitude: Double)?
    public let cameraModel: String?
    public let lensModel: String?
    public let focalLengthMM: Double?
    public let iso: Int?
    public let shutterSpeed: String?
    public let aperture: Double?
    public let colorTempKelvin: Int?
    public let hasXMPSidecar: Bool
    public let hasEmbeddedJPEG: Bool
    public let frameCount: Int

    public init(
        pixelWidth: Int, pixelHeight: Int, dpi: Double, colorSpace: String,
        hasAlpha: Bool, bitDepth: Int, isHDR: Bool, hasICCProfile: Bool,
        exif: [String: String], gps: (latitude: Double, longitude: Double)?,
        cameraModel: String?, lensModel: String?, focalLengthMM: Double?,
        iso: Int?, shutterSpeed: String?, aperture: Double?,
        colorTempKelvin: Int?, hasXMPSidecar: Bool, hasEmbeddedJPEG: Bool,
        frameCount: Int
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dpi = dpi
        self.colorSpace = colorSpace
        self.hasAlpha = hasAlpha
        self.bitDepth = bitDepth
        self.isHDR = isHDR
        self.hasICCProfile = hasICCProfile
        self.exif = exif
        self.gps = gps
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.focalLengthMM = focalLengthMM
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.colorTempKelvin = colorTempKelvin
        self.hasXMPSidecar = hasXMPSidecar
        self.hasEmbeddedJPEG = hasEmbeddedJPEG
        self.frameCount = frameCount
    }

    /// `(latitude, longitude)` tuple isn't automatically Hashable /
    /// Equatable, so conformances are hand-written below.
    public static func == (lhs: ImageStats, rhs: ImageStats) -> Bool {
        lhs.pixelWidth == rhs.pixelWidth
            && lhs.pixelHeight == rhs.pixelHeight
            && lhs.dpi == rhs.dpi
            && lhs.colorSpace == rhs.colorSpace
            && lhs.hasAlpha == rhs.hasAlpha
            && lhs.bitDepth == rhs.bitDepth
            && lhs.isHDR == rhs.isHDR
            && lhs.hasICCProfile == rhs.hasICCProfile
            && lhs.exif == rhs.exif
            && lhs.gps?.latitude == rhs.gps?.latitude
            && lhs.gps?.longitude == rhs.gps?.longitude
            && lhs.cameraModel == rhs.cameraModel
            && lhs.lensModel == rhs.lensModel
            && lhs.focalLengthMM == rhs.focalLengthMM
            && lhs.iso == rhs.iso
            && lhs.shutterSpeed == rhs.shutterSpeed
            && lhs.aperture == rhs.aperture
            && lhs.colorTempKelvin == rhs.colorTempKelvin
            && lhs.hasXMPSidecar == rhs.hasXMPSidecar
            && lhs.hasEmbeddedJPEG == rhs.hasEmbeddedJPEG
            && lhs.frameCount == rhs.frameCount
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(pixelWidth)
        hasher.combine(pixelHeight)
        hasher.combine(dpi)
        hasher.combine(colorSpace)
        hasher.combine(exif)
        hasher.combine(gps?.latitude)
        hasher.combine(gps?.longitude)
    }
}

public enum ImageAnalyzer {

    /// Extract static metadata from an image byte-blob. Runs synchronously;
    /// safe to call on main for small files, but the caller is expected
    /// to hop off-main for large RAWs.
    public static func stats(from data: Data, xmpSidecarExists: Bool = false) -> ImageStats? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let frameCount = CGImageSourceGetCount(source)
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }

        let width  = (props[kCGImagePropertyPixelWidth]  as? Int) ?? 0
        let height = (props[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let dpiX   = (props[kCGImagePropertyDPIWidth]  as? Double) ?? 72
        let dpi    = dpiX

        let colorModel = (props[kCGImagePropertyColorModel] as? String) ?? "RGB"
        let profileName = (props[kCGImagePropertyProfileName] as? String) ?? colorModel
        let hasAlpha   = (props[kCGImagePropertyHasAlpha]   as? Bool) ?? false
        let depth      = (props[kCGImagePropertyDepth]      as? Int) ?? 8
        let isHDR      = depth > 8

        let exifDict = (props[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        let gpsDict  = props[kCGImagePropertyGPSDictionary]   as? [CFString: Any]
        let tiffDict = props[kCGImagePropertyTIFFDictionary]  as? [CFString: Any]

        let exif: [String: String] = {
            var out: [String: String] = [:]
            for (k, v) in exifDict {
                let keyString = String(k as String)
                if let str = v as? String { out[keyString] = str }
                else if let n = v as? NSNumber { out[keyString] = n.stringValue }
            }
            return out
        }()

        let gps: (Double, Double)? = {
            guard let lat = gpsDict?[kCGImagePropertyGPSLatitude] as? Double,
                  let lon = gpsDict?[kCGImagePropertyGPSLongitude] as? Double,
                  let latRef = gpsDict?[kCGImagePropertyGPSLatitudeRef] as? String,
                  let lonRef = gpsDict?[kCGImagePropertyGPSLongitudeRef] as? String else {
                return nil
            }
            return (latRef == "S" ? -lat : lat, lonRef == "W" ? -lon : lon)
        }()

        let camera = (tiffDict?[kCGImagePropertyTIFFModel] as? String)
            ?? (tiffDict?[kCGImagePropertyTIFFMake] as? String)
        let lens = (exifDict[kCGImagePropertyExifLensModel] as? String)
            ?? (exifDict[kCGImagePropertyExifLensMake] as? String)
        let focalLength = exifDict[kCGImagePropertyExifFocalLength] as? Double
        let iso = (exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        let shutter = (exifDict[kCGImagePropertyExifExposureTime] as? Double).map { exposure in
            exposure >= 1 ? String(format: "%.1fs", exposure) : "1/\(Int((1 / exposure).rounded()))s"
        }
        let aperture = exifDict[kCGImagePropertyExifFNumber] as? Double
        let colorTemp = exifDict["WhiteBalanceKelvin" as CFString] as? Int
        let embedded = frameCount > 1

        return ImageStats(
            pixelWidth: width, pixelHeight: height, dpi: dpi,
            colorSpace: profileName, hasAlpha: hasAlpha, bitDepth: depth,
            isHDR: isHDR, hasICCProfile: profileName != colorModel,
            exif: exif, gps: gps, cameraModel: camera, lensModel: lens,
            focalLengthMM: focalLength, iso: iso,
            shutterSpeed: shutter, aperture: aperture,
            colorTempKelvin: colorTemp, hasXMPSidecar: xmpSidecarExists,
            hasEmbeddedJPEG: embedded, frameCount: frameCount
        )
    }

    // MARK: - Histogram

    /// Compute a 256-bucket histogram per channel (R, G, B) over the
    /// supplied image data by decoding to 8-bit RGBA and walking the
    /// buffer. Accelerate's vImage is available; for Session 4 the
    /// loop is explicit — CI stability wins over last-millisecond
    /// speed.
    public static func histogram(from data: Data) -> RGBHistogram? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return histogram(from: image)
    }

    public static func histogram(from image: CGImage) -> RGBHistogram? {
        let width = image.width
        let height = image.height
        let scale = max(1, (width * height) / 300_000) // downsample ~300 kpx
        let w = max(32, width / scale)
        let h = max(32, height / scale)
        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &rgba, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var r = [Int](repeating: 0, count: 256)
        var g = [Int](repeating: 0, count: 256)
        var b = [Int](repeating: 0, count: 256)
        var i = 0
        let end = rgba.count
        while i < end {
            r[Int(rgba[i])] += 1
            g[Int(rgba[i + 1])] += 1
            b[Int(rgba[i + 2])] += 1
            i += 4
        }
        return RGBHistogram(red: r, green: g, blue: b)
    }

    // MARK: - Dominant colors

    /// k-means-lite. Downsample to 64×64, cluster into `k` colours
    /// with 8 iterations. Fast, deterministic enough for preview UI.
    public static func dominantColors(from data: Data, k: Int = 5) -> [SRGBColor] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        return dominantColors(from: image, k: k)
    }

    public static func dominantColors(from image: CGImage, k: Int = 5) -> [SRGBColor] {
        let side = 64
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &rgba, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))

        // Collect pixels.
        var pixels: [(Double, Double, Double)] = []
        pixels.reserveCapacity(side * side)
        var i = 0
        while i < rgba.count {
            let r = Double(rgba[i]) / 255
            let g = Double(rgba[i + 1]) / 255
            let b = Double(rgba[i + 2]) / 255
            pixels.append((r, g, b))
            i += 4
        }

        // Seed with k evenly-spaced samples. Deterministic → same
        // image → same colours.
        guard pixels.count >= k else { return pixels.map { SRGBColor(r: $0.0, g: $0.1, b: $0.2) } }
        var centroids: [(Double, Double, Double)] = []
        for j in 0..<k {
            let idx = (j * pixels.count) / k
            centroids.append(pixels[idx])
        }

        for _ in 0..<8 {
            var sums = [(Double, Double, Double, Int)](repeating: (0, 0, 0, 0), count: k)
            for p in pixels {
                var best = 0
                var bestD = Double.greatestFiniteMagnitude
                for (idx, c) in centroids.enumerated() {
                    let d = pow(p.0 - c.0, 2) + pow(p.1 - c.1, 2) + pow(p.2 - c.2, 2)
                    if d < bestD { bestD = d; best = idx }
                }
                sums[best].0 += p.0
                sums[best].1 += p.1
                sums[best].2 += p.2
                sums[best].3 += 1
            }
            for j in 0..<k where sums[j].3 > 0 {
                centroids[j] = (
                    sums[j].0 / Double(sums[j].3),
                    sums[j].1 / Double(sums[j].3),
                    sums[j].2 / Double(sums[j].3)
                )
            }
        }
        return centroids.map { SRGBColor(r: $0.0, g: $0.1, b: $0.2) }
    }
}

// MARK: - Supporting types

public struct RGBHistogram: Sendable, Hashable {
    public let red: [Int]
    public let green: [Int]
    public let blue: [Int]
    public init(red: [Int], green: [Int], blue: [Int]) {
        self.red = red; self.green = green; self.blue = blue
    }
    public var maxBucket: Int {
        let m1 = red.max() ?? 0
        let m2 = green.max() ?? 0
        let m3 = blue.max() ?? 0
        return max(m1, max(m2, m3))
    }
}

public struct SRGBColor: Sendable, Hashable {
    public let r: Double
    public let g: Double
    public let b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public var hexTriplet: String {
        String(format: "#%02X%02X%02X",
               Int((r * 255).rounded()),
               Int((g * 255).rounded()),
               Int((b * 255).rounded()))
    }
}
