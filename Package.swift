// swift-tools-version: 6.0
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

// Resolve or ensure .filament cache is populated
let filamentDir: String = {
    if let env = ProcessInfo.processInfo.environment["FILAMENT_DIR"], !env.isEmpty {
        return env
    }
    let local = packageRoot.appendingPathComponent(".filament")
    if FileManager.default.fileExists(atPath: local.appendingPathComponent("include/filament/Engine.h").path) {
        return local.path
    }
    // Fetch if not present
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["python3", packageRoot.appendingPathComponent("scripts/ensure_filament.py").path]
    try? proc.run()
    proc.waitUntilExit()
    return local.path
}()

let includeDir = URL(fileURLWithPath: filamentDir).appendingPathComponent("include").path
let libDir: String = {
    #if os(macOS)
    return URL(fileURLWithPath: filamentDir).appendingPathComponent("lib/arm64").path
    #elseif os(Windows)
    return URL(fileURLWithPath: filamentDir).appendingPathComponent("lib/x86_64").path
    #else
    return URL(fileURLWithPath: filamentDir).appendingPathComponent("lib/x86_64").path
    #endif
}()

let filamentStaticLibs: [String] = [
    "libfilament.a",
    "libbackend.a",
    "libbluevk.a",
    "libbluegl.a",
    "libfilabridge.a",
    "libfilaflat.a",
    "libutils.a",
    "libgeometry.a",
    "libsmol-v.a",
    "libibl.a",
    "libgltfio.a",
    "libgltfio_core.a",
    "libdracodec.a",
    "libbasis_transcoder.a",
    "libmeshoptimizer.a",
    "libuberarchive.a",
    "libuberzlib.a",
    "libzstd.a",
    "libstb.a",
    "libktxreader.a",
].map { "\(libDir)/\($0)" }

let commonLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
    .unsafeFlags(filamentStaticLibs),
    .linkedFramework("Metal"),
    .linkedFramework("MetalKit"),
    .linkedFramework("CoreGraphics"),
    .linkedFramework("QuartzCore"),
    .linkedFramework("Cocoa"),
]

let package = Package(
    name: "FilamentSwift",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Filament",
            targets: ["Filament"]
        ),
    ],
    targets: [
        .target(
            name: "FilamentC",
            path: "Sources/FilamentC",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-I", includeDir, "-std=c++17"]),
            ]
        ),
        .target(
            name: "Filament",
            dependencies: ["FilamentC"],
            path: "Sources/Filament",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-I", includeDir,
                    "-I", URL(fileURLWithPath: packageRoot.path).appendingPathComponent("Sources/FilamentC/include").path,
                ]),
            ],
            linkerSettings: commonLinkerSettings
        ),
        .testTarget(
            name: "FilamentTests",
            dependencies: ["Filament"],
            path: "Tests/FilamentTests",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .interoperabilityMode(.Cxx),
                .unsafeFlags([
                    "-I", includeDir,
                    "-I", URL(fileURLWithPath: packageRoot.path).appendingPathComponent("Sources/FilamentC/include").path,
                ]),
            ],
            linkerSettings: commonLinkerSettings
        ),
    ],
    cxxLanguageStandard: .cxx17
)
