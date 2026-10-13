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

func nativePath(_ url: URL) -> String {
    url.withUnsafeFileSystemRepresentation { ptr in
        ptr.map { String(cString: $0) }
    } ?? url.path
}

func runEnsureFilament(scriptPath: String, expectedHeaderPath: String) {
    #if os(Windows)
    let env = ProcessInfo.processInfo.environment
    let pathDirs = (env["PATH"] ?? env["Path"] ?? "")
        .split(separator: ";")
        .map(String.init)
    let realDirs = pathDirs.filter { !$0.lowercased().contains("windowsapps") }
    let stubDirs = pathDirs.filter { $0.lowercased().contains("windowsapps") }

    var candidates: [(String, [String])] = []
    for dir in (realDirs + ["C:\\Windows"] + stubDirs) {
        let base = URL(fileURLWithPath: dir)
        let pythonExe = nativePath(base.appendingPathComponent("python.exe"))
        if FileManager.default.fileExists(atPath: pythonExe) {
            candidates.append((pythonExe, [scriptPath]))
        }
        let pyExe = nativePath(base.appendingPathComponent("py.exe"))
        if FileManager.default.fileExists(atPath: pyExe) {
            candidates.append((pyExe, ["-3", scriptPath]))
        }
        let python3Exe = nativePath(base.appendingPathComponent("python3.exe"))
        if FileManager.default.fileExists(atPath: python3Exe) {
            candidates.append((python3Exe, [scriptPath]))
        }
    }
    let comSpec = env["ComSpec"] ?? "C:\\Windows\\System32\\cmd.exe"
    candidates.append((comSpec, ["/d", "/s", "/c", "python \"\(scriptPath)\""]))
    candidates.append((comSpec, ["/d", "/s", "/c", "py -3 \"\(scriptPath)\""]))

    for (exe, args) in candidates {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: expectedHeaderPath) {
                return
            }
        }
    }
    let message = "[FilamentSwift] warning: could not run scripts/ensure_filament.py; "
        + "ensure Python 3 is installed on PATH or set FILAMENT_DIR.\n"
    FileHandle.standardError.write(Data(message.utf8))
    #else
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["python3", scriptPath]
    proc.standardOutput = FileHandle.nullDevice
    do {
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let message = "[FilamentSwift] warning: ensure_filament.py exited with status "
                + "\(proc.terminationStatus); assuming \(expectedHeaderPath) is usable.\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    } catch {
        let message = "[FilamentSwift] warning: could not run scripts/ensure_filament.py (\(error)); "
            + "set FILAMENT_DIR to point at a prebuilt Filament SDK.\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
    #endif
}

// Resolve or ensure .filament cache is populated
let filamentDir: String = {
    if let env = ProcessInfo.processInfo.environment["FILAMENT_DIR"], !env.isEmpty {
        return env
    }
    let local = packageRoot.appendingPathComponent(".filament")
    let headerPath = nativePath(local.appendingPathComponent("include/filament/Engine.h"))
    if FileManager.default.fileExists(atPath: headerPath) {
        return nativePath(local)
    }
    let scriptPath = nativePath(packageRoot.appendingPathComponent("scripts/ensure_filament.py"))
    runEnsureFilament(scriptPath: scriptPath, expectedHeaderPath: headerPath)
    return nativePath(local)
}()

let includeDir = nativePath(URL(fileURLWithPath: filamentDir).appendingPathComponent("include"))
let bridgeIncludeDir = nativePath(packageRoot.appendingPathComponent("Sources/FilamentC/include"))

/// Root of the prebuilt Filament libraries.
///
///   * macOS   - `lib/lib<name>.a` under `lib/arm64` or `lib/x86_64`
///   * Linux   - `lib/lib<name>.a` under `lib/x86_64`
///   * Windows - `<name>.lib` (static libraries compiled with `/MD` dynamic CRT to match
///               Swift on Windows) under `lib/x86_64/md`
let libDir: String = {
    let root = URL(fileURLWithPath: filamentDir)
    #if os(macOS)
    #if arch(arm64)
    return nativePath(root.appendingPathComponent("lib/arm64"))
    #else
    return nativePath(root.appendingPathComponent("lib/x86_64"))
    #endif
    #elseif os(Windows)
    let mdDir = root.appendingPathComponent("lib/x86_64/md")
    if FileManager.default.fileExists(atPath: nativePath(mdDir)) {
        return nativePath(mdDir)
    }
    return nativePath(root.appendingPathComponent("lib/x86_64"))
    #else
    return nativePath(root.appendingPathComponent("lib/x86_64"))
    #endif
}()

let filamentLibraryNames = [
    "filament", "backend", "bluevk", "bluegl", "filabridge", "filaflat",
    "utils", "geometry", "smol-v", "ibl", "gltfio", "gltfio_core", "dracodec",
    "basis_transcoder", "meshoptimizer", "uberarchive", "uberzlib",
    "zstd", "stb", "ktxreader",
]

#if os(Windows)
let filamentStaticLibs: [String] = filamentLibraryNames.map {
    nativePath(URL(fileURLWithPath: libDir).appendingPathComponent("\($0).lib"))
}
let filamentLinkerSettings: [LinkerSetting] = [
    .unsafeFlags(filamentStaticLibs),
    .linkedLibrary("gdi32"),
    .linkedLibrary("user32"),
    .linkedLibrary("opengl32"),
    .linkedLibrary("shlwapi"),
    .linkedLibrary("dwmapi"),
    .linkedLibrary("ole32"),
    .linkedLibrary("shell32"),
]
#elseif os(Linux)
let filamentStaticLibs: [String] = filamentLibraryNames.map { "\(libDir)/lib\($0).a" }
let filamentLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("stdc++"),
    .linkedLibrary("pthread"),
    .linkedLibrary("dl"),
    .unsafeFlags(filamentStaticLibs),
]
#else
let filamentStaticLibs: [String] = filamentLibraryNames.map { "\(libDir)/lib\($0).a" }
let filamentLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("c++"),
    .unsafeFlags(filamentStaticLibs),
]
#endif

let filamentSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .interoperabilityMode(.Cxx),
    .unsafeFlags([
        "-I", includeDir,
        "-I", bridgeIncludeDir,
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