// swift-tools-version: 6.0
//
// FilamentSwift examples — the demo applications, as their own package.
//
// Keeping demos out of the library package (the parent directory) is the standard
// SwiftPM layout: `swift build` at the repository root builds and tests only the
// library, and the demos are free to add per-platform app dependencies.
//
//   swift build --package-path Examples
//   swift run   --package-path Examples AppKitDemo

import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let libraryRoot = packageRoot.deletingLastPathComponent()

// Mirror of the library's Swift settings: Swift 6, C++ interop against the same
// prebuilt Filament SDK. The library resolves that SDK itself; the demos need the same
// include path, honouring FILAMENT_DIR the same way.
let filamentDir: String = {
    if let env = ProcessInfo.processInfo.environment["FILAMENT_DIR"], !env.isEmpty {
        return env
    }
    let local = libraryRoot.appendingPathComponent(".filament")
    if FileManager.default.fileExists(atPath: local.appendingPathComponent("include/filament/Engine.h").path) {
        return local.path
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["python3", libraryRoot.appendingPathComponent("scripts/ensure_filament.py").path]
    try? proc.run()
    proc.waitUntilExit()
    return local.path
}()

let includeDir = URL(fileURLWithPath: filamentDir).appendingPathComponent("include").path

// NOTE: for a path dependency SwiftPM identifies the package by its *directory* name,
// not the `name:` in its manifest - so this is "filament-swift", not "FilamentSwift".
var dependencies: [Package.Dependency] = [.package(path: "..")]

let demoSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .interoperabilityMode(.Cxx),
    .unsafeFlags([
        "-I", includeDir,
        "-I", libraryRoot.appendingPathComponent("Sources/FilamentC/include").path,
    ]),
]

// The static archives are already pulled in by the Filament target; the demos only need
// the platform UI libraries.
let macOSLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("CoreGraphics"),
    .linkedFramework("QuartzCore"),
    .linkedFramework("Cocoa"),
]

var products: [Product] = []
var targets: [Target] = []

#if os(macOS)
products.append(contentsOf: [
    .executable(name: "AppKitDemo", targets: ["AppKitDemo"]),
])
targets.append(.executableTarget(
    name: "AppKitDemo",
    dependencies: [.product(name: "Filament", package: "filament-swift"),
                   .product(name: "FilamentAppKit", package: "filament-swift")],
    path: "Sources/AppKitDemo",
    swiftSettings: demoSwiftSettings,
    linkerSettings: macOSLinkerSettings
))
#elseif os(Windows)
products.append(contentsOf: [
    .executable(name: "Win32Demo", targets: ["Win32Demo"]),
])
targets.append(.executableTarget(
    name: "Win32Demo",
    dependencies: [.product(name: "Filament", package: "filament-swift"),
                   .product(name: "FilamentWin32", package: "filament-swift")],
    path: "Sources/Win32Demo",
    swiftSettings: demoSwiftSettings,
    linkerSettings: [.unsafeFlags(["user32.lib", "gdi32.lib", "ole32.lib", "shell32.lib", "comdlg32.lib"])]
))

// The WinUI 3 demo additionally needs the generated WinRT projections. They live in
// their own package because SwiftPM can only read sources inside its own package root,
// so they cannot be targets of this one. The dependency is only added once they have
// been generated on a Windows machine.
if FileManager.default.fileExists(
    atPath: packageRoot.appendingPathComponent("../WinUIProjections/Sources/WinUI").path
) {
    dependencies.append(.package(path: "../WinUIProjections"))
    products.append(.executable(name: "WinUI3Demo", targets: ["WinUI3Demo"]))
    targets.append(.executableTarget(
        name: "WinUI3Demo",
        dependencies: [
            .product(name: "Filament", package: "filament-swift"),
            .product(name: "FilamentWin32", package: "filament-swift"),
            .product(name: "CWinRT", package: "WinUIProjections"),
            .product(name: "WindowsFoundation", package: "WinUIProjections"),
            .product(name: "UWP", package: "WinUIProjections"),
            .product(name: "WinAppSDK", package: "WinUIProjections"),
            .product(name: "WinUI", package: "WinUIProjections"),
        ],
        path: "Sources/WinUI3Demo",
        swiftSettings: demoSwiftSettings,
        linkerSettings: [.unsafeFlags(["user32.lib", "gdi32.lib", "ole32.lib", "shell32.lib",
                                       "comdlg32.lib", "dwmapi.lib"])]
    ))
}
#elseif os(Linux)
products.append(contentsOf: [
    .executable(name: "GTK4Demo", targets: ["GTK4Demo"]),
])
targets.append(.executableTarget(
    name: "GTK4Demo",
    dependencies: [.product(name: "Filament", package: "filament-swift"),
                   .product(name: "FilamentGTK", package: "filament-swift")],
    path: "Sources/GTK4Demo",
    swiftSettings: demoSwiftSettings,
    linkerSettings: [
        .linkedLibrary("gtk-4"),
        .linkedLibrary("gdk-4"),
        .linkedLibrary("gio-2.0"),
        .linkedLibrary("gobject-2.0"),
        .linkedLibrary("glib-2.0"),
        .linkedLibrary("X11"),
        .linkedLibrary("pthread"),
        .linkedLibrary("dl"),
    ]
))
#endif

let package = Package(
    name: "FilamentSwiftExamples",
    platforms: [
        .macOS(.v13),
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)