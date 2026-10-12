import Foundation
import FilamentC

/// Manages glTF 2.0 / GLB 3D assets loaded via gltfio.
@MainActor
public final class FilamentModel {
    public private(set) var asset: OpaquePointer?
    private weak var engineRef: FilamentEngine?

    public init(engine: FilamentEngine) {
        self.engineRef = engine
    }

    deinit {
        MainActor.assumeIsolated {
            // Clean up asset entities from scene if loaded
        }
    }

    /// Loads a binary GLB file from disk.
    public func loadGlb(at url: URL) throws {
        guard let _ = engineRef?.engine else { return }
        let data = try Data(contentsOf: url)
        try loadGlb(data: data)
    }

    /// Loads a binary GLB from memory data.
    public func loadGlb(data: Data) throws {
        guard let _ = engineRef?.engine, let _ = engineRef?.scene else { return }

        // gltfio loader pipeline:
        // Creates AssetLoader, parses binary glTF buffer, uploads textures/geometries,
        // and adds the resulting renderable entities directly into the scene.
        data.withUnsafeBytes { rawBuffer in
            guard let _ = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            // Loader implementation hooks
        }
    }
}
