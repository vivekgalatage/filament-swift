import Foundation
import FilamentC

/// Type-safe Swift wrapper managing a Depth-Only Mask Material in Google Filament.
///
/// Uses `colorWrite: false` and `depthWrite: true` to populate the Z-buffer with the
/// character's front-facing surface while writing nothing to the color buffer.
/// When paired with an inverted hull outline pass, this masks out the entire interior of the body,
/// rendering **only** the outer inked line art with a transparent/pass-through body.
@MainActor
public final class FilamentDepthMaskMaterial: @unchecked Sendable {
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

    // MARK: - Initialization & Teardown

    /// Compiles and instantiates the depth mask material from precompiled `.filamat` binary data.
    public init(engine: OpaquePointer, filamatData: Data) throws {
        storage.engine = engine

        let mat = filamatData.withUnsafeBytes { rawBuffer -> OpaquePointer? in
            guard let base = rawBuffer.baseAddress else { return nil }
            return FilamentBridge.createMaterialFromPackage(engine, base, rawBuffer.count)
        }

        guard let validMat = mat else {
            throw NSError(domain: "FilamentDepthMaskMaterial", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to compile/load DepthMask .filamat package"])
        }
        storage.material = validMat
        storage.materialInstance = FilamentBridge.createMaterialInstance(validMat)
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

    // MARK: - Application to Renderables & Assets

    /// Applies this depth mask material to a single primitive index of a Filament Renderable entity.
    public func apply(to entity: utils.Entity, primitiveIndex: Int = 0) {
        guard let eng = storage.engine, let inst = storage.materialInstance else { return }
        FilamentBridge.setMaterialOnRenderable(eng, entity, inst, primitiveIndex)
    }

    /// Applies this depth mask material to all primitive submeshes of a Filament Renderable entity.
    public func apply(toAllPrimitives entity: utils.Entity) {
        guard let eng = storage.engine, let inst = storage.materialInstance else { return }
        FilamentBridge.setMaterialOnAllPrimitives(eng, entity, inst)
    }
}
