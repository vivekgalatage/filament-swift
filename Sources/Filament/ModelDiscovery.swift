import Foundation

/// Represents a 3D model asset (.glb) on disk.
public struct ModelAsset: Sendable, Identifiable, Equatable {
    public let id: String
    public let name: String
    public let url: URL

    public init(name: String, url: URL) {
        self.id = url.standardizedFileURL.path
        self.name = name
        self.url = url.standardizedFileURL
    }

    public init(url: URL) {
        let standardized = url.standardizedFileURL
        self.id = standardized.path
        self.name = standardized.deletingPathExtension().lastPathComponent
        self.url = standardized
    }
}

/// Dynamic discovery utility for 3D model assets (.glb) in resource folders.
public enum ModelDiscovery {
    /// Discovers all `.glb` models in the standard search paths.
    ///
    /// Search paths are visited in order and de-duplicated by file base name, so a model
    /// found earlier in the list wins over a same-named model found later.
    /// Returns an empty array if no `.glb` files are found.
    ///
    /// - Parameters:
    ///   - extraSearchPaths: directories searched *before* the default ones.
    ///   - includeDefaultPaths: when `false`, only `extraSearchPaths` are searched.
    public static func discoverModels(extraSearchPaths: [URL] = [],
                                      includeDefaultPaths: Bool = true) -> [ModelAsset] {
        var found: [ModelAsset] = []
        var seenNames = Set<String>()

        let searchPaths = includeDefaultPaths
            ? normalizedSearchPaths(extraSearchPaths)
            : deduplicated(extraSearchPaths)

        for dir in searchPaths {
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            guard let contents = try? FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in contents {
                guard url.pathExtension.lowercased() == "glb" else { continue }
                // A directory named "Something.glb" must not be offered as a model.
                //
                // This deliberately uses FileManager rather than
                // `URLResourceValues.isRegularFile`: resource values do not follow
                // symlinks, and under Bazel every runfiles entry is one, so the
                // URL-based check reports `false` and silently drops every model.
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      !isDir.boolValue,
                      FileManager.default.isReadableFile(atPath: url.path) else {
                    continue
                }
                let name = url.deletingPathExtension().lastPathComponent
                guard !seenNames.contains(name) else { continue }
                seenNames.insert(name)
                found.append(ModelAsset(name: name, url: url))
            }
        }

        found.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return found
    }

    /// Merges user-selected file or directory URLs (from a file open dialog) into `existing`
    /// models without duplicates, returning the index of the first newly selected model.
    public static func mergeSelectedURLs(_ urls: [URL], into existing: inout [ModelAsset]) -> Int? {
        var firstSelectedIndex: Int?
        var isDir: ObjCBool = false

        for rawURL in urls {
            let url = rawURL.standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                let inDir = discoverModels(extraSearchPaths: [url], includeDefaultPaths: false)
                for asset in inDir {
                    if let idx = existing.firstIndex(where: { $0.id == asset.id }) {
                        if firstSelectedIndex == nil { firstSelectedIndex = idx }
                    } else {
                        existing.append(asset)
                        if firstSelectedIndex == nil { firstSelectedIndex = existing.count - 1 }
                    }
                }
            } else if url.pathExtension.lowercased() == "glb" {
                let asset = ModelAsset(url: url)
                if let idx = existing.firstIndex(where: { $0.id == asset.id }) {
                    if firstSelectedIndex == nil { firstSelectedIndex = idx }
                } else {
                    existing.append(asset)
                    if firstSelectedIndex == nil { firstSelectedIndex = existing.count - 1 }
                }
            }
        }
        return firstSelectedIndex
    }

    /// Default directories inspected for models, in priority order.
    public static func defaultSearchDirectories() -> [URL] {
        let fm = FileManager.default
        var dirs: [URL] = []

        // Resources directory relative to the current working directory and its parents,
        // so the demos work from the package root, from a build directory, or from a
        // subdirectory.
        var cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<3 {
            dirs.append(cwd.appendingPathComponent("Resources", isDirectory: true))
            let parent = cwd.deletingLastPathComponent().standardizedFileURL
            if parent.path == cwd.path || parent.path.isEmpty { break }
            cwd = parent
        }

        // Bazel runfiles: TEST_SRCDIR / RUNFILES_DIR point at the tree that holds the
        // declared `data`, which is where the sample models and any `Resources` directory
        // copied by a demo target will be. The working directory is not reliable here.
        let env = ProcessInfo.processInfo.environment
        for key in ["RUNFILES_DIR", "TEST_SRCDIR"] {
            if let runfiles = env[key], !runfiles.isEmpty {
                let root = URL(fileURLWithPath: runfiles, isDirectory: true)
                dirs.append(root.appendingPathComponent("Resources", isDirectory: true))
                dirs.append(root.appendingPathComponent("Examples/Resources", isDirectory: true))
                // Manifest-based runfiles: <dir>/<workspace>/<path>
                let main = root.appendingPathComponent("_main", isDirectory: true)
                if FileManager.default.fileExists(atPath: main.path) {
                    dirs.append(main.appendingPathComponent("Resources", isDirectory: true))
                    dirs.append(main.appendingPathComponent("Examples/Resources", isDirectory: true))
                }
            }
        }

        // The sample models ship with the Examples package (`Examples/Resources`), which
        // is where they live when running from the repository root - both for `swift test`
        // and for `swift run --package-path Examples <Demo>`, since `swift run` does not
        // change the process working directory.
        var repoRoot = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        for _ in 0..<3 {
            let examples = repoRoot.appendingPathComponent("Examples/Resources", isDirectory: true)
            if fm.fileExists(atPath: examples.path) {
                dirs.append(examples)
                break
            }
            let parent = repoRoot.deletingLastPathComponent().standardizedFileURL
            if parent.path == repoRoot.path || parent.path.isEmpty { break }
            repoRoot = parent
        }

        // Bundled resources.
        if let bundleRes = Bundle.main.resourceURL {
            dirs.append(bundleRes)
            dirs.append(bundleRes.appendingPathComponent("Resources", isDirectory: true))
        }

        // Resources next to (or just above) the executable, which is where SwiftPM and
        // Bazel place a copied `Resources` directory.
        if let exeURL = Bundle.main.executableURL?.deletingLastPathComponent() {
            var dir = exeURL.standardizedFileURL
            for _ in 0..<3 {
                dirs.append(dir.appendingPathComponent("Resources", isDirectory: true))
                let parent = dir.deletingLastPathComponent().standardizedFileURL
                if parent.path == dir.path || parent.path.isEmpty { break }
                dir = parent
            }
        }

        return dirs
    }

    private static func normalizedSearchPaths(_ extraSearchPaths: [URL]) -> [URL] {
        deduplicated(extraSearchPaths + defaultSearchDirectories())
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            if seen.insert(standardized.path).inserted {
                result.append(standardized)
            }
        }
        return result
    }
}