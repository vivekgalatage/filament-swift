import Foundation
import FilamentC

/// High-level Swift manager for Google Filament's core rendering context.
@MainActor
public final class FilamentEngine {
    public private(set) var engine: OpaquePointer?
    public private(set) var renderer: OpaquePointer?
    public private(set) var scene: OpaquePointer?
    public private(set) var view: OpaquePointer?
    public private(set) var cameraEntity: utils.Entity

    public convenience init() {
        self.init(backend: .DEFAULT)
    }

    public init(backend: filament.backend.Backend) {
        let eng = FilamentBridge.createEngine(backend)
        self.engine = eng
        self.renderer = FilamentBridge.createRenderer(eng)
        self.scene = FilamentBridge.createScene(eng)
        self.view = FilamentBridge.createView(eng)

        self.cameraEntity = FilamentBridge.createCamera(eng)
        let cam = FilamentBridge.getCamera(eng, self.cameraEntity)

        if let v = self.view {
            if let scn = self.scene {
                FilamentBridge.setViewScene(v, scn)
            }
            if let c = cam {
                FilamentBridge.setViewCamera(v, c)
            }
            FilamentBridge.setViewBlendMode(v, true)
            FilamentBridge.setViewShadowingEnabled(v, true)
        }
    }

    deinit {
        MainActor.assumeIsolated {
            if let eng = engine {
                FilamentBridge.destroyCamera(eng, cameraEntity)
                if let v = view { FilamentBridge.destroyView(eng, v) }
                if let s = scene { FilamentBridge.destroyScene(eng, s) }
                if let r = renderer { FilamentBridge.destroyRenderer(eng, r) }
                FilamentBridge.destroyEngine(eng)
            }
        }
    }

    /// Sets whether the background renders with 100% alpha transparency.
    public func setTransparent(_ transparent: Bool) {
        if let ren = renderer {
            FilamentBridge.setTransparent(ren, transparent)
        }
    }
}
