import Foundation
import FilamentC

/// Type-safe Swift wrapper managing an Inverted Hull Outline Material for cartoon rendering in Filament.
///
/// Uses front-face culling (`culling: front`) and distance-compensated vertex extrusion
/// to draw consistent, stable ink silhouette outlines across all platforms (Metal, Vulkan, OpenGL).
@MainActor
public final class FilamentToonOutlineMaterial: @unchecked Sendable {
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

    // MARK: - Parameters

    /// Inked outline color (RGBA).
    /// Classic cartoon inks often use deep warm sepia/charcoal (#1A120B) rather than harsh #000000.
    public var outlineColor: (r: Float, g: Float, b: Float, a: Float) = (0.10, 0.08, 0.06, 1.0) {
        didSet { updateOutlineColor() }
    }

    /// Outline thickness scaling factor (multiplied with camera distance in vertex shader).
    public var outlineThickness: Float = 2.5 {
        didSet { updateOutlineThickness() }
    }

    // MARK: - Initialization & Teardown

    /// Compiles and instantiates the Inverted Hull outline material from precompiled `.filamat` binary data.
    public init(engine: OpaquePointer, filamatData: Data) throws {
        storage.engine = engine

        let mat = filamatData.withUnsafeBytes { rawBuffer -> OpaquePointer? in
            guard let base = rawBuffer.baseAddress else { return nil }
            return FilamentBridge.createMaterialFromPackage(engine, base, rawBuffer.count)
        }

        guard let validMat = mat else {
            throw NSError(domain: "FilamentToonOutlineMaterial", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compile/load ToonOutline .filamat package"])
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
        updateOutlineColor()
        updateOutlineThickness()
    }

    private func updateOutlineColor() {
        guard let inst = storage.materialInstance else { return }
        "outlineColor".withCString { name in
            FilamentBridge.setMaterialParameterFloat4(inst, name, outlineColor.r, outlineColor.g, outlineColor.b, outlineColor.a)
        }
    }

    private func updateOutlineThickness() {
        guard let inst = storage.materialInstance else { return }
        "outlineThickness".withCString { name in
            FilamentBridge.setMaterialParameterFloat(inst, name, outlineThickness)
        }
    }

    // MARK: - Application to Renderables & Assets

    /// Applies this outline material to a single primitive index of a Filament Renderable entity.
    public func apply(to entity: utils.Entity, primitiveIndex: Int = 0) {
        guard let eng = storage.engine, let inst = storage.materialInstance else { return }
        FilamentBridge.setMaterialOnRenderable(eng, entity, inst, primitiveIndex)
    }

    /// Applies this outline material to all primitive submeshes of a Filament Renderable entity.
    public func apply(toAllPrimitives entity: utils.Entity) {
        guard let eng = storage.engine, let inst = storage.materialInstance else { return }
        FilamentBridge.setMaterialOnAllPrimitives(eng, entity, inst)
    }
}
