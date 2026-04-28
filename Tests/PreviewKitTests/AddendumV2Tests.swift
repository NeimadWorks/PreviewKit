// Tests for the addendum v2 renderers: Patch, Icon, MobileProvision, GPG.
// Coverage focuses on the analyzer layer — each renderer's view tree is
// exercised by XCTest-only indirectly (compile-time via the registry).

import XCTest
import AppKit
@testable import PreviewKit

final class PatchAnalyzerTests: XCTestCase {

    func testClassifyKnownPrefixes() {
        XCTAssertEqual(PatchAnalyzer.classify("+new line"), .addition)
        XCTAssertEqual(PatchAnalyzer.classify("-old line"), .deletion)
        XCTAssertEqual(PatchAnalyzer.classify(" context"),  .context)
        XCTAssertEqual(PatchAnalyzer.classify("@@ -1,3 +1,4 @@ hunk"), .hunkHeader)
        XCTAssertEqual(PatchAnalyzer.classify("--- a/x"),   .fileHeader)
        XCTAssertEqual(PatchAnalyzer.classify("+++ b/x"),   .fileHeader)
        XCTAssertEqual(PatchAnalyzer.classify("diff --git a/x b/x"), .meta)
        XCTAssertEqual(PatchAnalyzer.classify("index abc..def 100644"), .meta)
        XCTAssertEqual(PatchAnalyzer.classify("rename from a"), .meta)
        XCTAssertEqual(PatchAnalyzer.classify("new file mode 100644"), .meta)
        XCTAssertEqual(PatchAnalyzer.classify("Binary files a and b differ"), .meta)
    }

    func testParseCountsAdditionsAndDeletions() {
        let patch = """
        diff --git a/foo.swift b/foo.swift
        index 123..456 100644
        --- a/foo.swift
        +++ b/foo.swift
        @@ -1,3 +1,4 @@
         line a
        -line b
        +line B
        +line C
         line d
        """
        let s = PatchAnalyzer.parse(patch)
        XCTAssertEqual(s.filesChanged, 1)
        XCTAssertEqual(s.additions, 2)
        XCTAssertEqual(s.deletions, 1)
        XCTAssertEqual(s.hunks, 1)
        XCTAssertEqual(s.files, ["foo.swift"])
    }

    func testParseDetectsRenameAndNewFile() {
        let patch = """
        diff --git a/old.txt b/new.txt
        similarity index 100%
        rename from old.txt
        rename to new.txt
        new file mode 100644
        """
        let s = PatchAnalyzer.parse(patch)
        XCTAssertTrue(s.hasRename)
        XCTAssertTrue(s.hasNewFile)
    }

    func testParseDetectsBinaryPatch() {
        let s = PatchAnalyzer.parse("GIT binary patch\nliteral 0\nHcmV?d00001")
        XCTAssertTrue(s.hasBinaryPatch)
    }

    func testParseHandlesMultipleFiles() {
        let patch = """
        diff --git a/a b/a
        --- a/a
        +++ b/a
        @@ -1 +1 @@
        -x
        +y
        diff --git a/b b/b
        --- a/b
        +++ b/b
        @@ -1 +1 @@
        -p
        +q
        """
        let s = PatchAnalyzer.parse(patch)
        XCTAssertEqual(s.filesChanged, 2)
        XCTAssertEqual(s.hunks, 2)
        XCTAssertEqual(s.additions, 2)
        XCTAssertEqual(s.deletions, 2)
    }
}

final class IconAnalyzerTests: XCTestCase {

    /// Build an in-memory multi-size NSImage and round-trip it through
    /// IconAnalyzer by re-encoding as TIFF (NSImage accepts TIFF data
    /// with multiple reps the same way it accepts ICNS).
    func testSpecimenEnumeratesRepresentations() throws {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.addRepresentation(
            NSBitmapImageRep(bitmapDataPlanes: nil,
                             pixelsWide: 64, pixelsHigh: 64,
                             bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
        )
        image.addRepresentation(
            NSBitmapImageRep(bitmapDataPlanes: nil,
                             pixelsWide: 128, pixelsHigh: 128,
                             bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
        )
        let data = try XCTUnwrap(image.tiffRepresentation)
        let spec = try XCTUnwrap(IconAnalyzer.specimen(data: data))
        XCTAssertEqual(spec.representations.count, 2)
        XCTAssertEqual(spec.largestPixelDimension, 128)
        XCTAssertTrue(spec.hasSlot(64))
        XCTAssertTrue(spec.hasSlot(128))
        XCTAssertFalse(spec.hasSlot(1024))
        XCTAssertFalse(spec.hasAppStoreSize)
    }

    func testSpecimenReturnsNilForGarbage() {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        XCTAssertNil(IconAnalyzer.specimen(data: data))
    }

    func testStandardSlotRoster() {
        XCTAssertEqual(IconSpecimen.standardSlots, [16, 32, 64, 128, 256, 512, 1024])
    }
}

final class MobileProvisionAnalyzerTests: XCTestCase {

    func testParseClassifiesAppStoreWhenNoDevices() {
        let plist: [String: Any] = [
            "Name": "Dist · AppStore",
            "TeamName": "NeimadWorks",
            "TeamIdentifier": ["A1B2C3D4E5"],
            "Entitlements": [
                "application-identifier": "A1B2C3D4E5.fr.neimad.cairn",
                "get-task-allow": false,
            ] as [String: Any],
            "ProvisionedDevices": [] as [String],
            "ExpirationDate": Date().addingTimeInterval(60 * 24 * 3600),
            "UUID": "FAKE-UUID",
        ]
        let p = MobileProvisionAnalyzer.parse(plist: plist)
        XCTAssertEqual(p.profileType, .appStore)
        XCTAssertEqual(p.bundleIdentifier, "fr.neimad.cairn")
        XCTAssertEqual(p.teamIdentifier, "A1B2C3D4E5")
        XCTAssertEqual(p.name, "Dist · AppStore")
        XCTAssertGreaterThan(p.daysUntilExpiry ?? 0, 50)
    }

    func testParseClassifiesDevelopmentWhenGetTaskAllow() {
        let plist: [String: Any] = [
            "Name": "Dev",
            "TeamIdentifier": ["T"],
            "Entitlements": [
                "application-identifier": "T.x",
                "get-task-allow": true,
            ] as [String: Any],
            "ProvisionedDevices": ["UDID-1", "UDID-2"],
        ]
        XCTAssertEqual(MobileProvisionAnalyzer.parse(plist: plist).profileType, .development)
    }

    func testParseClassifiesEnterpriseWhenProvisionsAllDevices() {
        let plist: [String: Any] = [
            "Name": "Ent",
            "TeamIdentifier": ["T"],
            "Entitlements": ["application-identifier": "T.x"] as [String: Any],
            "ProvisionsAllDevices": true,
        ]
        XCTAssertEqual(MobileProvisionAnalyzer.parse(plist: plist).profileType, .enterprise)
    }

    func testParseClassifiesAdHocWhenDevicesButNoGetTaskAllow() {
        let plist: [String: Any] = [
            "Name": "AdHoc",
            "TeamIdentifier": ["T"],
            "Entitlements": [
                "application-identifier": "T.x",
                "get-task-allow": false,
            ] as [String: Any],
            "ProvisionedDevices": ["A", "B", "C"],
        ]
        XCTAssertEqual(MobileProvisionAnalyzer.parse(plist: plist).profileType, .adHoc)
    }

    func testExtractPlistDataFindsMarkers() {
        // Synthetic: some CMS-looking prefix + XML plist + trailing junk.
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>Name</key><string>X</string></dict></plist>
        """
        var buf = Data([0x30, 0x82, 0x01, 0x00, 0x02, 0x01, 0x01])   // fake CMS bytes
        buf.append(xml.data(using: .utf8)!)
        buf.append(Data([0x00, 0x00, 0x00]))                          // trailing junk
        let extracted = MobileProvisionAnalyzer.extractPlistData(from: buf)
        XCTAssertNotNil(extracted)
        let s = String(data: extracted!, encoding: .utf8) ?? ""
        XCTAssertTrue(s.hasPrefix("<?xml"))
        XCTAssertTrue(s.hasSuffix("</plist>"))
    }

    func testEntitlementsSortedAlphabetically() {
        let plist: [String: Any] = [
            "Name": "x",
            "TeamIdentifier": ["T"],
            "Entitlements": [
                "z-key": true,
                "a-key": "val",
                "m-key": 1,
            ] as [String: Any],
        ]
        let keys = MobileProvisionAnalyzer.parse(plist: plist).entitlements.map(\.key)
        XCTAssertEqual(keys, ["a-key", "m-key", "z-key"])
    }
}

final class GPGAnalyzerTests: XCTestCase {

    func testParseSignatureBlock() {
        let source = """
        -----BEGIN PGP SIGNATURE-----
        Version: GnuPG v2.4.0
        Comment: https://gnupg.org

        iHUEABYKAB0WIQTfakesigfakesigfakesigfakesigfakesigfakeFAmY3abc=
        =xyz1
        -----END PGP SIGNATURE-----
        """
        let s = GPGAnalyzer.parse(data: source.data(using: .utf8)!)
        XCTAssertTrue(s.isArmored)
        XCTAssertEqual(s.blockType, .signature)
        XCTAssertEqual(s.version, "GnuPG v2.4.0")
        XCTAssertEqual(s.comment, "https://gnupg.org")
        XCTAssertGreaterThan(s.bodyByteCount, 0)
    }

    func testParseMessageBlock() {
        let source = """
        -----BEGIN PGP MESSAGE-----
        Version: OpenPGP.js

        wVgDEi4iXKKKKKKKSSSSS==
        -----END PGP MESSAGE-----
        """
        let s = GPGAnalyzer.parse(data: source.data(using: .utf8)!)
        XCTAssertEqual(s.blockType, .message)
    }

    func testParsePublicKeyBlock() {
        let source = """
        -----BEGIN PGP PUBLIC KEY BLOCK-----

        mQINBGJabcdefg
        -----END PGP PUBLIC KEY BLOCK-----
        """
        let s = GPGAnalyzer.parse(data: source.data(using: .utf8)!)
        XCTAssertEqual(s.blockType, .publicKey)
    }

    func testParseBinaryReturnsUnarmored() {
        let data = Data([0xC3, 0x0D, 0x04, 0x00, 0x01, 0x02, 0x03])  // plausible OpenPGP packet
        let s = GPGAnalyzer.parse(data: data)
        XCTAssertFalse(s.isArmored)
        XCTAssertEqual(s.blockType, .unknown)
    }

    func testExtractKeyIDRecognisesHexTokens() {
        XCTAssertEqual(GPGAnalyzer.extractKeyID("key 0xA1B2C3D4E5F60001 for"),
                       "0xA1B2C3D4E5F60001")
        XCTAssertEqual(GPGAnalyzer.extractKeyID("short DEADBEEF signed"),
                       "0xDEADBEEF")
        XCTAssertNil(GPGAnalyzer.extractKeyID("no hex here folks"))
        XCTAssertNil(GPGAnalyzer.extractKeyID("too short AB"))
    }
}

@MainActor
final class AddendumV2RegistryTests: XCTestCase {

    func testBootstrapRegistersAddendumRenderers() {
        let registry = RendererRegistry()
        PreviewKit.bootstrap(registry: registry)
        XCTAssertEqual(String(describing: type(of: registry.renderer(for: .patch))),
                       "PatchRenderer")
        XCTAssertEqual(String(describing: type(of: registry.renderer(for: .icns))),
                       "IconRenderer")
        XCTAssertEqual(String(describing: type(of: registry.renderer(for: .mobileProvision))),
                       "MobileProvisionRenderer")
        XCTAssertEqual(String(describing: type(of: registry.renderer(for: .gpgSignature))),
                       "GPGRenderer")
        XCTAssertEqual(String(describing: type(of: registry.renderer(for: .gpgMessage))),
                       "GPGRenderer")
    }

    func testInferExtensionMapsNewKinds() {
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "patch"), .patch)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "diff"), .patch)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "icns"), .icns)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "mobileprovision"), .mobileProvision)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "asc"), .gpgSignature)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "sig"), .gpgSignature)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "pgp"), .gpgSignature)
        XCTAssertEqual(ArtifactKind.infer(fromExtension: "gpg"), .gpgMessage)
    }
}
