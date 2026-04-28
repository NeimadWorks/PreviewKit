// Tests for `ImageAnalyzer` and `SRGBColor`. Build a synthetic PNG
// in-process so the tests are self-contained — no fixture files.

import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PreviewKit

final class ImageAnalyzerTests: XCTestCase {

    // MARK: - Synthetic PNG builder

    private func makePNG(width: Int, height: Int,
                         fill: (red: UInt8, green: UInt8, blue: UInt8)) -> Data {
        let bytesPerPixel = 4
        var raw = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        for i in stride(from: 0, to: raw.count, by: 4) {
            raw[i + 0] = fill.red
            raw[i + 1] = fill.green
            raw[i + 2] = fill.blue
            raw[i + 3] = 255
        }
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(
            data: &raw, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * bytesPerPixel,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = ctx.makeImage()!
        let mutableData = NSMutableData()
        let dest = CGImageDestinationCreateWithData(
            mutableData, UTType.png.identifier as CFString, 1, nil
        )!
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
        return mutableData as Data
    }

    // MARK: - Stats

    func testStatsOnRedSquare() {
        let data = makePNG(width: 32, height: 32, fill: (255, 0, 0))
        guard let stats = ImageAnalyzer.stats(from: data) else {
            return XCTFail("Should parse")
        }
        XCTAssertEqual(stats.pixelWidth, 32)
        XCTAssertEqual(stats.pixelHeight, 32)
        XCTAssertGreaterThan(stats.bitDepth, 0)
        XCTAssertNil(stats.gps)
    }

    // MARK: - Histogram

    func testHistogramMaxBucketReflectsChannel() {
        let data = makePNG(width: 16, height: 16, fill: (255, 0, 0))
        guard let h = ImageAnalyzer.histogram(from: data) else {
            return XCTFail("Histogram should compute")
        }
        XCTAssertGreaterThan(h.red[255], 0)
        XCTAssertGreaterThan(h.green[0], 0)
        XCTAssertGreaterThan(h.blue[0], 0)
    }

    // MARK: - Dominant colors

    func testDominantColorsReturnsRequestedCount() {
        let data = makePNG(width: 16, height: 16, fill: (100, 150, 200))
        let colors = ImageAnalyzer.dominantColors(from: data, k: 5)
        XCTAssertEqual(colors.count, 5)
    }

    func testDominantColorsDeterministicForSameImage() {
        let data = makePNG(width: 16, height: 16, fill: (50, 100, 150))
        let first = ImageAnalyzer.dominantColors(from: data, k: 3).map(\.hexTriplet)
        let second = ImageAnalyzer.dominantColors(from: data, k: 3).map(\.hexTriplet)
        XCTAssertEqual(first, second)
    }

    // MARK: - SRGBColor

    func testSRGBHexTripletRoundTrips() {
        XCTAssertEqual(SRGBColor(r: 1, g: 0, b: 0).hexTriplet,  "#FF0000")
        XCTAssertEqual(SRGBColor(r: 0, g: 1, b: 0).hexTriplet,  "#00FF00")
        XCTAssertEqual(SRGBColor(r: 0.5, g: 0.5, b: 0.5).hexTriplet, "#808080")
    }
}
