// swift-tools-version: 6.0
//
// FilamentSwift — the library package.
//
//   Sources/Filament        core: engine, camera, lights, PBR controls, glTF loader
//   Sources/FilamentC       C++ bridge (public C++ interop surface)
//   Sources/FilamentAppKit   macOS AppKit/Metal host view
//   Sources/FilamentGTK      Linux GTK 4 host view
//   Sources/FilamentWin32    Windows HWND host view (Win32 *and* WinUI 3 demos)
//
// Demos live in Examples/ as their own package, so this package stays free of
// executable targets and platform app dependencies. See Examples/Package.swift.

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
    do {
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let message = "[FilamentSwift] warning: ensure_filament.py exited with status "
                + "\(proc.terminationStatus); assuming \(local.path) is usable.\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    } catch {
        let message = "[FilamentSwift] warning: could not run scripts/ensure_filament.py (\(error)); "
            + "set FILAMENT_DIR to point at a prebuilt Filament SDK.\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
    return local.path
}()

let includeDir = URL(fileURLWithPath: filamentDir).appendingPathComponent("include").path

/// Root of the prebuilt Filament libraries.
///
/// These archives do NOT agree across platforms:
///   * macOS   - `lib/<name>.a` under `lib/arm64` or `lib/x86_64`
///   * Linux   - `lib/<name>.a` under `lib/x86_64`
///   * Windows - `lib/<name>.lib` (MSVC import libraries, **no `.a` anywhere**) under
///               `lib/x86_64/<mt|mtd>`. `md`/`mdd` are the DLL flavours and cannot be
///               statically linked.
/// `gltfio_core` exists only in the macOS/Linux archives.
let libDir: String = {
    let root = URL(fileURLWithPath: filamentDir)
    #if os(macOS)
    #if arch(arm64)
    return root.appendingPathComponent("lib/arm64").path
    #else
    return root.appendingPathComponent("lib/x86_64").path
    #endif
    #elseif os(Windows)
    // mt = multi-threaded static (mtd = static debug).
    return root.appendingPathComponent("lib/x86_64/mt").path
    #else
    return root.appendingPathComponent("lib/x86_64").path
    #endif
}()

#if os(Windows)
let libExt = "lib"
let filamentLibraryNames = [
    "filament", "backend", "bluevk", "bluegl", "filabridge", "filaflat",
    "utils", "geometry", "smol-v", "ibl", "gltfio", "dracodec",
    "basis_transcoder", "meshoptimizer", "uberarchive", "uberzlib",
    "zstd", "stb", "ktxreader",
]
#else
let libExt = "a"
let filamentLibraryNames = [
    "filament", "backend", "bluevk", "bluegl", "filabridge", "filaflat",
    "utils", "geometry", "smol-v", "ibl", "gltfio", "gltfio_core", "dracodec",
    "basis_transcoder", "meshoptimizer", "uberarchive", "uberzlib",
    "zstd", "stb", "ktxreader",
]
#endif

let filamentStaticLibs: [String] = filamentLibraryNames.map { "\(libDir)/lib\($0).\(libExt)" }

// Core Filament targets only need the C++ runtime and the static libraries. Platform
// frameworks/UI libraries belong to the platform host-view targets: putting them here
// breaks linking on the other platforms.
let filamentLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
    .unsafeFlags(filamentStaticLibs),
]

let filamentSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .interoperabilityMode(.Cxx),
    .unsafeFlags([
        "-I", includeDir,
        "-I", URL(fileURLWithPath: packageRoot.path).appendingPathComponent("Sources/FilamentC/include").path,
    ]),
]

var products: [Product] = [
    .library(name: "Filament", targets: ["Filament"]),
]

var targets: [Target] = [
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
        swiftSettings: filamentSwiftSettings,
        linkerSettings: filamentLinkerSettings
    ),
    .testTarget(
        name: "FilamentTests",
        dependencies: ["Filament"],
        path: "Tests/FilamentTests",
        swiftSettings: filamentSwiftSettings,
        linkerSettings: filamentLinkerSettings
    ),
]

#if os(macOS)
products.append(.library(name: "FilamentAppKit", targets: ["FilamentAppKit"]))
targets.append(contentsOf: [
    .target(
        name: "FilamentAppKit",
        dependencies: ["Filament", "FilamentC"],
        path: "Sources/FilamentAppKit",
        swiftSettings: filamentSwiftSettings,
        linkerSettings: filamentLinkerSettings + [
            .linkedFramework("Metal"),
            .linkedFramework("MetalKit"),
            .linkedFramework("CoreGraphics"),
            .linkedFramework("QuartzCore"),
            .linkedFramework("Cocoa"),
        ]
    ),
    .testTarget(
        name: "FilamentAppKitTests",
        dependencies: ["Filament", "FilamentAppKit", "FilamentC"],
        path: "Tests/FilamentAppKitTests",
        swiftSettings: filamentSwiftSettings,
        linkerSettings: filamentLinkerSettings + [
            .linkedFramework("Metal"),
            .linkedFramework("MetalKit"),
            .linkedFramework("CoreGraphics"),
            .linkedFramework("QuartzCore"),
            .linkedFramework("Cocoa"),
        ]
    ),
])
#elseif os(Windows)
products.append(.library(name: "FilamentWin32", targets: ["FilamentWin32"]))
targets.append(.target(
    name: "FilamentWin32",
    dependencies: ["Filament", "FilamentC"],
    path: "Sources/FilamentWin32",
    swiftSettings: filamentSwiftSettings,
    linkerSettings: filamentLinkerSettings
))
#elseif os(Linux)
products.append(.library(name: "FilamentGTK", targets: ["FilamentGTK"]))
targets.append(.target(
    name: "FilamentGTK",
    dependencies: ["Filament", "FilamentC"],
    path: "Sources/FilamentGTK",
    swiftSettings: filamentSwiftSettings,
    linkerSettings: filamentLinkerSettings
))
#endif

let package = Package(
    name: "FilamentSwift",
    platforms: [
        .macOS(.v13),
    ],
    products: products,
    targets: targets,
    cxxLanguageStandard: .cxx17
)