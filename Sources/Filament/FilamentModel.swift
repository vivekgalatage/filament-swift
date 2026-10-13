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

public struct FilamentMorphTarget: Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    public var weight: Float

    public init(id: Int, name: String, weight: Float = 0.0) {
        self.id = id
        self.name = name
        self.weight = weight
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

        func take() -> UnsafeMutablePointer<FilamentBridge.GlbContext>? {
            let previous = glbContext
            glbContext = nil
            return previous
        }
    }

    private let storage = Storage()
    private let engineRef: FilamentEngine

    private var glbContext: UnsafeMutablePointer<FilamentBridge.GlbContext>? {
        get { storage.glbContext }
        set { storage.glbContext = newValue }
    }

    public private(set) var animations: [FilamentAnimation] = []
    public private(set) var morphTargets: [FilamentMorphTarget] = []
    public private(set) var hasCustomMorphWeights: Bool = false
    private var cachedWeightsBuffer: [Float] = []

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

    public var hasMorphTargets: Bool {
        return !morphTargets.isEmpty
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
        // Captured via the `@unchecked Sendable` storage box so raw pointers stay valid
        // without crossing a `@Sendable` closure boundary. `engineRef` is retained by this
        // closure, so the engine cannot be destroyed before the asset is released.
        let storage = storage
        let engine = engineRef
        FilamentMainActor.perform {
            guard let ctx = storage.take() else { return }
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
        morphTargets.removeAll()
        hasCustomMorphWeights = false
        cachedWeightsBuffer.removeAll()
        activeAnimationIndex = nil
        isVisible = false
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

    /// Sets the weight (typically 0.0 to 1.0) of a blend shape / morph target by index.
    /// If the target has an assigned glTF target name, all other targets sharing that name
    /// are synchronized so multi-entity submeshes (e.g. head, mouth, teeth) deform together.
    public func setMorphWeight(at index: Int, weight: Float) {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        guard index >= 0 && index < morphTargets.count else { return }
        let targetName = morphTargets[index].name
        let isNamed = !targetName.hasPrefix("MorphTarget ")
        if isNamed {
            for i in 0..<morphTargets.count {
                if morphTargets[i].name == targetName {
                    morphTargets[i].weight = weight
                }
            }
            targetName.withCString { cStr in
                FilamentBridge.setMorphWeightByName(eng, ctx, cStr, weight)
            }
        } else {
            morphTargets[index].weight = weight
            FilamentBridge.setMorphWeight(eng, ctx, index, weight)
        }
        hasCustomMorphWeights = true
    }

    /// Sets the weight (typically 0.0 to 1.0) of a blend shape / morph target by name across all meshes.
    public func setMorphWeight(named name: String, weight: Float) {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        for i in 0..<morphTargets.count {
            if morphTargets[i].name == name {
                morphTargets[i].weight = weight
            }
        }
        name.withCString { cStr in
            FilamentBridge.setMorphWeightByName(eng, ctx, cStr, weight)
        }
        hasCustomMorphWeights = true
    }

    /// Re-applies all active morph target weights to their respective renderables.
    /// Call this per-frame after `applyAnimation(time:)` so manual morph target
    /// modifications persist and are not overwritten by keyframed animations.
    public func applyMorphWeights() {
        guard hasCustomMorphWeights, let eng = engineRef.engine, let ctx = glbContext else { return }
        guard !morphTargets.isEmpty else { return }

        let count = morphTargets.count
        if cachedWeightsBuffer.count != count {
            cachedWeightsBuffer = [Float](repeating: 0.0, count: count)
        }
        for i in 0..<count {
            cachedWeightsBuffer[i] = morphTargets[i].weight
        }
        cachedWeightsBuffer.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                FilamentBridge.applyMorphWeights(eng, ctx, base, count)
            }
        }
    }

    /// Returns the current weight of a blend shape / morph target by index, or 0.0 if out of range.
    public func getMorphWeight(at index: Int) -> Float {
        guard index >= 0 && index < morphTargets.count else { return 0.0 }
        return morphTargets[index].weight
    }

    /// Resets all morph target weights to 0.0.
    public func resetMorphWeights() {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        for i in 0..<morphTargets.count {
            morphTargets[i].weight = 0.0
        }
        hasCustomMorphWeights = false
        FilamentBridge.resetMorphWeights(eng, ctx)
    }

    /// Sets the weight (typically 0.0 to 1.0) of a blend shape / morph target by index.
    public func setBlendShape(index: Int, weight: Float) {
        setMorphWeight(at: index, weight: weight)
    }

    /// Sets the weight (typically 0.0 to 1.0) of a blend shape / morph target by name.
    public func setBlendShape(name: String, weight: Float) {
        setMorphWeight(named: name, weight: weight)
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
            self.isVisible = true
            refreshAnimations()
            refreshMorphTargets()
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

    private func refreshMorphTargets() {
        morphTargets.removeAll()
        hasCustomMorphWeights = false
        cachedWeightsBuffer.removeAll()
        guard let ctx = glbContext else { return }
        let count = FilamentBridge.getMorphTargetCount(ctx)
        for i in 0..<count {
            let cName = FilamentBridge.getMorphTargetName(ctx, i)
            let rawName = (cName != nil && cName![0] != 0) ? String(cString: cName!) : ""
            let name = rawName.isEmpty ? "MorphTarget \(i + 1)" : rawName
            morphTargets.append(FilamentMorphTarget(id: i, name: name))
        }
        cachedWeightsBuffer = [Float](repeating: 0.0, count: count)
    }

    /// Rotates the model around the Y axis in radians and scales it to fit the unit view frustum.
    public func setRotation(radiansY: Float) {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        FilamentBridge.setModelRotation(eng, ctx, radiansY)
    }

    /// Replaces the material on all renderable primitives across this model's entities with the given material instance.
    public func applyMaterialInstance(_ materialInstance: OpaquePointer) {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        FilamentBridge.applyMaterialToGlbAsset(eng, ctx, materialInstance)
    }

    /// Applies a custom toon cel material to all renderable primitives of this model.
    public func applyToonMaterial(_ toonMaterial: FilamentToonMaterial) {
        guard let inst = toonMaterial.rawInstance else { return }
        applyMaterialInstance(inst)
    }

    /// Applies an inverted hull outline material to all renderable primitives of this model.
    public func applyOutlineMaterial(_ outlineMaterial: FilamentToonOutlineMaterial) {
        guard let inst = outlineMaterial.rawInstance else { return }
        applyMaterialInstance(inst)
    }

    /// Whether this model's entities are currently added to the Filament scene.
    public private(set) var isVisible: Bool = true

    /// Toggles the visibility of this model by adding or removing its entities from the scene.
    public func setVisible(_ visible: Bool) {
        guard let scn = engineRef.scene, let ctx = glbContext else { return }
        if isVisible == visible { return }
        isVisible = visible
        if visible {
            FilamentBridge.showGlbAsset(scn, ctx)
        } else {
            FilamentBridge.hideGlbAsset(scn, ctx)
        }
    }

    /// Sets the coarse draw priority (0..7, default is 4; 7 is rendered last).
    public func setPriority(_ priority: UInt8) {
        guard let eng = engineRef.engine, let ctx = glbContext else { return }
        FilamentBridge.setGlbPriority(eng, ctx, priority)
    }
}