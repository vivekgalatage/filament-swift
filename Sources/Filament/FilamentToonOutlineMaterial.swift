import Foundation
import FilamentC

/// Type-safe Swift wrapper managing an Inverted Hull Outline Material for cartoon rendering in Filament.
///
/// Supports classic solid inked outlines as well as multi-color gradients (VIBGYOR rainbow,
/// vertical/radial gradients, and randomized facet patterns) with custom add/delete stops and animation flow.
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

    // MARK: - Enums & Types

    public enum GradientMode: Int32, CaseIterable, Sendable {
        case solid = 0
        case vertical = 1
        case radial = 2
        case rainbow = 3
        case randomFacets = 4
        case graphitePencil = 5

        public var title: String {
            switch self {
            case .solid: return "Solid Single Color"
            case .vertical: return "Vertical Height Gradient"
            case .radial: return "Radial Angle Gradient (360°)"
            case .rainbow: return "VIBGYOR Rainbow Spectrum"
            case .randomFacets: return "Random Multi-Color Facets"
            case .graphitePencil: return "Graphite Pencil Lead"
            }
        }
    }

    public struct GradientStop: Equatable, Sendable {
        public var position: Float
        public var color: (r: Float, g: Float, b: Float, a: Float)

        public init(position: Float, color: (r: Float, g: Float, b: Float, a: Float)) {
            self.position = position
            self.color = color
        }

        public static func == (lhs: GradientStop, rhs: GradientStop) -> Bool {
            lhs.position == rhs.position &&
            lhs.color.r == rhs.color.r &&
            lhs.color.g == rhs.color.g &&
            lhs.color.b == rhs.color.b &&
            lhs.color.a == rhs.color.a
        }
    }

    // MARK: - Predefined Gradient Palettes

    /// Authentic VIBGYOR / Rainbow spectral stops: Violet, Indigo, Blue, Green, Yellow, Orange, Red.
    public static let vibgyorStops: [GradientStop] = [
        GradientStop(position: 0.00, color: (0.58, 0.00, 0.83, 1.0)), // Violet
        GradientStop(position: 0.16, color: (0.29, 0.00, 0.51, 1.0)), // Indigo
        GradientStop(position: 0.33, color: (0.00, 0.20, 1.00, 1.0)), // Blue
        GradientStop(position: 0.50, color: (0.00, 0.85, 0.20, 1.0)), // Green
        GradientStop(position: 0.67, color: (1.00, 0.92, 0.00, 1.0)), // Yellow
        GradientStop(position: 0.83, color: (1.00, 0.50, 0.00, 1.0)), // Orange
        GradientStop(position: 1.00, color: (0.95, 0.10, 0.15, 1.0)), // Red
    ]

    /// Cyberpunk / Synthwave neon gradient palette.
    public static let synthwaveStops: [GradientStop] = [
        GradientStop(position: 0.0, color: (1.00, 0.08, 0.58, 1.0)), // Hot Pink
        GradientStop(position: 0.5, color: (0.00, 0.90, 1.00, 1.0)), // Electric Cyan
        GradientStop(position: 1.0, color: (1.00, 0.85, 0.00, 1.0)), // Neon Gold
    ]

    /// Warm Sunset flare gradient palette.
    public static let sunsetStops: [GradientStop] = [
        GradientStop(position: 0.00, color: (0.25, 0.05, 0.40, 1.0)), // Deep Purple
        GradientStop(position: 0.35, color: (0.85, 0.15, 0.30, 1.0)), // Crimson
        GradientStop(position: 0.70, color: (0.98, 0.55, 0.10, 1.0)), // Orange
        GradientStop(position: 1.00, color: (1.00, 0.90, 0.30, 1.0)), // Warm Gold
    ]

    /// Aurora Borealis / Northern Lights palette.
    public static let auroraStops: [GradientStop] = [
        GradientStop(position: 0.00, color: (0.05, 0.95, 0.55, 1.0)), // Emerald Green
        GradientStop(position: 0.40, color: (0.00, 0.75, 0.90, 1.0)), // Turquoise
        GradientStop(position: 0.75, color: (0.35, 0.20, 0.85, 1.0)), // Royal Indigo
        GradientStop(position: 1.00, color: (0.80, 0.20, 0.90, 1.0)), // Violet Magenta
    ]

    /// Generates vibrant, randomized multi-color gradient stops.
    public static func generateRandomStops(count: Int = 4) -> [GradientStop] {
        let clampedCount = max(2, min(8, count))
        var result: [GradientStop] = []
        for i in 0..<clampedCount {
            let pos = Float(i) / Float(clampedCount - 1)
            let r = Float.random(in: 0.15...1.0)
            let g = Float.random(in: 0.15...1.0)
            let b = Float.random(in: 0.15...1.0)
            result.append(GradientStop(position: pos, color: (r, g, b, 1.0)))
        }
        return result
    }

    // MARK: - Parameters

    /// Inked outline color (RGBA) used for solid mode.
    public var outlineColor: (r: Float, g: Float, b: Float, a: Float) = (0.10, 0.08, 0.06, 1.0) {
        didSet { updateOutlineColor() }
    }

    /// Outline thickness scaling factor (multiplied with camera distance in vertex shader).
    public var outlineThickness: Float = 2.5 {
        didSet { updateOutlineThickness() }
    }

    /// Active outline coloring mode (solid, vertical, radial, rainbow, or random facets).
    public var gradientMode: GradientMode = .solid {
        didSet { updateGradientMode() }
    }

    /// Custom gradient color stops (up to 8 stops).
    public var stops: [GradientStop] = FilamentToonOutlineMaterial.vibgyorStops {
        didSet { updateStops() }
    }

    /// Phase offset for the gradient animation / pattern positioning (0.0 ... 1.0).
    public var gradientPhase: Float = 0.0 {
        didSet { updatePhase() }
    }

    /// Frequency / repeat scale factor along the outline geometry.
    public var gradientScale: Float = 1.0 {
        didSet { updateScale() }
    }

    /// Noise / facet spatial frequency for the random multi-color facet pattern.
    public var noiseScale: Float = 6.0 {
        didSet { updateNoise() }
    }

    /// Amplitude of hand-drawn jitter / organic stroke wobble (0.0 = crisp vector, 1.0 = rough freehand sketch).
    public var outlineJitter: Float = 0.0 {
        didSet { updateJitter() }
    }

    /// Spatial frequency of the organic stroke wobble.
    public var outlineJitterFreq: Float = 4.0 {
        didSet { updateJitterFreq() }
    }

    /// Speed for automatic continuous flow animation in cycles per second.
    /// If 0.0, the gradient remains static.
    public var flowAnimationSpeed: Float = 0.0

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

    // MARK: - Stop Management

    @discardableResult
    public func addStop(color: (r: Float, g: Float, b: Float, a: Float)? = nil, position: Float? = nil) -> Bool {
        guard stops.count < 8 else { return false }
        let newColor = color ?? (Float.random(in: 0.2...1.0), Float.random(in: 0.2...1.0), Float.random(in: 0.2...1.0), 1.0)
        let newPos: Float
        if let position {
            newPos = max(0.0, min(1.0, position))
        } else if let last = stops.last, stops.count >= 2 {
            let prev = stops[stops.count - 2]
            newPos = (prev.position + last.position) * 0.5
        } else {
            newPos = 0.5
        }
        stops.append(GradientStop(position: newPos, color: newColor))
        stops.sort { $0.position < $1.position }
        return true
    }

    @discardableResult
    public func removeStop(at index: Int) -> Bool {
        guard stops.count > 2, index >= 0, index < stops.count else { return false }
        stops.remove(at: index)
        return true
    }

    public func setStopColor(at index: Int, r: Float, g: Float, b: Float, a: Float = 1.0) {
        guard index >= 0, index < stops.count else { return }
        stops[index].color = (r, g, b, a)
    }

    public func setStopPosition(at index: Int, position: Float) {
        guard index >= 0, index < stops.count else { return }
        stops[index].position = max(0.0, min(1.0, position))
        stops.sort { $0.position < $1.position }
    }

    public func randomizeColors() {
        for i in 0..<stops.count {
            let r = Float.random(in: 0.2...1.0)
            let g = Float.random(in: 0.2...1.0)
            let b = Float.random(in: 0.2...1.0)
            stops[i].color = (r, g, b, 1.0)
        }
    }

    // MARK: - Parameter Syncing

    public func pushAllParameters() {
        updateOutlineColor()
        updateOutlineThickness()
        updateGradientMode()
        updateStops()
        updatePhase()
        updateScale()
        updateNoise()
        updateJitter()
        updateJitterFreq()
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

    private func updateGradientMode() {
        guard let inst = storage.materialInstance else { return }
        "gradientMode".withCString { name in
            FilamentBridge.setMaterialParameterInt(inst, name, gradientMode.rawValue)
        }
    }

    private func updateStops() {
        guard let inst = storage.materialInstance else { return }
        let count = Int32(min(8, max(1, stops.count)))
        "stopCount".withCString { FilamentBridge.setMaterialParameterInt(inst, $0, count) }

        for i in 0..<8 {
            let colorName = "color\(i)"
            let posName = "pos\(i)"
            let stop = i < stops.count ? stops[i] : (stops.last ?? GradientStop(position: 1.0, color: outlineColor))
            colorName.withCString {
                FilamentBridge.setMaterialParameterFloat4(inst, $0, stop.color.r, stop.color.g, stop.color.b, stop.color.a)
            }
            posName.withCString {
                FilamentBridge.setMaterialParameterFloat(inst, $0, stop.position)
            }
        }
    }

    private func updatePhase() {
        guard let inst = storage.materialInstance else { return }
        "gradientPhase".withCString {
            FilamentBridge.setMaterialParameterFloat(inst, $0, gradientPhase)
        }
    }

    private func updateScale() {
        guard let inst = storage.materialInstance else { return }
        "gradientScale".withCString {
            FilamentBridge.setMaterialParameterFloat(inst, $0, gradientScale)
        }
    }

    private func updateNoise() {
        guard let inst = storage.materialInstance else { return }
        "noiseScale".withCString {
            FilamentBridge.setMaterialParameterFloat(inst, $0, noiseScale)
        }
    }

    private func updateJitter() {
        guard let inst = storage.materialInstance else { return }
        "outlineJitter".withCString {
            FilamentBridge.setMaterialParameterFloat(inst, $0, outlineJitter)
        }
    }

    private func updateJitterFreq() {
        guard let inst = storage.materialInstance else { return }
        "outlineJitterFreq".withCString {
            FilamentBridge.setMaterialParameterFloat(inst, $0, outlineJitterFreq)
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
