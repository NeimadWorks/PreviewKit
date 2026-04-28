// swift-tools-version: 6.0
//
// PreviewKit — format-agnostic file-preview and inspection module.
//
// Standalone Swift package. Zero external dependencies. Two consumers
// today (Cairn and Canopy); designed so adding a third is just another
// `.package(path:)` line. The single Cairn-aware type is `CairnMeta`,
// always optional, so non-Cairn hosts pass nil.

import PackageDescription

let package = Package(
    name: "PreviewKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PreviewKit", targets: ["PreviewKit"])
    ],
    targets: [
        .target(
            name: "PreviewKit",
            dependencies: [],
            path: "Sources/PreviewKit"
        ),
        .testTarget(
            name: "PreviewKitTests",
            dependencies: ["PreviewKit"],
            path: "Tests/PreviewKitTests"
        )
    ]
)
