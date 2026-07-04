// swift-tools-version:5.9
import PackageDescription

// SelkorinCam — a macOS test/lab tool for:
//   1. Receiving a phone camera stream and recording it (your own phone -> your own Mac).
//   2. Inventorying IP cameras on a network YOU own or are authorized to test.
//   3. Passively summarizing camera-related network traffic for that same network.
//
// Build:   swift build -c release
// Run:     swift run SelkorinCam
// Or open Package.swift in Xcode and run the SelkorinCam scheme.
//
// Requires macOS 13+ (SwiftUI lifecycle, Network framework, AVAssetWriter).

let package = Package(
    name: "SelkorinCam",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "SelkorinCam",
            path: "Sources/SelkorinCam"
        )
    ]
)
