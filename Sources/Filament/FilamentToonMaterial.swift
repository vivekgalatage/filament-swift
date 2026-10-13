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

    // MARK: - Halftone & Screentone Parameters

    public enum HalftoneMode: Int, CaseIterable, Sendable {
        case disabled = 0
        case screenDots = 1
        case surfaceUVDots = 2
        case cmykPrint = 3
        case hatchingLines = 4

        public var title: String {
            switch self {
            case .disabled: return "Disabled (Clean Cel)"
            case .screenDots: return "Screen-Space Dots (Pop-Art / Spider-Verse)"
            case .surfaceUVDots: return "Surface UV Dots (Manga Screentone)"
            case .cmykPrint: return "CMYK 4-Color Print Separation"
            case .hatchingLines: return "Hatching / Engraving Lines"
            }
        }
    }

    public enum HalftoneTarget: Int, CaseIterable, Sendable {
        case shadowsOnly = 0
        case fullSurface = 1
        case highlightsOnly = 2

        public var title: String {
            switch self {
            case .shadowsOnly: return "Shadows & Transitions (Manga)"
            case .fullSurface: return "Full Surface (Pop-Art Print)"
            case .highlightsOnly: return "Highlights Only"
            }
        }
    }

    /// Halftone rendering pattern mode (dots, UV screentone, CMYK, hatching).
    public var halftoneMode: HalftoneMode = .disabled {
        didSet { updateHalftoneParameters() }
    }

    /// Halftone target shading zone (shadows only, full surface, highlights only).
    public var halftoneTarget: HalftoneTarget = .shadowsOnly {
        didSet { updateHalftoneParameters() }
    }

    /// Dot/line frequency scale. Higher values = finer dots; lower = bold graphic dots.
    public var halftoneScale: Float = 24.0 {
        didSet { updateHalftoneParameters() }
    }

    /// Dot grid screen rotation angle in degrees (e.g. 45° standard printing angle).
    public var halftoneAngle: Float = 45.0 {
        didSet { updateHalftoneParameters() }
    }

    /// Dot radius or line width multiplier (0.1 to 2.0).
    public var halftoneDotSize: Float = 1.0 {
        didSet { updateHalftoneParameters() }
    }

    /// Dot edge hardness (0.0 = soft ink bleed, 1.0 = razor-sharp vector circles).
    public var halftoneHardness: Float = 0.85 {
        didSet { updateHalftoneParameters() }
    }

    /// Blend factor between pure cel shading (0.0) and full halftone effect (1.0).
    public var halftoneBlend: Float = 1.0 {
        didSet { updateHalftoneParameters() }
    }

    /// Color of the printed ink dots (RGBA).
    public var halftoneDotColor: (r: Float, g: Float, b: Float, a: Float) = (0.08, 0.06, 0.05, 1.0) {
        didSet { updateHalftoneParameters() }
    }

    /// Color of the paper / background beneath the halftone dots (RGBA).
    public var halftonePaperColor: (r: Float, g: Float, b: Float, a: Float) = (0.98, 0.97, 0.94, 1.0) {
        didSet { updateHalftoneParameters() }
    }

    public struct HalftonePreset: Sendable {
        public let name: String
        public let mode: HalftoneMode
        public let target: HalftoneTarget
        public let scale: Float
        public let angle: Float
        public let dotSize: Float
        public let hardness: Float
        public let dotColor: (r: Float, g: Float, b: Float, a: Float)
        public let paperColor: (r: Float, g: Float, b: Float, a: Float)

        public init(
            name: String,
            mode: HalftoneMode,
            target: HalftoneTarget,
            scale: Float,
            angle: Float,
            dotSize: Float,
            hardness: Float,
            dotColor: (r: Float, g: Float, b: Float, a: Float),
            paperColor: (r: Float, g: Float, b: Float, a: Float)
        ) {
            self.name = name
            self.mode = mode
            self.target = target
            self.scale = scale
            self.angle = angle
            self.dotSize = dotSize
            self.hardness = hardness
            self.dotColor = dotColor
            self.paperColor = paperColor
        }
    }

    public static let spiderVersePreset = HalftonePreset(
        name: "Spider-Verse Pop-Art",
        mode: .screenDots,
        target: .fullSurface,
        scale: 18.0,
        angle: 45.0,
        dotSize: 1.05,
        hardness: 0.92,
        dotColor: (0.05, 0.05, 0.06, 1.0),
        paperColor: (0.98, 0.97, 0.95, 1.0)
    )

    public static let mangaScreentonePreset = HalftonePreset(
        name: "Manga Screentone",
        mode: .surfaceUVDots,
        target: .shadowsOnly,
        scale: 32.0,
        angle: 45.0,
        dotSize: 1.0,
        hardness: 0.88,
        dotColor: (0.08, 0.07, 0.06, 1.0),
        paperColor: (0.98, 0.98, 0.98, 1.0)
    )

    public static let cmykNewspaperPreset = HalftonePreset(
        name: "Vintage CMYK Newspaper",
        mode: .cmykPrint,
        target: .fullSurface,
        scale: 22.0,
        angle: 0.0,
        dotSize: 1.1,
        hardness: 0.80,
        dotColor: (0.0, 0.0, 0.0, 1.0),
        paperColor: (0.96, 0.94, 0.88, 1.0)
    )

    public static let comicHatchingPreset = HalftonePreset(
        name: "Woodcut / Pen Hatching",
        mode: .hatchingLines,
        target: .shadowsOnly,
        scale: 18.0,
        angle: 35.0,
        dotSize: 1.0,
        hardness: 0.90,
        dotColor: (0.10, 0.08, 0.07, 1.0),
        paperColor: (0.98, 0.97, 0.94, 1.0)
    )

    public func applyPreset(_ preset: HalftonePreset) {
        self.halftoneMode = preset.mode
        self.halftoneTarget = preset.target
        self.halftoneScale = preset.scale
        self.halftoneAngle = preset.angle
        self.halftoneDotSize = preset.dotSize
        self.halftoneHardness = preset.hardness
        self.halftoneDotColor = preset.dotColor
        self.halftonePaperColor = preset.paperColor
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
        updateHalftoneParameters()
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

    private func updateHalftoneParameters() {
        guard let inst = storage.materialInstance else { return }
        "halftoneMode".withCString { FilamentBridge.setMaterialParameterInt(inst, $0, Int32(halftoneMode.rawValue)) }
        "halftoneTarget".withCString { FilamentBridge.setMaterialParameterInt(inst, $0, Int32(halftoneTarget.rawValue)) }
        "halftoneScale".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, halftoneScale) }
        "halftoneAngle".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, halftoneAngle) }
        "halftoneDotSize".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, halftoneDotSize) }
        "halftoneHardness".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, halftoneHardness) }
        "halftoneBlend".withCString { FilamentBridge.setMaterialParameterFloat(inst, $0, halftoneBlend) }
        "halftoneDotColor".withCString {
            FilamentBridge.setMaterialParameterFloat4(inst, $0, halftoneDotColor.r, halftoneDotColor.g, halftoneDotColor.b, halftoneDotColor.a)
        }
        "halftonePaperColor".withCString {
            FilamentBridge.setMaterialParameterFloat4(inst, $0, halftonePaperColor.r, halftonePaperColor.g, halftonePaperColor.b, halftonePaperColor.a)
        }
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
