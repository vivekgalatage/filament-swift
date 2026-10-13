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
    #else
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    proc.arguments = ["python3", scriptPath]
    proc.standardOutput = FileHandle.nullDevice
    try? proc.run()
    proc.waitUntilExit()
    #endif
}

// Mirror of the library's Swift settings: Swift 6, C++ interop against the same
// prebuilt Filament SDK. The library resolves that SDK itself; the demos need the same
// include path, honouring FILAMENT_DIR the same way.
let filamentDir: String = {
    if let env = ProcessInfo.processInfo.environment["FILAMENT_DIR"], !env.isEmpty {
        return env
    }
    let local = libraryRoot.appendingPathComponent(".filament")
    let headerPath = nativePath(local.appendingPathComponent("include/filament/Engine.h"))
    if FileManager.default.fileExists(atPath: headerPath) {
        return nativePath(local)
    }
    let scriptPath = nativePath(libraryRoot.appendingPathComponent("scripts/ensure_filament.py"))
    runEnsureFilament(scriptPath: scriptPath, expectedHeaderPath: headerPath)
    return nativePath(local)
}()

let includeDir = nativePath(URL(fileURLWithPath: filamentDir).appendingPathComponent("include"))
let bridgeIncludeDir = nativePath(libraryRoot.appendingPathComponent("Sources/FilamentC/include"))

// NOTE: for a path dependency SwiftPM identifies the package by its *directory* name,
// not the `name:` in its manifest - so this is "filament-swift", not "FilamentSwift".
var dependencies: [Package.Dependency] = [.package(path: "..")]

let demoSwiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .interoperabilityMode(.Cxx),
    .unsafeFlags([
        "-I", includeDir,
        "-I", bridgeIncludeDir,
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

let windowsLinkerSettings: [LinkerSetting] = [
    .linkedLibrary("user32"),
    .linkedLibrary("gdi32"),
    .linkedLibrary("opengl32"),
    .linkedLibrary("shlwapi"),
    .linkedLibrary("ole32"),
    .linkedLibrary("oleaut32"),
    .linkedLibrary("runtimeobject"),
    .linkedLibrary("shell32"),
    .linkedLibrary("comdlg32"),
    .linkedLibrary("dwmapi"),
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
    linkerSettings: windowsLinkerSettings
))

// The WinUI 3 demo additionally needs the generated WinRT projections. They live in
// their own package because SwiftPM can only read sources inside its own package root,
// so they cannot be targets of this one. The dependency is only added once they have
// been generated on a Windows machine.
if FileManager.default.fileExists(
    atPath: nativePath(packageRoot.appendingPathComponent("../WinUIProjections/Sources/WinUI"))
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
        linkerSettings: windowsLinkerSettings
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
        .linkedLibrary("gio-2.0"),
        .linkedLibrary("gobject-2.0"),
        .linkedLibrary("glib-2.0"),
        .linkedLibrary("X11"),
        .linkedLibrary("c++"),
        .linkedLibrary("c++abi"),
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