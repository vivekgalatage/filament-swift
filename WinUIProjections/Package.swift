// swift-tools-version: 6.0
//
// Generated WinRT projections for the WinUI 3 demo.
//
// Run `python3 WinUIProjections/scripts/generate_winui_projection.py` (on Windows) to
// produce Sources/{CWinRT,WindowsFoundation,UWP,WinAppSDK,WinUI}. Until then this
// package only carries `WinRTVersion`, so the manifest always resolves and the rest of
// the repository builds on any platform.
//
// This is a separate package on purpose: SwiftPM can only read sources inside its own
// package root, so the generated code has to be a target of *some* package. Making it its
// own also keeps machine-generated files out of the library's Sources/ directory, where
// they would sit indistinguishable from hand-written targets.
//
// See README.md.

import Foundation
import PackageDescription

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

func generatedModuleExists(_ name: String) -> Bool {
    FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/\(name)").path)
}

let projectionsPresent = ["CWinRT", "WindowsFoundation", "UWP", "WinAppSDK", "WinUI"]
    .allSatisfy(generatedModuleExists)

// Generated WinRT bindings are not concurrency-annotated: they build in Swift 5 language
// mode, and consumers import them with `@preconcurrency` from Swift 6 targets.
let projectionSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v5)]

var products: [Product] = [
    .library(name: "WinRTVersion", targets: ["WinRTVersion"]),
]

var targets: [Target] = [
    .target(
        name: "WinRTVersion",
        path: "Sources/WinRTVersion",
        swiftSettings: [.swiftLanguageMode(.v6)]
    ),
]

if projectionsPresent {
    targets.append(contentsOf: [
        .target(name: "CWinRT", path: "Sources/CWinRT", swiftSettings: projectionSwiftSettings),
        .target(name: "WindowsFoundation", dependencies: ["CWinRT"],
                path: "Sources/WindowsFoundation", swiftSettings: projectionSwiftSettings),
        .target(name: "UWP", dependencies: ["CWinRT", "WindowsFoundation"],
                path: "Sources/UWP", swiftSettings: projectionSwiftSettings),
        .target(name: "WinAppSDK", dependencies: ["CWinRT", "WindowsFoundation", "UWP"],
                path: "Sources/WinAppSDK", swiftSettings: projectionSwiftSettings),
        .target(name: "WinUI", dependencies: ["CWinRT", "WindowsFoundation", "UWP", "WinAppSDK"],
                path: "Sources/WinUI", swiftSettings: projectionSwiftSettings),
    ])
    products.append(contentsOf: [
        .library(name: "CWinRT", targets: ["CWinRT"]),
        .library(name: "WindowsFoundation", targets: ["WindowsFoundation"]),
        .library(name: "UWP", targets: ["UWP"]),
        .library(name: "WinAppSDK", targets: ["WinAppSDK"]),
        .library(name: "WinUI", targets: ["WinUI"]),
    ])
}

let package = Package(
    name: "WinUIProjections",
    products: products,
    targets: targets
)