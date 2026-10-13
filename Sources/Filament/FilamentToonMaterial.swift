import Foundation
import FilamentC

/// Type-safe Swift wrapper managing a Google Filament Cel/Toon Material and its instance uniforms.
///
/// Implements custom non-PBR lighting math designed for classic hand-drawn cartoon aesthetics
/// (like 1940s-1950s Tom and Jerry animation). Supports 2-tone or 3-tone quantized color shading,
/// directional light sampling, and seamless application to Filament renderable entities and glTF assets.
@MainActor
public final class FilamentToonMaterial: @unchecked Sendable {
    private final class Storage: @unchecked Sendable {
        var engine: OpaquePointer?
        var material: OpaquePointer?
        var materialInstance: OpaquePointer?

        func take() -> (OpaquePointer?, OpaquePointer?, OpaquePointer?) {
            let res = (engine, material, materialInstance)
            engine = nil
            material = nil
            materialInstance = nil
            return res
        }
    }

    private let storage = Storage()

    public var rawMaterial: OpaquePointer? { storage.material }
    public var rawInstance: OpaquePointer? { storage.materialInstance }

    // MARK: - Material Parameters

    /// Base painted cel color (RGBA).
    public var baseColor: (r: Float, g: Float, b: Float, a: Float) = (0.95, 0.70, 0.50, 1.0) {
        didSet { updateBaseColor() }
    }

    /// Color of the key light source (RGB).
    public var lightColor: (r: Float, g: Float, b: Float) = (1.0, 0.98, 0.95) {
        didSet { updateLightColor() }
    }

    /// Multiplier applied to baseColor in shadowed areas (RGB).
    /// Classic warm/cool cartoon contrast uses cool blue/lavender shadows (e.g. 0.45, 0.45, 0.65).
    public var shadowColorMultiplier: (r: Float, g: Float, b: Float) = (0.45, 0.45, 0.65) {
        didSet { updateShadowMultiplier() }
    }

    /// Direction vector of the incoming light.
    public var lightDirection: (x: Float, y: Float, z: Float) = (0.0, -1.0, -0.5) {
        didSet { updateLightDirection() }
    }

    /// Normal dot Light threshold for transitioning from shadow to midtone (-1.0 to 1.0).
    public var shadowThreshold: Float = 0.05 {
        didSet { updateThresholds() }
    }

    /// Normal dot Light threshold for transitioning from midtone to highlight (-1.0 to 1.0).
    public var highlightThreshold: Float = 0.75 {
        didSet { updateThresholds() }
    }

    /// Anti-aliasing boundary feathering width to eliminate temporal edge crawl/flicker.
    public var edgeFeather: Float = 0.015 {
        didSet { updateThresholds() }
    }

    // MARK: - Initialization & Teardown

    /// Compiles and instantiates the Toon material from precompiled `.filamat` binary data.
    public init(engine: OpaquePointer, filamatData: Data) throws {
        storage.engine = engine

        let mat = filamatData.withUnsafeBytes { rawBuffer -> OpaquePointer? in
            guard let base = rawBuffer.baseAddress else { return nil }
            return FilamentBridge.createMaterialFromPackage(engine, base, rawBuffer.count)
        }

        guard let validMat = mat else {
            throw NSError(domain: "FilamentToonMaterial", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compile/load ToonCel .filamat package"])
        }
        storage.material = validMat
        storage.materialInstance = FilamentBridge.createMaterialInstance(validMat)

        pushAllParameters()
    }

    /// Convenience initializer loading a `.filamat` file from a local URL.
    public convenience init(engine: OpaquePointer, filamatURL: URL) throws {
        let data = try Data(contentsOf: filamatURL)
        try self.init(engine: engine, filamatData: data)
    }

    deinit {
        let storage = self.storage
        FilamentMainActor.perform {
            let (eng, mat, inst) = storage.take()
            guard let eng else { return }
            if let inst { FilamentBridge.destroyMaterialInstance(eng, inst) }
            if let mat { FilamentBridge.destroyMaterial(eng, mat) }
        }
    }

    // MARK: - Parameter Syncing

    public func pushAllParameters() {
        updateBaseColor()
        updateLightColor()
        updateShadowMultiplier()
        updateLightDirection()
        updateThresholds()
    }

    private func updateBaseColor() {
        guard let inst = storage.materialInstance else { return }
        "baseColor".withCString { name in
            FilamentBridge.setMaterialParameterFloat4(inst, name, baseColor.r, baseColor.g, baseColor.b, baseColor.a)
        }
    }

    private func updateLightColor() {
        guard let inst = storage.materialInstance else { return }
        "lightColor".withCString { name in
            FilamentBridge.setMaterialParameterFloat3(inst, name, lightColor.r, lightColor.g, lightColor.b)
        }
    }

    private func updateShadowMultiplier() {
        guard let inst = storage.materialInstance else { return }
        "shadowColorMultiplier".withCString { name in
            FilamentBridge.setMaterialParameterFloat3(inst, name, shadowColorMultiplier.r, shadowColorMultiplier.g, shadowColorMultiplier.b)
        }
    }

    private func updateLightDirection() {
        guard let inst = storage.materialInstance else { return }
        let len = sqrt(lightDirection.x * lightDirection.x + lightDirection.y * lightDirection.y + lightDirection.z * lightDirection.z)
        let norm = len > 0 ? (lightDirection.x / len, lightDirection.y / len, lightDirection.z / len) : (0, 1, 0)
        // Pass vector pointing towards the light source to shader
        "lightDirection".withCString { name in
            FilamentBridge.setMaterialParameterFloat3(inst, name, -norm.0, -norm.1, -norm.2)
        }
    }

    private func updateThresholds() {
        guard let inst = storage.materialInstance else { return }
        "shadowThreshold".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, shadowThreshold) }
        "highlightThreshold".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, highlightThreshold) }
        "feather".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, edgeFeather) }
    }

    // MARK: - Application to Renderables & Assets

    /// Applies this toon material to a single primitive index of a Filament Renderable entity.
    public func apply(to entity: utils.Entity, primitiveIndex: Int = 0) {
        guard let eng = storage.engine, let inst = storage.materialInstance else { return }
        FilamentBridge.setMaterialOnRenderable(eng, entity, inst, primitiveIndex)
    }

    /// Applies this toon material to all primitive submeshes of a Filament Renderable entity.
    public func apply(toAllPrimitives entity: utils.Entity) {
        guard let eng = storage.engine, let inst = storage.materialInstance else { return }
        FilamentBridge.setMaterialOnAllPrimitives(eng, entity, inst)
    }

    /// Synchronizes light direction and color from a scene directional light source.
    public func syncWithDirectionalLight(direction: (Float, Float, Float), color: (Float, Float, Float)) {
        self.lightDirection = direction
        self.lightColor = color
    }
}
