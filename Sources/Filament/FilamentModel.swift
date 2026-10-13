import Foundation
import FilamentC

public struct FilamentAnimation: Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let duration: Float

    public init(id: Int, name: String, duration: Float) {
        self.id = id
        self.name = name
        self.duration = duration
    }
}

/// Manages glTF 2.0 / GLB 3D assets loaded via Google Filament gltfio.
///
/// The engine is retained strongly: Filament asserts if the engine is destroyed while
/// asset entities are still alive, so the model must always be unloaded (or deallocated)
/// before the engine that backs it goes away.
@MainActor
public final class FilamentModel {
    /// Non-isolated so `deinit` can detach the context from any thread; only the bridge
    /// calls that consume it are main-actor bound.
    private final class Storage: @unchecked Sendable {
        var glbContext: UnsafeMutablePointer<FilamentBridge.GlbContext>?
    }

    private let storage = Storage()
    private let engineRef: FilamentEngine

    private var glbContext: UnsafeMutablePointer<FilamentBridge.GlbContext>? {
        get { storage.glbContext }
        set { storage.glbContext = newValue }
    }

    public private(set) var animations: [FilamentAnimation] = []

    /// Index of the animation applied by `applyAnimation(time:)`, or `nil` when disabled.
    /// Assign through `selectAnimation(at:)`, which validates the range.
    public private(set) var activeAnimationIndex: Int? {
        didSet {
            if activeAnimationIndex == nil, let ctx = glbContext {
                FilamentBridge.resetBoneMatrices(ctx)
            }
        }
    }

    public var hasAnimations: Bool {
        return !animations.isEmpty
    }

    public var activeAnimationDuration: Float {
        guard let idx = activeAnimationIndex, idx >= 0, idx < animations.count else { return 0 }
        return animations[idx].duration
    }

    public var isLoaded: Bool {
        return glbContext != nil
    }

    public init(engine: FilamentEngine) {
        self.engineRef = engine
    }

    deinit {
        // Captured by value so the raw pointers stay valid even when the engine that owns
        // them is torn down on another thread first. `engineRef` is retained by this
        // closure, so the engine cannot be destroyed before the asset is released.
        let ctx = storage.glbContext
        storage.glbContext = nil
        let engine = engineRef
        FilamentMainActor.perform {
            guard let ctx else { return }
            FilamentBridge.destroyGlbContext(engine.engine, engine.scene, ctx)
        }
    }

    /// Unloads any currently loaded model from the scene. Idempotent.
    public func unload() {
        if let ctx = glbContext, let eng = engineRef.engine, let scn = engineRef.scene {
            FilamentBridge.destroyGlbContext(eng, scn, ctx)
        }
        glbContext = nil
        animations.removeAll()
        activeAnimationIndex = nil
    }

    /// Selects active animation index or nil to disable animation.
    public func selectAnimation(at index: Int?) {
        guard let idx = index else {
            activeAnimationIndex = nil
            return
        }
        if idx >= 0 && idx < animations.count {
            activeAnimationIndex = idx
        }
    }

    /// Applies the current active animation at the given timestamp in seconds.
    public func applyAnimation(time: Float) {
        guard let ctx = glbContext, let idx = activeAnimationIndex, idx >= 0, idx < animations.count else { return }
        FilamentBridge.applyAnimation(ctx, idx, time)
    }

    /// Loads a binary GLB file from disk.
    public func loadGlb(at url: URL) throws {
        let data = try Data(contentsOf: url)
        try loadGlb(data: data)
    }

    /// Loads a binary GLB from memory data using the gltfio ubershader pipeline.
    public func loadGlb(data: Data) throws {
        guard engineRef.engine != nil, engineRef.scene != nil else {
            throw NSError(domain: "FilamentModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Filament Engine or Scene is unavailable"])
        }

        unload()

        try data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw NSError(domain: "FilamentModel", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid or empty data buffer"])
            }
            let ctx = FilamentBridge.loadGlbFromMemory(engineRef.engine, engineRef.scene, base, rawBuffer.count)
            guard let loadedCtx = ctx else {
                throw NSError(domain: "FilamentModel", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse and load GLB model via gltfio"])
            }
            self.glbContext = loadedCtx
            refreshAnimations()
        }
    }

    private func refreshAnimations() {
        animations.removeAll()
        guard let ctx = glbContext else {
            activeAnimationIndex = nil
            return
        }
        let count = FilamentBridge.getAnimationCount(ctx)
        for i in 0..<count {
            let cName = FilamentBridge.getAnimationName(ctx, i)
            let rawName = (cName != nil && cName![0] != 0) ? String(cString: cName!) : ""
            let name = rawName.isEmpty ? "Animation \(i + 1)" : rawName
            let duration = FilamentBridge.getAnimationDuration(ctx, i)
            animations.append(FilamentAnimation(id: i, name: name, duration: duration))
        }
        activeAnimationIndex = animations.isEmpty ? nil : 0
    }

    /// Rotates the model around the Y axis in radians and scales it to fit the unit view frustum.
    public func setRotation(radiansY: Float) {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        FilamentBridge.setModelRotation(eng, ctx, radiansY)
    }
}