import Foundation
import FilamentC

public enum FilamentBackend: Sendable {
    case `default`
    case opengl
    case vulkan
    case metal
    case webgpu
    case noop
}

/// Non-isolated storage for the raw Filament handles owned by a `FilamentEngine`.
///
/// The handles are deliberately kept in a plain (non-actor-isolated) reference type so
/// that `deinit` — which runs on whichever thread dropped the last reference and is
/// therefore *not* main-actor isolated — can read, clear and snapshot them without
/// touching isolated state. Only the bridge calls that consume them are main-actor bound.
final class FilamentEngineStorage: @unchecked Sendable {
    var engine: OpaquePointer?
    var renderer: OpaquePointer?
    var scene: OpaquePointer?
    var view: OpaquePointer?
    var cameraId: UInt32 = 0
    var indirectLight: OpaquePointer?
    var colorGrading: OpaquePointer?
    var lightIds: Set<UInt32> = []
    var isShutDown: Bool = false

    /// Detaches every handle and returns them for destruction.
    func detach() -> FilamentEngineResources {
        isShutDown = true
        let snapshot = FilamentEngineResources(
            engine: engine,
            renderer: renderer,
            scene: scene,
            view: view,
            cameraId: cameraId,
            indirectLight: indirectLight,
            colorGrading: colorGrading,
            lightIds: Array(lightIds)
        )
        engine = nil
        renderer = nil
        scene = nil
        view = nil
        indirectLight = nil
        colorGrading = nil
        lightIds.removeAll()
        return snapshot
    }
}

/// A `Sendable` snapshot of every Filament resource owned by a `FilamentEngine`.
///
/// Teardown can be scheduled from a `deinit` running on an arbitrary thread, so the
/// resources are flattened into raw pointers/ids first.
struct FilamentEngineResources: @unchecked Sendable {
    var engine: OpaquePointer?
    var renderer: OpaquePointer?
    var scene: OpaquePointer?
    var view: OpaquePointer?
    var cameraId: UInt32
    var indirectLight: OpaquePointer?
    var colorGrading: OpaquePointer?
    var lightIds: [UInt32]

    /// Destroys the captured resources. Must run on the main actor.
    func destroyAll() {
        guard let engine else { return }
        if let scene {
            for id in lightIds {
                FilamentBridge.destroyLightById(engine, scene, id)
            }
        }
        if let indirectLight {
            FilamentBridge.destroyIndirectLight(engine, indirectLight)
        }
        // A ColorGrading must be dissociated from every view before it is destroyed.
        if let colorGrading {
            if let view {
                FilamentBridge.setViewColorGrading(view, nil)
            }
            FilamentBridge.destroyColorGrading(engine, colorGrading)
        }
        FilamentBridge.destroyCameraById(engine, cameraId)
        if let view { FilamentBridge.destroyView(engine, view) }
        if let scene { FilamentBridge.destroyScene(engine, scene) }
        if let renderer { FilamentBridge.destroyRenderer(engine, renderer) }
        FilamentBridge.destroyEngine(engine)
    }
}

/// High-level Swift manager for Google Filament's core rendering context.
///
/// Every Filament object it creates is released when it is deallocated or when
/// `shutDown()` is called. Because `deinit` may run on any thread, teardown is routed
/// through `FilamentMainActor.perform`: nothing traps, nothing leaks.
@MainActor
public final class FilamentEngine: @unchecked Sendable {
    private let storage = FilamentEngineStorage()

    public var engine: OpaquePointer? { storage.engine }
    public var renderer: OpaquePointer? { storage.renderer }
    public var scene: OpaquePointer? { storage.scene }
    public var view: OpaquePointer? { storage.view }

    /// `true` once `shutDown()` (or `deinit`) has released the Filament objects.
    public var isShutDown: Bool { storage.isShutDown }

    public convenience init() {
        self.init(backend: .default)
    }

    /// Creates an engine with the requested backend.
    ///
    /// - Precondition: the backend must be supported on this machine. `Engine::create`
    ///   returns `null` when it is not, which would make every subsequent bridge call a
    ///   null pointer dereference, so this traps with an actionable message instead.
    public init(backend: FilamentBackend = .default) {
        let b: filament.backend.Backend = switch backend {
        case .default: .DEFAULT
        case .opengl: .OPENGL
        case .vulkan: .VULKAN
        case .metal: .METAL
        case .webgpu: .WEBGPU
        case .noop: .NOOP
        }

        guard let created = FilamentBridge.createEngine(b) else {
            fatalError("""
                FilamentEngine: could not create a Filament engine with the \(backend) backend. \
                That backend is unavailable on this machine or in this process \
                (for example .vulkan with no Vulkan driver, or .metal off the UI thread).
                """)
        }

        storage.engine = created
        let ren = FilamentBridge.createRenderer(created)
        let scn = FilamentBridge.createScene(created)
        let vw = FilamentBridge.createView(created)
        storage.renderer = ren
        storage.scene = scn
        storage.view = vw

        let cameraEntity = FilamentBridge.createCamera(created)
        storage.cameraId = cameraEntity.getId()
        let cam = FilamentBridge.getCamera(created, cameraEntity)

        if let r = ren {
            // Enable per-frame color buffer clearing to the default studio background
            // (Filament's Renderer::ClearOptions::clear defaults to false).
            FilamentBridge.setTransparent(r, false)
        }

        if let v = vw {
            if let scn { FilamentBridge.setViewScene(v, scn) }
            if let cam { FilamentBridge.setViewCamera(v, cam) }
            // Opaque by default; flipped to TRANSLUCENT only while rendering into a
            // transparent swap chain (a TRANSLUCENT view forces whole-scene sorting).
            FilamentBridge.setViewBlendMode(v, false)
            FilamentBridge.setViewShadowingEnabled(v, true)
        }
    }

    deinit {
        let snapshot = storage.detach()
        FilamentMainActor.perform { snapshot.destroyAll() }
    }

    /// Releases every Filament object owned by this engine. Idempotent.
    ///
    /// `FilamentModel` retains its engine strongly, so a loaded model always outlives the
    /// engine backing it and this is only needed to release GPU resources eagerly.
    /// Call `FilamentModel.unload()` first if models are still attached.
    public func shutDown() {
        guard !storage.isShutDown else { return }
        let snapshot = storage.detach()
        FilamentMainActor.perform { snapshot.destroyAll() }
    }

    /// Sets whether the background renders with 100% alpha transparency.
    ///
    /// Also switches the view blend mode, which is what actually enables per-fragment
    /// blending of the scene into the swap chain.
    public func setTransparent(_ transparent: Bool) {
        if let ren = storage.renderer {
            FilamentBridge.setTransparent(ren, transparent)
        }
        if let v = storage.view {
            FilamentBridge.setViewBlendMode(v, transparent)
        }
    }

    /// Sets custom background clear color (RGBA).
    public func setClearColor(r: Float, g: Float, b: Float, a: Float) {
        if let ren = storage.renderer {
            FilamentBridge.setClearColor(ren, r, g, b, a)
        }
    }

    /// Configures spherical ambient indirect illumination for the scene.
    ///
    /// Replaces (and destroys) any previously installed indirect light, so calling this
    /// repeatedly does not leak `IndirectLight` objects.
    public func setAmbientLight(intensity: Float = 40_000.0) {
        guard let eng = storage.engine else { return }
        let ibl = FilamentBridge.setAmbientLight(eng, intensity)
        if let scn = storage.scene {
            FilamentBridge.setSceneAmbientLight(scn, ibl)
        }
        if let previous = storage.indirectLight {
            FilamentBridge.destroyIndirectLight(eng, previous)
        }
        storage.indirectLight = ibl
    }

    /// Number of `IndirectLight` objects currently alive in the engine (diagnostics/tests).
    public var indirectLightCount: Int {
        guard let eng = storage.engine else { return 0 }
        return Int(FilamentBridge.getIndirectLightCount(eng))
    }

    /// Configures the camera projection matrix.
    public func setCameraProjection(fovInDegrees: Double, aspect: Double, near: Double = 0.1, far: Double = 100.0) {
        guard let eng = storage.engine, let cam = currentCamera(eng) else { return }
        FilamentBridge.setCameraProjection(cam, fovInDegrees, aspect, near, far)
    }

    /// Configures the camera position and orientation.
    public func setCameraLookAt(eye: (Double, Double, Double),
                                center: (Double, Double, Double) = (0, 0, 0),
                                up: (Double, Double, Double) = (0, 1, 0)) {
        guard let eng = storage.engine, let cam = currentCamera(eng) else { return }
        FilamentBridge.setCameraLookAt(cam, eye.0, eye.1, eye.2, center.0, center.1, center.2, up.0, up.1, up.2)
    }

    /// Adds a directional sunlight to the scene and returns its light ID.
    ///
    /// The engine retains the ID so the light can be destroyed during teardown. Returns
    /// `nil` when the engine has already been shut down.
    @discardableResult
    public func addDirectionalLight(direction: (Float, Float, Float) = (0, -1, -1),
                                    color: (Float, Float, Float) = (1, 1, 1),
                                    intensity: Float = 100000.0) -> UInt32? {
        guard let eng = storage.engine, let scn = storage.scene else { return nil }
        let light = FilamentBridge.createDirectionalLight(
            eng, scn, direction.0, direction.1, direction.2,
            color.0, color.1, color.2, intensity
        )
        let id = light.getId()
        storage.lightIds.insert(id)
        return id
    }

    /// Removes a directional light created by `addDirectionalLight(direction:color:intensity:)`.
    ///
    /// Unknown or already-removed IDs are ignored: `utils::Entity::import` on a stale id
    /// would operate on whatever recycled entity owns that id.
    public func removeLight(id: UInt32) {
        guard let eng = storage.engine, let scn = storage.scene, storage.lightIds.remove(id) != nil else { return }
        FilamentBridge.destroyLightById(eng, scn, id)
    }

    /// Light IDs currently owned by this engine.
    public var activeLightIds: Set<UInt32> { storage.lightIds }

    private func withLight(_ id: UInt32, _ body: (OpaquePointer, utils.Entity) -> Void) {
        guard storage.lightIds.contains(id), let eng = storage.engine else { return }
        body(eng, FilamentBridge.entityFromId(id))
    }

    // MARK: - Runtime light controls

    /// Changes a light's intensity without rebuilding it.
    public func setLightIntensity(id: UInt32, intensity: Float) {
        withLight(id) { FilamentBridge.setLightIntensity($0, $1, intensity) }
    }

    /// Changes a light's color without rebuilding it.
    public func setLightColor(id: UInt32, color: (Float, Float, Float)) {
        withLight(id) { FilamentBridge.setLightColor($0, $1, color.0, color.1, color.2) }
    }

    /// Changes a directional light's direction without rebuilding it.
    public func setLightDirection(id: UInt32, direction: (Float, Float, Float)) {
        withLight(id) { FilamentBridge.setLightDirection($0, $1, direction.0, direction.1, direction.2) }
    }

    /// Enables or disables shadow casting for a light.
    public func setLightShadows(id: UInt32, enabled: Bool) {
        withLight(id) { FilamentBridge.setLightShadows($0, $1, enabled) }
    }

    // MARK: - PBR / post-processing controls

    /// Linear brightness multiplier; `1.0` keeps Filament's default exposure (f/16, 1/125s,
    /// ISO 100), which is calibrated for the ~100 000 lux lights used by the demos.
    public func setExposure(_ multiplier: Float) {
        guard let eng = storage.engine, let cam = currentCamera(eng) else { return }
        FilamentBridge.setCameraExposureMultiplier(cam, multiplier)
    }

    public func setAntiAliasing(_ mode: FilamentAntiAliasing) {
        guard let v = storage.view else { return }
        FilamentBridge.setAntiAliasingMode(v, mode.rawValue)
    }

    /// MSAA sample count. Filament supports 1, 2, 4 and 8; other values are clamped.
    public func setMultiSampleCount(_ sampleCount: Int) {
        guard let v = storage.view else { return }
        let allowed = [1, 2, 4, 8]
        let clamped = allowed.min(by: { abs($0 - sampleCount) < abs($1 - sampleCount) }) ?? 1
        FilamentBridge.setMultiSampleCount(v, UInt32(clamped))
    }

    public func setDithering(_ enabled: Bool) {
        guard let v = storage.view else { return }
        FilamentBridge.setDitheringEnabled(v, enabled)
    }

    public func setHDRQuality(_ quality: FilamentHDRQuality) {
        guard let v = storage.view else { return }
        FilamentBridge.setHDRQuality(v, quality.rawValue)
    }

    public func setBloom(enabled: Bool, strength: Float = 0.1, levels: Int = 6) {
        guard let v = storage.view else { return }
        FilamentBridge.setBloom(v, enabled, strength, UInt32(max(1, min(11, levels))))
    }

    public func setVignette(enabled: Bool, strength: Float = 0.5, roundness: Float = 0.5) {
        guard let v = storage.view else { return }
        FilamentBridge.setVignette(v, enabled, strength, roundness, 0.5, 0.5)
    }

    public func setAmbientOcclusion(enabled: Bool,
                                     mode: FilamentOcclusionMode = .ssao,
                                     intensity: Float = 1.0,
                                     radius: Float = 0.3) {
        guard let v = storage.view else { return }
        FilamentBridge.setAmbientOcclusion(v, enabled, mode.rawValue, intensity, radius, 1.0)
    }

    public func setScreenSpaceReflections(enabled: Bool, maxDistance: Float = 3.0) {
        guard let v = storage.view else { return }
        FilamentBridge.setScreenSpaceReflections(v, enabled, maxDistance, 0.1, 2.0)
    }

    public func setDepthOfField(enabled: Bool, cocScale: Float = 1.0) {
        guard let v = storage.view else { return }
        FilamentBridge.setDepthOfField(v, enabled, cocScale, 3)
    }

    /// Enables or disables shadow rendering for the whole view.
    public func setShadowsEnabled(_ enabled: Bool) {
        guard let v = storage.view else { return }
        FilamentBridge.setViewShadowingEnabled(v, enabled)
    }

    /// Installs a color-grading LUT built from tone mapping and grading parameters.
    ///
    /// Replaces (and destroys) any LUT installed by a previous call, so repeated calls do
    /// not leak. The caller must have already associated `grading` with the view.
    func replaceColorGrading(_ grading: OpaquePointer?) {
        guard let eng = storage.engine else { return }
        if let previous = storage.colorGrading, previous != grading {
            // Dissociate from the view first: a ColorGrading must never outlive its view.
            FilamentBridge.setViewColorGrading(storage.view, nil)
            FilamentBridge.destroyColorGrading(eng, previous)
        }
        storage.colorGrading = grading
    }

    /// Number of `ColorGrading` objects currently alive in the engine (diagnostics/tests).
    public var colorGradingCount: Int {
        guard let eng = storage.engine else { return 0 }
        return Int(FilamentBridge.getColorGradingCount(eng))
    }

    /// Creates a headless swap chain for offscreen rendering.
    public func createHeadlessSwapChain(width: UInt32, height: UInt32, transparent: Bool = true) -> OpaquePointer? {
        guard let eng = storage.engine else { return nil }
        var flags = FilamentBridge.getSwapChainFlagReadable()
        if transparent {
            flags |= FilamentBridge.getSwapChainFlagTransparent()
        }
        return FilamentBridge.createHeadlessSwapChain(eng, width, height, flags)
    }

    /// Destroys a headless swap chain.
    public func destroySwapChain(_ swapChain: OpaquePointer) {
        guard let eng = storage.engine else { return }
        FilamentBridge.destroySwapChain(eng, swapChain)
    }

    /// Reads pixels from the current frame into the provided buffer.
    public func readPixels(x: UInt32 = 0, y: UInt32 = 0, width: UInt32, height: UInt32,
                           into buffer: UnsafeMutableRawPointer, bufferSize: Int) -> Bool {
        guard let eng = storage.engine, let ren = storage.renderer else { return false }
        return FilamentBridge.readPixels(eng, ren, x, y, width, height, buffer, bufferSize)
    }

    /// Creates and compiles a custom Cel/Toon Material from binary `.filamat` data.
    public func createToonMaterial(from filamatData: Data) throws -> FilamentToonMaterial {
        guard let eng = storage.engine else {
            throw NSError(domain: "FilamentEngine", code: 10, userInfo: [NSLocalizedDescriptionKey: "Engine is shut down"])
        }
        return try FilamentToonMaterial(engine: eng, filamatData: filamatData)
    }

    /// Creates and compiles a custom Cel/Toon Material from a `.filamat` file URL.
    public func createToonMaterial(from filamatURL: URL) throws -> FilamentToonMaterial {
        let data = try Data(contentsOf: filamatURL)
        return try createToonMaterial(from: data)
    }

    /// Creates and compiles an Inverted Hull Outline Material from binary `.filamat` data.
    public func createOutlineMaterial(from filamatData: Data) throws -> FilamentToonOutlineMaterial {
        guard let eng = storage.engine else {
            throw NSError(domain: "FilamentEngine", code: 11, userInfo: [NSLocalizedDescriptionKey: "Engine is shut down"])
        }
        return try FilamentToonOutlineMaterial(engine: eng, filamatData: filamatData)
    }

    /// Creates and compiles an Inverted Hull Outline Material from a `.filamat` file URL.
    public func createOutlineMaterial(from filamatURL: URL) throws -> FilamentToonOutlineMaterial {
        let data = try Data(contentsOf: filamatURL)
        return try createOutlineMaterial(from: data)
    }

    /// Creates and compiles a Depth-Only Mask Material (colorWrite: false) from binary `.filamat` data.
    public func createDepthMaskMaterial(from filamatData: Data) throws -> FilamentDepthMaskMaterial {
        guard let eng = storage.engine else {
            throw NSError(domain: "FilamentEngine", code: 12, userInfo: [NSLocalizedDescriptionKey: "Engine is shut down"])
        }
        return try FilamentDepthMaskMaterial(engine: eng, filamatData: filamatData)
    }

    /// Creates and compiles a Depth-Only Mask Material (colorWrite: false) from a `.filamat` file URL.
    public func createDepthMaskMaterial(from filamatURL: URL) throws -> FilamentDepthMaskMaterial {
        let data = try Data(contentsOf: filamatURL)
        return try createDepthMaskMaterial(from: data)
    }

    private func currentCamera(_ engine: OpaquePointer) -> OpaquePointer? {
        FilamentBridge.getCamera(engine, FilamentBridge.entityFromId(storage.cameraId))
    }
}