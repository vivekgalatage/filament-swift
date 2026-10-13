import Foundation
import FilamentC

/// Tone-mapping operators exposed by Filament.
public enum FilamentToneMapping: UInt32, Sendable, CaseIterable {
    case linear = 0
    case acesLegacy = 1
    case aces = 2
    case filmic = 3
    case pbrNeutral = 4
    case agx = 5
    case gt7 = 6

    public var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .acesLegacy: return "ACES Legacy"
        case .aces: return "ACES"
        case .filmic: return "Filmic"
        case .pbrNeutral: return "PBR Neutral"
        case .agx: return "AgX"
        case .gt7: return "GT7"
        }
    }
}

/// Screen-space anti-aliasing mode.
public enum FilamentAntiAliasing: UInt32, Sendable, CaseIterable {
    case none = 0
    case fxaa = 1

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .fxaa: return "FXAA"
        }
    }
}

/// Ambient occlusion algorithm.
public enum FilamentOcclusionMode: UInt32, Sendable, CaseIterable {
    case ssao = 0
    case gtao = 1

    public var displayName: String {
        switch self {
        case .ssao: return "SSAO"
        case .gtao: return "GTAO"
        }
    }
}

/// Precision of the HDR color buffer.
public enum FilamentHDRQuality: UInt32, Sendable, CaseIterable {
    case low = 0
    case medium = 1
    case high = 2
    case ultra = 3

    public var displayName: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        case .ultra: return "Ultra"
        }
    }
}

/// A complete, `Sendable` description of how a model should be rendered.
///
/// Every field maps onto a Filament feature, so a host view only has to bind widgets to
/// this struct and hand it to ``FilamentPBRController``.
public struct FilamentPBRSettings: Sendable, Equatable {
    // Lighting
    /// Spherical-harmonic ambient light intensity, in Filament lux units.
    public var ambientIntensity: Float = 40_000
    /// Intensity of the key (sun-like) directional light.
    public var keyLightIntensity: Float = 120_000
    /// Intensity of the fill directional light.
    public var fillLightIntensity: Float = 60_000
    /// Whether the key light casts shadows.
    public var shadowsEnabled: Bool = true

    // Camera / tone mapping
    /// Linear exposure multiplier; 1.0 is Filament's default.
    public var exposure: Float = 1.0
    public var toneMapping: FilamentToneMapping = .aces
    public var contrast: Float = 1.0
    public var saturation: Float = 1.0
    public var vibrance: Float = 1.0
    /// White balance on the blue/yellow axis, between -1 (cool) and +1 (warm).
    ///
    /// Filament takes a normalized value, not Kelvin: -1.0 is roughly 50 000 K and +1.0 is
    /// roughly 1 000 K. `0` is neutral.
    public var whiteBalance: Float = 0.0
    /// White balance on the green/magenta axis, between -1 and +1.
    public var tint: Float = 0.0

    // Anti-aliasing
    public var antiAliasing: FilamentAntiAliasing = .fxaa
    /// MSAA sample count: 1, 2, 4 or 8.
    public var multiSampleCount: Int = 1
    public var dithering: Bool = true
    public var hdrQuality: FilamentHDRQuality = .high

    // Screen-space effects
    public var bloomEnabled: Bool = false
    public var bloomStrength: Float = 0.10
    public var bloomLevels: Int = 6

    public var vignetteEnabled: Bool = false
    public var vignetteStrength: Float = 0.5
    public var vignetteRoundness: Float = 0.5

    public var occlusionEnabled: Bool = false
    public var occlusionMode: FilamentOcclusionMode = .ssao
    public var occlusionIntensity: Float = 1.0
    public var occlusionRadius: Float = 0.3

    public var reflectionsEnabled: Bool = false
    public var reflectionMaxDistance: Float = 3.0

    public var depthOfFieldEnabled: Bool = false
    public var depthOfFieldStrength: Float = 1.0

    public init() {}

    /// A physically based, neutral starting point.
    public static let neutral = FilamentPBRSettings()
}

/// Applies ``FilamentPBRSettings`` to a ``FilamentEngine`` and keeps the engine's
/// color-grading LUT in sync.
///
/// Changing tone mapping, contrast, saturation, vibrance or white balance requires
/// rebuilding the LUT, so those fields are applied together and only when they change.
@MainActor
public final class FilamentPBRController {
    /// The settings currently applied.
    public private(set) var settings: FilamentPBRSettings

    private let engine: FilamentEngine
    private var keyLightId: UInt32?
    private var fillLightId: UInt32?
    private var appliedColorGrading: ColorGradingKey?

    /// Subset of settings that requires rebuilding the color-grading LUT.
    private struct ColorGradingKey: Equatable {
        var toneMapping: FilamentToneMapping
        var contrast: Float
        var saturation: Float
        var vibrance: Float
        var whiteBalance: Float
        var tint: Float
    }

    public init(engine: FilamentEngine, settings: FilamentPBRSettings = .neutral) {
        self.engine = engine
        self.settings = settings
        createLights()
        apply()
    }

    /// The engine this controller drives.
    public var engineRef: FilamentEngine { engine }

    /// Identifiers of the two directional lights created for the scene.
    public var lightIds: [UInt32?] { [keyLightId, fillLightId] }

    /// Applies a settings change. Only the fields that actually changed are pushed to
    /// Filament, so this is cheap enough to call from a slider callback.
    public func update(_ newSettings: FilamentPBRSettings) {
        let old = settings
        settings = newSettings

        if old.ambientIntensity != newSettings.ambientIntensity {
            engine.setAmbientLight(intensity: newSettings.ambientIntensity)
        }

        if old.shadowsEnabled != newSettings.shadowsEnabled,
           let id = keyLightId {
            engine.setLightShadows(id: id, enabled: newSettings.shadowsEnabled)
        }
        if old.keyLightIntensity != newSettings.keyLightIntensity,
           let id = keyLightId {
            engine.setLightIntensity(id: id, intensity: newSettings.keyLightIntensity)
        }
        if old.fillLightIntensity != newSettings.fillLightIntensity,
           let id = fillLightId {
            engine.setLightIntensity(id: id, intensity: newSettings.fillLightIntensity)
        }

        if old.exposure != newSettings.exposure {
            engine.setExposure(newSettings.exposure)
        }

        if colorGradingKey(for: old) != colorGradingKey(for: newSettings) {
            rebuildColorGrading()
        }

        if old.antiAliasing != newSettings.antiAliasing {
            engine.setAntiAliasing(newSettings.antiAliasing)
        }
        if old.multiSampleCount != newSettings.multiSampleCount {
            engine.setMultiSampleCount(newSettings.multiSampleCount)
        }
        if old.dithering != newSettings.dithering {
            engine.setDithering(newSettings.dithering)
        }
        if old.hdrQuality != newSettings.hdrQuality {
            engine.setHDRQuality(newSettings.hdrQuality)
        }

        if old.bloomEnabled != newSettings.bloomEnabled
            || old.bloomStrength != newSettings.bloomStrength
            || old.bloomLevels != newSettings.bloomLevels {
            engine.setBloom(enabled: newSettings.bloomEnabled,
                            strength: newSettings.bloomStrength,
                            levels: newSettings.bloomLevels)
        }

        if old.vignetteEnabled != newSettings.vignetteEnabled
            || old.vignetteStrength != newSettings.vignetteStrength
            || old.vignetteRoundness != newSettings.vignetteRoundness {
            engine.setVignette(enabled: newSettings.vignetteEnabled,
                               strength: newSettings.vignetteStrength,
                               roundness: newSettings.vignetteRoundness)
        }

        if old.occlusionEnabled != newSettings.occlusionEnabled
            || old.occlusionMode != newSettings.occlusionMode
            || old.occlusionIntensity != newSettings.occlusionIntensity
            || old.occlusionRadius != newSettings.occlusionRadius {
            engine.setAmbientOcclusion(enabled: newSettings.occlusionEnabled,
                                      mode: newSettings.occlusionMode,
                                      intensity: newSettings.occlusionIntensity,
                                      radius: newSettings.occlusionRadius)
        }

        if old.reflectionsEnabled != newSettings.reflectionsEnabled
            || old.reflectionMaxDistance != newSettings.reflectionMaxDistance {
            engine.setScreenSpaceReflections(enabled: newSettings.reflectionsEnabled,
                                             maxDistance: newSettings.reflectionMaxDistance)
        }

        if old.depthOfFieldEnabled != newSettings.depthOfFieldEnabled
            || old.depthOfFieldStrength != newSettings.depthOfFieldStrength {
            engine.setDepthOfField(enabled: newSettings.depthOfFieldEnabled,
                                   cocScale: newSettings.depthOfFieldStrength)
        }
    }

    /// Convenience for UI bindings: mutate and apply in one call.
    public func mutate(_ body: (inout FilamentPBRSettings) -> Void) {
        var next = settings
        body(&next)
        update(next)
    }

    /// Restores the neutral starting point.
    public func reset() {
        update(.neutral)
    }

    /// Rotates the key light, which is the quickest way to show off PBR shading.
    public func setKeyLightDirection(_ direction: (Float, Float, Float)) {
        guard let id = keyLightId else { return }
        engine.setLightDirection(id: id, direction: direction)
    }

    /// Tints the key light (useful for demonstrating colour temperature interaction).
    public func setKeyLightColor(_ color: (Float, Float, Float)) {
        guard let id = keyLightId else { return }
        engine.setLightColor(id: id, color: color)
    }

    /// Applies every setting. Called during initialization.
    public func apply() {
        let s = settings
        engine.setAmbientLight(intensity: s.ambientIntensity)
        engine.setExposure(s.exposure)
        engine.setAntiAliasing(s.antiAliasing)
        engine.setMultiSampleCount(s.multiSampleCount)
        engine.setDithering(s.dithering)
        engine.setHDRQuality(s.hdrQuality)
        engine.setBloom(enabled: s.bloomEnabled, strength: s.bloomStrength, levels: s.bloomLevels)
        engine.setVignette(enabled: s.vignetteEnabled,
                           strength: s.vignetteStrength,
                           roundness: s.vignetteRoundness)
        engine.setAmbientOcclusion(enabled: s.occlusionEnabled,
                                  mode: s.occlusionMode,
                                  intensity: s.occlusionIntensity,
                                  radius: s.occlusionRadius)
        engine.setScreenSpaceReflections(enabled: s.reflectionsEnabled,
                                         maxDistance: s.reflectionMaxDistance)
        engine.setDepthOfField(enabled: s.depthOfFieldEnabled, cocScale: s.depthOfFieldStrength)

        if let id = keyLightId {
            engine.setLightIntensity(id: id, intensity: s.keyLightIntensity)
            engine.setLightShadows(id: id, enabled: s.shadowsEnabled)
        }
        if let id = fillLightId {
            engine.setLightIntensity(id: id, intensity: s.fillLightIntensity)
        }

        rebuildColorGrading()
    }

    /// Removes the fill light; the key light is owned by the engine and destroyed with it.
    public func destroyFillLight() {
        guard let id = fillLightId else { return }
        engine.removeLight(id: id)
        fillLightId = nil
    }

    private func createLights() {
        keyLightId = engine.addDirectionalLight(
            direction: (0.4, -1.0, -0.6),
            color: (1.0, 0.98, 0.95),
            intensity: settings.keyLightIntensity
        )
        fillLightId = engine.addDirectionalLight(
            direction: (-0.5, -0.7, 0.6),
            color: (0.75, 0.85, 1.0),
            intensity: settings.fillLightIntensity
        )
    }

    private func colorGradingKey(for s: FilamentPBRSettings) -> ColorGradingKey {
        ColorGradingKey(toneMapping: s.toneMapping,
                        contrast: s.contrast,
                        saturation: s.saturation,
                        vibrance: s.vibrance,
                        whiteBalance: s.whiteBalance,
                        tint: s.tint)
    }

    private func rebuildColorGrading() {
        guard let eng = engine.engine, let view = engine.view else { return }
        let s = settings

        let grading = FilamentBridge.createColorGrading(
            eng,
            s.toneMapping.rawValue,
            s.contrast,
            s.saturation,
            s.vibrance,
            s.whiteBalance,
            s.tint
        )
        // Replacing before destroying keeps the view pointing at a live LUT at all times.
        FilamentBridge.setViewColorGrading(view, grading)
        engine.replaceColorGrading(grading)

        appliedColorGrading = colorGradingKey(for: s)
    }
}