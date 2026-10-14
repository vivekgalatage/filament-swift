import AppKit
import QuartzCore
import Filament
import FilamentAppKit

/// Manages the Filament 3D viewport, glTF model lifecycle, PBR controller, interactive
/// orbit/pan/zoom camera, and 60 Hz render loop for the macOS AppKit demo.
@MainActor
final class DemoSceneController {
    let filamentView: FilamentView
    let model: FilamentModel
    let outlineModel: FilamentModel
    let pbr: FilamentPBRController
    let camera: FilamentOrbitCamera

    private(set) var currentModelName: String?
    private(set) var currentModelURL: URL?
    private(set) var isAnimationPlaying: Bool = true

    public enum ShadingMode: Int, CaseIterable {
        case standardPBR = 0
        case toonCel = 1
        case toonWithOutline = 2
        case pbrWithOutline = 3
        case outlineOnly = 4
        case comicHalftone = 5
        case halftoneWithOutline = 6

        var title: String {
            switch self {
            case .standardPBR: return "Standard PBR"
            case .toonCel: return "Toon Cel (Cartoon)"
            case .toonWithOutline: return "Toon + Inked Outline"
            case .pbrWithOutline: return "PBR + Inked Outline"
            case .outlineOnly: return "Outline Only (Transparent Body)"
            case .comicHalftone: return "Comic Halftone (Pop-Art / Manga)"
            case .halftoneWithOutline: return "Halftone + Inked Outline"
            }
        }
    }

    public enum CanvasBackground: Int, CaseIterable {
        case darkStudio = 0
        case paperWhite = 1
        case blueprint = 2
        case neutralGray = 3

        var title: String {
            switch self {
            case .darkStudio: return "Dark Studio (Default)"
            case .paperWhite: return "Paper White (Print)"
            case .blueprint: return "Blueprint Blue"
            case .neutralGray: return "Neutral Gray"
            }
        }
    }

    private(set) var currentShadingMode: ShadingMode = .standardPBR
    private(set) var currentCanvasBackground: CanvasBackground = .darkStudio
    private(set) var currentOutlineColor: (r: Float, g: Float, b: Float) = (0.10, 0.08, 0.06)
    private(set) var toonMaterial: FilamentToonMaterial?
    private(set) var outlineMaterial: FilamentToonOutlineMaterial?
    private(set) var depthMaskMaterial: FilamentDepthMaskMaterial?
    public private(set) var overlayWindow: FilamentOverlayWindow?
    public private(set) var isOverlayEventPassthrough: Bool = false

    private var animationTime: Float = 0.0
    private var renderTimer: Timer?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()

    /// Invoked whenever the loaded model changes.
    var onModelStateChanged: (() -> Void)?
    /// Invoked whenever the floating overlay window is opened or closed.
    var onOverlayStateChanged: ((Bool) -> Void)?
    /// Invoked after each rendered frame with the instantaneous FPS and auto-orbit state.
    var onFrameRendered: ((Double, Bool) -> Void)?

    init(frame: NSRect) {
        let engine = FilamentEngine(backend: .metal, config: .largeModelPreset)
        filamentView = FilamentView(frame: frame, engine: engine)
        filamentView.autoresizingMask = [.width, .height]
        filamentView.isTransparent = false
        pbr = FilamentPBRController(engine: engine)
        model = FilamentModel(engine: engine)
        outlineModel = FilamentModel(engine: engine)
        camera = FilamentOrbitCamera(engine: engine)
        filamentView.orbitCamera = camera
    }

    // MARK: - Model loading

    func loadInitialModel() {
        if let first = ModelDiscovery.discoverModels().first {
            loadModel(from: first.url)
        } else {
            onModelStateChanged?()
        }
    }

    func loadModel(from url: URL) {
        let asset = ModelAsset(url: url)
        animationTime = 0.0

        do {
            try model.loadGlb(at: asset.url)
            currentModelName = asset.name
            currentModelURL = asset.url
            print("[AppKitDemo] Loaded model: \(asset.name) from \(asset.url.path)")

            // Also load duplicate geometry into outlineModel
            try outlineModel.loadGlb(at: asset.url)
            outlineModel.setPriority(6)
            model.setPriority(4)
            ensureToonMaterials()
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setRotation(radiansY: 0.0)
            if outlineModel.hasAnimations {
                outlineModel.selectAnimation(at: 0)
            }
        } catch {
            print("[AppKitDemo] Failed to load \(asset.url.path): \(error)")
            model.unload()
            outlineModel.unload()
            currentModelName = nil
            currentModelURL = nil
        }

        if model.hasAnimations {
            model.selectAnimation(at: 0)
            isAnimationPlaying = model.activeAnimationDuration > 0.001
        } else {
            model.selectAnimation(at: nil)
            isAnimationPlaying = false
        }

        if model.hasMorphTargets {
            print("[AppKitDemo] Detected \(model.morphTargets.count) morph target(s)")
        }

        model.setRotation(radiansY: 0.0)

        applyCurrentShadingMode()

        if let overlay = overlayWindow, let url = currentModelURL {
            try? overlay.loadModel(from: url)
            overlay.setShadingMode(index: currentShadingMode.rawValue)
        }

        onModelStateChanged?()
    }

    // MARK: - Toon / Cel Shading Controls

    func setShadingMode(_ mode: ShadingMode) {
        currentShadingMode = mode
        applyCurrentShadingMode()
        overlayWindow?.setShadingMode(index: mode.rawValue)
    }

    private func applyCurrentShadingMode() {
        guard let url = currentModelURL else { return }
        ensureToonMaterials()

        switch currentShadingMode {
        case .standardPBR:
            outlineModel.setVisible(false)
            do {
                try model.loadGlb(at: url)
                model.setRotation(radiansY: 0.0)
                model.setPriority(4)
                if model.hasAnimations {
                    model.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            } catch {
                print("[AppKitDemo] Failed to reload PBR model: \(error)")
            }

        case .toonCel:
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                model.applyToonMaterial(toon)
            }

        case .toonWithOutline:
            model.setPriority(4)
            if let toon = toonMaterial {
                model.applyToonMaterial(toon)
            }
            if !outlineModel.isLoaded {
                try? outlineModel.loadGlb(at: url)
                outlineModel.setRotation(radiansY: 0.0)
                if outlineModel.hasAnimations {
                    outlineModel.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case .pbrWithOutline:
            do {
                try model.loadGlb(at: url)
                model.setRotation(radiansY: 0.0)
                model.setPriority(4)
                if model.hasAnimations {
                    model.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            } catch {
                print("[AppKitDemo] Failed to reload PBR model: \(error)")
            }
            if !outlineModel.isLoaded {
                try? outlineModel.loadGlb(at: url)
                outlineModel.setRotation(radiansY: 0.0)
                if outlineModel.hasAnimations {
                    outlineModel.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case .outlineOnly:
            model.setPriority(4)
            if let mask = depthMaskMaterial {
                model.applyDepthMaskMaterial(mask)
            }
            model.setVisible(true)
            if !outlineModel.isLoaded {
                try? outlineModel.loadGlb(at: url)
                outlineModel.setRotation(radiansY: 0.0)
                if outlineModel.hasAnimations {
                    outlineModel.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case .comicHalftone:
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode == .disabled {
                    toon.halftoneMode = .screenDots
                }
                model.applyToonMaterial(toon)
            }

        case .halftoneWithOutline:
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode == .disabled {
                    toon.halftoneMode = .screenDots
                }
                model.applyToonMaterial(toon)
            }
            if !outlineModel.isLoaded {
                try? outlineModel.loadGlb(at: url)
                outlineModel.setRotation(radiansY: 0.0)
                if outlineModel.hasAnimations {
                    outlineModel.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)
        }
    }

    private func ensureToonMaterials() {
        guard toonMaterial == nil || outlineMaterial == nil || depthMaskMaterial == nil else { return }
        let engine = filamentView.engine
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = sourceDir.deletingLastPathComponent().deletingLastPathComponent()
        let candidateDirs = [
            repoRoot.appendingPathComponent("Resources/Materials", isDirectory: true),
            repoRoot.appendingPathComponent("Examples/Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "Examples/Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "../Resources/Materials", isDirectory: true),
        ]

        for dir in candidateDirs {
            let celURL = dir.appendingPathComponent("ToonCel.filamat")
            let outURL = dir.appendingPathComponent("ToonOutline.filamat")
            let maskURL = dir.appendingPathComponent("DepthMask.filamat")
            if FileManager.default.fileExists(atPath: celURL.path) && toonMaterial == nil {
                do {
                    toonMaterial = try engine.createToonMaterial(from: celURL)
                    toonMaterial?.syncWithDirectionalLight(direction: (0.2, -1.0, -0.6), color: (1.0, 0.98, 0.95))
                    print("[AppKitDemo] Loaded ToonCel material from \(celURL.path)")
                } catch {
                    print("[AppKitDemo] Error loading ToonCel: \(error)")
                }
            }
            if FileManager.default.fileExists(atPath: outURL.path) && outlineMaterial == nil {
                do {
                    let out = try engine.createOutlineMaterial(from: outURL)
                    out.outlineColor = (currentOutlineColor.r, currentOutlineColor.g, currentOutlineColor.b, 1.0)
                    outlineMaterial = out
                    print("[AppKitDemo] Loaded ToonOutline material from \(outURL.path)")
                } catch {
                    print("[AppKitDemo] Error loading ToonOutline: \(error)")
                }
            }
            if FileManager.default.fileExists(atPath: maskURL.path) && depthMaskMaterial == nil {
                do {
                    depthMaskMaterial = try engine.createDepthMaskMaterial(from: maskURL)
                    print("[AppKitDemo] Loaded DepthMask material from \(maskURL.path)")
                } catch {
                    print("[AppKitDemo] Error loading DepthMask: \(error)")
                }
            }
        }
    }

    func setCanvasBackground(_ bg: CanvasBackground) {
        currentCanvasBackground = bg
        switch bg {
        case .darkStudio:
            filamentView.engine.setClearColor(r: 0.12, g: 0.13, b: 0.16, a: 1.0)
        case .paperWhite:
            filamentView.engine.setClearColor(r: 0.98, g: 0.98, b: 0.98, a: 1.0)
        case .blueprint:
            filamentView.engine.setClearColor(r: 0.10, g: 0.22, b: 0.38, a: 1.0)
        case .neutralGray:
            filamentView.engine.setClearColor(r: 0.50, g: 0.50, b: 0.50, a: 1.0)
        }
    }

    func setToonShadowThreshold(_ value: Float) {
        ensureToonMaterials()
        toonMaterial?.shadowThreshold = value
    }

    func setToonHighlightThreshold(_ value: Float) {
        ensureToonMaterials()
        toonMaterial?.highlightThreshold = value
    }

    func setToonEdgeFeather(_ value: Float) {
        ensureToonMaterials()
        toonMaterial?.edgeFeather = value
    }

    func setOutlineThickness(_ value: Float) {
        ensureToonMaterials()
        outlineMaterial?.outlineThickness = value
        overlayWindow?.setOutlineThickness(value)
    }

    func setToonBaseColor(r: Float, g: Float, b: Float) {
        ensureToonMaterials()
        toonMaterial?.baseColor = (r, g, b, 1.0)
    }

    func setOutlineColor(r: Float, g: Float, b: Float) {
        currentOutlineColor = (r, g, b)
        ensureToonMaterials()
        outlineMaterial?.outlineColor = (r, g, b, 1.0)
        overlayWindow?.setOutlineColor(r: r, g: g, b: b, a: 1.0)
    }

    func setOutlineGradientMode(_ mode: FilamentToonOutlineMaterial.GradientMode) {
        ensureToonMaterials()
        outlineMaterial?.gradientMode = mode
        overlayWindow?.setOutlineGradientMode(mode)
    }

    func setOutlineStops(_ stops: [FilamentToonOutlineMaterial.GradientStop]) {
        ensureToonMaterials()
        outlineMaterial?.stops = stops
        overlayWindow?.setOutlineStops(stops)
    }

    @discardableResult
    func addOutlineStop(color: (Float, Float, Float, Float)? = nil, position: Float? = nil) -> Bool {
        ensureToonMaterials()
        guard let out = outlineMaterial else { return false }
        let ok = out.addStop(color: color, position: position)
        if ok {
            overlayWindow?.setOutlineStops(out.stops)
        }
        return ok
    }

    @discardableResult
    func removeOutlineStop(at index: Int) -> Bool {
        ensureToonMaterials()
        guard let out = outlineMaterial else { return false }
        let ok = out.removeStop(at: index)
        if ok {
            overlayWindow?.setOutlineStops(out.stops)
        }
        return ok
    }

    func updateOutlineStop(at index: Int, r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureToonMaterials()
        outlineMaterial?.setStopColor(at: index, r: r, g: g, b: b, a: a)
        if let stops = outlineMaterial?.stops {
            overlayWindow?.setOutlineStops(stops)
        }
    }

    func updateOutlineStopPosition(at index: Int, position: Float) {
        ensureToonMaterials()
        outlineMaterial?.setStopPosition(at: index, position: position)
        if let stops = outlineMaterial?.stops {
            overlayWindow?.setOutlineStops(stops)
        }
    }

    func randomizeOutlineColors() {
        ensureToonMaterials()
        outlineMaterial?.randomizeColors()
        if let stops = outlineMaterial?.stops {
            overlayWindow?.setOutlineStops(stops)
        }
    }

    func setOutlineGradientScale(_ scale: Float) {
        ensureToonMaterials()
        outlineMaterial?.gradientScale = scale
        overlayWindow?.setOutlineGradientScale(scale)
    }

    func setOutlineFlowSpeed(_ speed: Float) {
        ensureToonMaterials()
        outlineMaterial?.flowAnimationSpeed = speed
        overlayWindow?.setOutlineFlowSpeed(speed)
    }

    func setOutlineNoiseScale(_ noise: Float) {
        ensureToonMaterials()
        outlineMaterial?.noiseScale = noise
        overlayWindow?.setOutlineNoiseScale(noise)
    }

    // MARK: - Morph Target controls

    func setMorphWeight(at index: Int, weight: Float) {
        model.setMorphWeight(at: index, weight: weight)
        if outlineModel.isLoaded {
            outlineModel.setMorphWeight(at: index, weight: weight)
        }
    }

    func setMorphWeight(named name: String, weight: Float) {
        model.setMorphWeight(named: name, weight: weight)
        if outlineModel.isLoaded {
            outlineModel.setMorphWeight(named: name, weight: weight)
        }
    }

    func resetMorphWeights() {
        model.resetMorphWeights()
        if outlineModel.isLoaded {
            outlineModel.resetMorphWeights()
        }
    }

    // MARK: - Animation & camera controls

    func selectAnimation(at index: Int) {
        guard index >= 0 else { return }
        model.selectAnimation(at: index)
        if outlineModel.isLoaded {
            outlineModel.selectAnimation(at: index)
        }
        animationTime = 0.0
        isAnimationPlaying = model.activeAnimationDuration > 0.001
        print("[AppKitDemo] Selected animation index: \(index), duration: \(model.activeAnimationDuration)s")
    }

    @discardableResult
    func toggleAnimationPlayback() -> Bool {
        isAnimationPlaying.toggle()
        return isAnimationPlaying
    }

    @discardableResult
    func toggleAutoOrbit() -> Bool {
        camera.isAutoOrbiting.toggle()
        return camera.isAutoOrbiting
    }

    func resetCamera() {
        camera.reset()
    }

    @discardableResult
    func toggleTransparency(in window: NSWindow) -> Bool {
        let newTransparency = !filamentView.isTransparent
        filamentView.isTransparent = newTransparency
        window.isOpaque = !newTransparency
        window.backgroundColor = newTransparency ? .clear : .windowBackgroundColor
        return newTransparency
    }

    @discardableResult
    func toggleOverlayWindow() -> Bool {
        if let existing = overlayWindow {
            existing.close()
            overlayWindow = nil
            onOverlayStateChanged?(false)
            return false
        }

        let overlay = FilamentOverlayWindow(width: 440, height: 560)
        overlay.onClose = { [weak self] in
            self?.overlayWindow = nil
            self?.onOverlayStateChanged?(false)
        }
        if let url = currentModelURL {
            try? overlay.loadModel(from: url)
        }
        overlay.setShadingMode(index: currentShadingMode.rawValue)
        overlay.setOutlineColor(r: currentOutlineColor.r, g: currentOutlineColor.g, b: currentOutlineColor.b, a: 1.0)
        if let outline = outlineMaterial {
            overlay.setOutlineThickness(outline.outlineThickness)
            overlay.setOutlineGradientMode(outline.gradientMode)
            overlay.setOutlineStops(outline.stops)
            overlay.setOutlineGradientScale(outline.gradientScale)
            overlay.setOutlineFlowSpeed(outline.flowAnimationSpeed)
            overlay.setOutlineNoiseScale(outline.noiseScale)
        }
        if let toon = toonMaterial {
            overlay.setHalftoneMode(toon.halftoneMode)
            overlay.setHalftoneTarget(toon.halftoneTarget)
            overlay.setHalftoneScale(toon.halftoneScale)
            overlay.setHalftoneAngle(toon.halftoneAngle)
            overlay.setHalftoneDotSize(toon.halftoneDotSize)
            overlay.setHalftoneHardness(toon.halftoneHardness)
            overlay.setHalftoneBlend(toon.halftoneBlend)
            overlay.setHalftoneDotColor(r: toon.halftoneDotColor.r, g: toon.halftoneDotColor.g, b: toon.halftoneDotColor.b, a: toon.halftoneDotColor.a)
            overlay.setHalftonePaperColor(r: toon.halftonePaperColor.r, g: toon.halftonePaperColor.g, b: toon.halftonePaperColor.b, a: toon.halftonePaperColor.a)
        }
        overlay.isClickThrough = isOverlayEventPassthrough
        overlay.show()
        overlayWindow = overlay
        onOverlayStateChanged?(true)
        return true
    }

    func setOverlayEventPassthrough(_ passthrough: Bool) {
        isOverlayEventPassthrough = passthrough
        overlayWindow?.isClickThrough = passthrough
    }

    @discardableResult
    func toggleOverlayEventPassthrough() -> Bool {
        let newValue = !isOverlayEventPassthrough
        setOverlayEventPassthrough(newValue)
        return newValue
    }

    // MARK: - Halftone & Screentone controls

    func setHalftoneMode(_ mode: FilamentToonMaterial.HalftoneMode) {
        ensureToonMaterials()
        toonMaterial?.halftoneMode = mode
        overlayWindow?.setHalftoneMode(mode)
    }

    func setHalftoneTarget(_ target: FilamentToonMaterial.HalftoneTarget) {
        ensureToonMaterials()
        toonMaterial?.halftoneTarget = target
        overlayWindow?.setHalftoneTarget(target)
    }

    func setHalftoneScale(_ scale: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneScale = scale
        overlayWindow?.setHalftoneScale(scale)
    }

    func setHalftoneAngle(_ angle: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneAngle = angle
        overlayWindow?.setHalftoneAngle(angle)
    }

    func setHalftoneDotSize(_ size: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneDotSize = size
        overlayWindow?.setHalftoneDotSize(size)
    }

    func setHalftoneHardness(_ hardness: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneHardness = hardness
        overlayWindow?.setHalftoneHardness(hardness)
    }

    func setHalftoneBlend(_ blend: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneBlend = blend
        overlayWindow?.setHalftoneBlend(blend)
    }

    func setHalftoneDotColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureToonMaterials()
        toonMaterial?.halftoneDotColor = (r, g, b, a)
        overlayWindow?.setHalftoneDotColor(r: r, g: g, b: b, a: a)
    }

    func setHalftonePaperColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureToonMaterials()
        toonMaterial?.halftonePaperColor = (r, g, b, a)
        overlayWindow?.setHalftonePaperColor(r: r, g: g, b: b, a: a)
    }

    func applyHalftonePreset(_ preset: FilamentToonMaterial.HalftonePreset) {
        ensureToonMaterials()
        toonMaterial?.applyPreset(preset)
        overlayWindow?.applyHalftonePreset(preset)
    }

    // MARK: - Demo Mode (Product Video Reel)

    public enum DemoCameraMove: Sendable {
        /// Crash zoom: High-velocity spring slam-in from startDistance to targetDistance
        case crashZoomIn(startDistance: Double, targetDistance: Double)
        /// Whip-pan snap: Rapid angular whip rotation that snaps into the hero angle with spring overshoot
        case whipPanSnap(startOffsetAzimuth: Double, startDistance: Double, targetDistance: Double)
        /// True Vertigo Dolly Zoom: Camera dollies in/out while dynamically counter-warping FOV
        case vertigoDollyZoom(fromDistance: Double, toDistance: Double, fromFov: Double, toFov: Double)
        /// Macro Punch: Crash zooms into extreme close-up detail, holds, then snappy pull-back to wide
        case macroPunch(macroDistance: Double, returnDistance: Double)
        /// Kinetic Arc Sweep: High-speed curved sweep around the model with dynamic elevation
        case dynamicArc(speed: Double, heightSway: Double)
        /// Elastic Snap: Instant scale punch with spring bounce
        case elasticSnap(punchDistance: Double, settleDistance: Double)
    }

    public struct DemoStep: Sendable {
        public let title: String
        public let subtitle: String
        public let mode: ShadingMode
        public let outlineMode: FilamentToonOutlineMaterial.GradientMode?
        public let outlineSpeed: Float?
        public let halftonePreset: FilamentToonMaterial.HalftonePreset?
        public let duration: TimeInterval
        public let initialAzimuth: Double
        public let initialElevation: Double
        public let initialDistance: Double
        public let cameraMove: DemoCameraMove
    }

    public private(set) var isDemoModeActive: Bool = false
    public private(set) var isDemoTurntableEnabled: Bool = false
    private var demoTimer: Timer?
    private var demoStepIndex: Int = 0

    // Dynamic camera choreography
    private var stepStartTime: Double = 0.0
    private var currentStepDuration: Double = 2.0
    private var currentStepBaseAzimuth: Double = 0.0
    private var currentStepBaseElevation: Double = 0.12
    private var currentStepBaseDistance: Double = 10.5
    private var currentCameraMove: DemoCameraMove = .crashZoomIn(startDistance: 13.5, targetDistance: 9.2)

    // Saved state for restoring when demo mode exits
    private var savedTransparency: Bool = false
    private var savedWindowOpaque: Bool = true
    private var savedWindowBgColor: NSColor?
    private var savedCanvasBackground: CanvasBackground = .darkStudio
    private var savedShadingMode: ShadingMode = .standardPBR
    private var savedAutoOrbit: Bool = false
    private var savedAzimuth: Double = 0.0
    private var savedElevation: Double = 0.25
    private var savedDistance: Double = 3.2
    private var savedTarget: (x: Double, y: Double, z: Double) = (0.0, 0.0, 0.0)
    private var savedAnimationPlaying: Bool = true

    public var onDemoTurntableToggled: ((Bool) -> Void)?
    public var onDemoModeStateChanged: ((Bool) -> Void)?
    public var onDemoModeStepChanged: ((Int, Int, String, String) -> Void)?

    public static let demoSteps: [DemoStep] = [
        DemoStep(
            title: "Standard PBR",
            subtitle: "Physically-Based Rendering (Metal / Vulkan)",
            mode: .standardPBR,
            outlineMode: nil,
            outlineSpeed: nil,
            halftonePreset: nil,
            duration: 2.2,
            initialAzimuth: 0.0,
            initialElevation: 0.12,
            initialDistance: 10.5,
            cameraMove: .crashZoomIn(startDistance: 13.5, targetDistance: 9.2)
        ),
        DemoStep(
            title: "Toon Cel (Cartoon)",
            subtitle: "2-Band Stepped Lighting & Smooth Edge Feathers",
            mode: .toonCel,
            outlineMode: nil,
            outlineSpeed: nil,
            halftonePreset: nil,
            duration: 1.4,
            initialAzimuth: 0.48,
            initialElevation: 0.18,
            initialDistance: 8.2,
            cameraMove: .whipPanSnap(startOffsetAzimuth: 0.70, startDistance: 10.8, targetDistance: 8.0)
        ),
        DemoStep(
            title: "Toon + Inked Outline",
            subtitle: "Inverted Hull Normal Extrusion & Front-Face Culling",
            mode: .toonWithOutline,
            outlineMode: .solid,
            outlineSpeed: 0.0,
            halftonePreset: nil,
            duration: 1.8,
            initialAzimuth: -0.52,
            initialElevation: -0.08,
            initialDistance: 7.6,
            cameraMove: .crashZoomIn(startDistance: 11.2, targetDistance: 7.2)
        ),
        DemoStep(
            title: "PBR + Inked Outline",
            subtitle: "Photorealistic Textures with Graphic Ink Outlines",
            mode: .pbrWithOutline,
            outlineMode: .solid,
            outlineSpeed: 0.0,
            halftonePreset: nil,
            duration: 1.3,
            initialAzimuth: 0.78,
            initialElevation: 0.26,
            initialDistance: 8.6,
            cameraMove: .elasticSnap(punchDistance: 6.4, settleDistance: 8.4)
        ),
        DemoStep(
            title: "Outline Only (Transparent Body)",
            subtitle: "Zero-Alpha Depth Mask with Inked Wireframe Hull",
            mode: .outlineOnly,
            outlineMode: .solid,
            outlineSpeed: 0.0,
            halftonePreset: nil,
            duration: 2.4,
            initialAzimuth: 0.18,
            initialElevation: 0.05,
            initialDistance: 4.8,
            cameraMove: .macroPunch(macroDistance: 4.5, returnDistance: 7.6)
        ),
        DemoStep(
            title: "Comic Halftone (Spider-Verse Pop-Art)",
            subtitle: "Screen-Space Ben-Day Dots & CMYK Separation",
            mode: .comicHalftone,
            outlineMode: nil,
            outlineSpeed: nil,
            halftonePreset: FilamentToonMaterial.spiderVersePreset,
            duration: 2.2,
            initialAzimuth: -0.42,
            initialElevation: 0.16,
            initialDistance: 9.8,
            cameraMove: .vertigoDollyZoom(fromDistance: 10.2, toDistance: 5.8, fromFov: 32.0, toFov: 62.0)
        ),
        DemoStep(
            title: "Manga Screentone + Outline",
            subtitle: "Surface UV Screentone Dots on Shadow Transitions",
            mode: .halftoneWithOutline,
            outlineMode: .solid,
            outlineSpeed: 0.0,
            halftonePreset: FilamentToonMaterial.mangaScreentonePreset,
            duration: 1.4,
            initialAzimuth: 0.65,
            initialElevation: 0.32,
            initialDistance: 7.4,
            cameraMove: .whipPanSnap(startOffsetAzimuth: -0.65, startDistance: 10.5, targetDistance: 7.2)
        ),
        DemoStep(
            title: "VIBGYOR Rainbow Spectrum",
            subtitle: "Dynamic Multi-Color Animated Rainbow Outline",
            mode: .toonWithOutline,
            outlineMode: .rainbow,
            outlineSpeed: 1.8,
            halftonePreset: nil,
            duration: 2.8,
            initialAzimuth: -0.75,
            initialElevation: 0.12,
            initialDistance: 8.5,
            cameraMove: .crashZoomIn(startDistance: 12.0, targetDistance: 8.2)
        ),
        DemoStep(
            title: "Random Multi-Color Facets",
            subtitle: "Procedural Randomized Facet Outline Pattern",
            mode: .toonWithOutline,
            outlineMode: .randomFacets,
            outlineSpeed: 0.0,
            halftonePreset: nil,
            duration: 1.8,
            initialAzimuth: 0.38,
            initialElevation: 0.20,
            initialDistance: 8.8,
            cameraMove: .dynamicArc(speed: 0.35, heightSway: 0.08)
        ),
    ]

    private static func springEaseOut(_ t: Double) -> Double {
        let x = min(max(t, 0.0), 1.0)
        return 1.0 - pow(2.0, -10.0 * x) * cos(x * .pi * 2.5)
    }

    private static func easeOutExpo(_ t: Double) -> Double {
        let x = min(max(t, 0.0), 1.0)
        return x == 1.0 ? 1.0 : 1.0 - pow(2.0, -10.0 * x)
    }

    private static func smoothHermite(_ t: Double) -> Double {
        let x = min(max(t, 0.0), 1.0)
        return x * x * (3.0 - 2.0 * x)
    }

    @discardableResult
    func toggleDemoTurntable() -> Bool {
        guard isDemoModeActive else { return false }
        isDemoTurntableEnabled.toggle()
        camera.isAutoOrbiting = isDemoTurntableEnabled
        camera.lockAutoOrbit = isDemoTurntableEnabled
        onDemoTurntableToggled?(isDemoTurntableEnabled)
        return isDemoTurntableEnabled
    }

    @discardableResult
    func toggleDemoMode(in window: NSWindow) -> Bool {
        if isDemoModeActive {
            stopDemoMode(in: window)
            return false
        } else {
            startDemoMode(in: window)
            return true
        }
    }

    func startDemoMode(in window: NSWindow) {
        guard !isDemoModeActive else { return }
        isDemoModeActive = true

        // Save state
        savedTransparency = filamentView.isTransparent
        savedWindowOpaque = window.isOpaque
        savedWindowBgColor = window.backgroundColor
        savedCanvasBackground = currentCanvasBackground
        savedShadingMode = currentShadingMode
        savedAutoOrbit = camera.isAutoOrbiting
        savedAzimuth = camera.azimuth
        savedElevation = camera.elevation
        savedDistance = camera.distance
        savedTarget = camera.target
        savedAnimationPlaying = isAnimationPlaying

        // 1. Center model at ~30% size in full window
        camera.setPose(azimuth: 0.0, elevation: 0.12, distance: 13.5, target: (0.0, 0.0, 0.0))
        isDemoTurntableEnabled = false
        camera.isAutoOrbiting = false
        camera.lockAutoOrbit = false

        stepStartTime = CACurrentMediaTime()
        currentStepDuration = 2.2
        currentStepBaseAzimuth = 0.0
        currentStepBaseElevation = 0.12
        currentStepBaseDistance = 10.5
        currentCameraMove = .crashZoomIn(startDistance: 13.5, targetDistance: 9.2)

        if model.hasAnimations {
            isAnimationPlaying = true
            model.selectAnimation(at: 0)
            if outlineModel.isLoaded {
                outlineModel.selectAnimation(at: 0)
            }
        }

        // 2. Full window with black background, alpha off
        filamentView.isTransparent = false
        window.isOpaque = true
        window.backgroundColor = .black
        filamentView.engine.setClearColor(r: 0.0, g: 0.0, b: 0.0, a: 1.0)

        // Set initial mode: Standard PBR
        demoStepIndex = 0
        setShadingMode(.standardPBR)

        onDemoModeStateChanged?(true)
        let total = Self.demoSteps.count
        onDemoModeStepChanged?(0, total, "Standard PBR", "Full Window · Black Background")

        // 3. After ~1s, turn alpha on
        demoTimer?.invalidate()
        let alphaTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.isDemoModeActive else { return }
                self.turnAlphaOnInDemo(window: window)
            }
        }
        RunLoop.main.add(alphaTimer, forMode: .common)
        demoTimer = alphaTimer
    }

    private func turnAlphaOnInDemo(window: NSWindow) {
        filamentView.isTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        filamentView.engine.setClearColor(r: 0.0, g: 0.0, b: 0.0, a: 0.0)

        // Trigger crash zoom slam on alpha drop
        stepStartTime = CACurrentMediaTime()
        currentStepDuration = 1.2
        currentCameraMove = .crashZoomIn(startDistance: 12.0, targetDistance: 8.8)

        let total = Self.demoSteps.count
        onDemoModeStepChanged?(0, total, "Standard PBR", "Per-Pixel Alpha Transparent Mode Active")

        // Hold initial alpha step for 1.2s, then advance to step 1
        demoStepIndex = 1
        demoTimer?.invalidate()
        let stepTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.isDemoModeActive else { return }
                self.advanceDemoStep(window: window)
            }
        }
        RunLoop.main.add(stepTimer, forMode: .common)
        demoTimer = stepTimer
    }

    private func advanceDemoStep(window: NSWindow) {
        let total = Self.demoSteps.count
        let step = Self.demoSteps[demoStepIndex]

        setShadingMode(step.mode)

        if let gradMode = step.outlineMode {
            setOutlineGradientMode(gradMode)
        }
        if let speed = step.outlineSpeed {
            setOutlineFlowSpeed(speed)
        } else {
            setOutlineFlowSpeed(0.0)
        }
        if let preset = step.halftonePreset {
            applyHalftonePreset(preset)
        }

        stepStartTime = CACurrentMediaTime()
        currentStepDuration = step.duration
        currentStepBaseAzimuth = step.initialAzimuth
        currentStepBaseElevation = step.initialElevation
        currentStepBaseDistance = step.initialDistance
        currentCameraMove = step.cameraMove

        if !isDemoTurntableEnabled {
            camera.setPose(
                azimuth: step.initialAzimuth,
                elevation: step.initialElevation,
                distance: step.initialDistance,
                target: (0.0, 0.0, 0.0)
            )
        } else {
            camera.setPose(
                elevation: step.initialElevation,
                distance: step.initialDistance,
                target: (0.0, 0.0, 0.0)
            )
        }

        onDemoModeStepChanged?(demoStepIndex, total, step.title, step.subtitle)
        let curDuration = step.duration
        demoStepIndex = (demoStepIndex + 1) % total

        // Schedule next cut with this step's dynamic duration
        demoTimer?.invalidate()
        let nextTimer = Timer.scheduledTimer(withTimeInterval: curDuration, repeats: false) { [weak self, weak window] _ in
            MainActor.assumeIsolated {
                guard let self, let window, self.isDemoModeActive else { return }
                self.advanceDemoStep(window: window)
            }
        }
        RunLoop.main.add(nextTimer, forMode: .common)
        demoTimer = nextTimer
    }

    private func updateDemoCamera(dt: Float) {
        guard isDemoModeActive else { return }

        let elapsed = CACurrentMediaTime() - stepStartTime
        let duration = max(0.5, currentStepDuration)
        let normalizedProgress = min(1.0, elapsed / duration)

        // Subtle outline pulse on cut impact (first 0.15s)
        if elapsed < 0.15 {
            let pulseProgress = elapsed / 0.15
            let pulseScale = Float(1.0 + sin(pulseProgress * .pi) * 0.4)
            outlineMaterial?.outlineThickness = 0.02 * pulseScale
        } else {
            outlineMaterial?.outlineThickness = 0.02
        }

        if isDemoTurntableEnabled {
            // Turntable is active (R key pressed): auto-orbit handles 360 spin
            return
        }

        let aspect: Double
        if filamentView.bounds.height > 0 {
            aspect = Double(filamentView.bounds.width / filamentView.bounds.height)
        } else {
            aspect = 1.77
        }

        switch currentCameraMove {
        case .crashZoomIn(let startDist, let targetDist):
            // Fast spring rush in first 0.35s, then subtle breathing
            let spring = Self.springEaseOut(min(1.0, elapsed / 0.38))
            let curDist = startDist + (targetDist - startDist) * spring
            let breath = sin(elapsed * 2.0) * 0.015
            camera.setPose(
                azimuth: currentStepBaseAzimuth + breath,
                elevation: currentStepBaseElevation,
                distance: curDist
            )
            filamentView.engine.setCameraProjection(fovInDegrees: 45.0, aspect: aspect)

        case .whipPanSnap(let startOffsetAz, let startDist, let targetDist):
            // Whip pan rotation and crash punch in first 0.30s
            let spring = Self.springEaseOut(min(1.0, elapsed / 0.35))
            let curAz = (currentStepBaseAzimuth + startOffsetAz) - startOffsetAz * spring
            let curDist = startDist + (targetDist - startDist) * spring
            let drift = elapsed > 0.35 ? (elapsed - 0.35) * 0.08 : 0.0
            camera.setPose(
                azimuth: curAz + drift,
                elevation: currentStepBaseElevation,
                distance: curDist
            )
            filamentView.engine.setCameraProjection(fovInDegrees: 45.0, aspect: aspect)

        case .vertigoDollyZoom(let fromDist, let toDist, let fromFov, let toFov):
            // True Dolly Zoom: Dolly in/out while dynamically counter-warping FOV
            let hermite = Self.smoothHermite(normalizedProgress)
            let curDist = fromDist + (toDist - fromDist) * hermite
            let curFov = fromFov + (toFov - fromFov) * hermite
            let sway = sin(elapsed * 1.5) * 0.02
            camera.setPose(
                azimuth: currentStepBaseAzimuth + sway,
                elevation: currentStepBaseElevation,
                distance: curDist
            )
            filamentView.engine.setCameraProjection(fovInDegrees: curFov, aspect: aspect)

        case .macroPunch(let macroDist, let returnDist):
            // Crash into macro detail, hold, then snap back
            let curDist: Double
            if normalizedProgress < 0.40 {
                // Slam into macro
                let spring = Self.springEaseOut(normalizedProgress / 0.40)
                curDist = currentStepBaseDistance + (macroDist - currentStepBaseDistance) * spring
            } else if normalizedProgress < 0.70 {
                // Hold macro with micro sway
                let micro = sin(elapsed * 2.5) * 0.04
                curDist = macroDist + micro
            } else {
                // Snap pull-back to wide
                let returnProgress = (normalizedProgress - 0.70) / 0.30
                let spring = Self.springEaseOut(returnProgress)
                curDist = macroDist + (returnDist - macroDist) * spring
            }
            let sway = sin(elapsed * 1.8) * 0.02
            camera.setPose(
                azimuth: currentStepBaseAzimuth + sway,
                elevation: currentStepBaseElevation,
                distance: curDist
            )
            filamentView.engine.setCameraProjection(fovInDegrees: 45.0, aspect: aspect)

        case .dynamicArc(let speed, let heightSway):
            // High-speed curved tracking arc with dynamic tilt
            let curAz = currentStepBaseAzimuth + elapsed * speed
            let curEl = currentStepBaseElevation + sin(elapsed * speed * 2.5) * heightSway
            let curDist = currentStepBaseDistance + sin(elapsed * speed * 1.8) * 0.25
            camera.setPose(
                azimuth: curAz,
                elevation: curEl,
                distance: curDist
            )
            filamentView.engine.setCameraProjection(fovInDegrees: 45.0, aspect: aspect)

        case .elasticSnap(let punchDist, let settleDist):
            // Quick punch-in and snap rebound
            let spring = Self.springEaseOut(min(1.0, elapsed / 0.30))
            let curDist = punchDist + (settleDist - punchDist) * spring
            let micro = sin(elapsed * 1.8) * 0.015
            camera.setPose(
                azimuth: currentStepBaseAzimuth + micro,
                elevation: currentStepBaseElevation,
                distance: curDist
            )
            filamentView.engine.setCameraProjection(fovInDegrees: 45.0, aspect: aspect)
        }
    }

    func stopDemoMode(in window: NSWindow) {
        guard isDemoModeActive else { return }
        isDemoModeActive = false
        isDemoTurntableEnabled = false

        demoTimer?.invalidate()
        demoTimer = nil

        // Restore FOV to 45 degrees
        let aspect = filamentView.bounds.height > 0 ? Double(filamentView.bounds.width / filamentView.bounds.height) : 1.77
        filamentView.engine.setCameraProjection(fovInDegrees: 45.0, aspect: aspect)

        // Restore camera
        camera.lockAutoOrbit = false
        camera.isAutoOrbiting = savedAutoOrbit
        camera.setPose(
            azimuth: savedAzimuth,
            elevation: savedElevation,
            distance: savedDistance,
            target: savedTarget
        )

        // Restore transparency & background
        filamentView.isTransparent = savedTransparency
        window.isOpaque = savedWindowOpaque
        window.backgroundColor = savedWindowBgColor ?? .windowBackgroundColor
        setCanvasBackground(savedCanvasBackground)

        // Restore animation state
        isAnimationPlaying = savedAnimationPlaying

        // Restore shading mode & outline settings
        setShadingMode(savedShadingMode)
        outlineMaterial?.flowAnimationSpeed = 0.0
        outlineMaterial?.outlineThickness = 0.02

        onDemoModeStateChanged?(false)
    }

    func updateViewport() {
        filamentView.updateViewport()
    }

    // MARK: - Render loop & teardown

    func startRenderLoop() {
        lastFrameTime = CACurrentMediaTime()
        let timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(onRenderTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    func shutdown() {
        renderTimer?.invalidate()
        renderTimer = nil
        overlayWindow?.close()
        overlayWindow = nil
        model.unload()
        outlineModel.unload()
        filamentView.stopRendering()
    }

    @objc private func onRenderTimer() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.25, max(0, now - lastFrameTime)))
        lastFrameTime = now

        if isAnimationPlaying && model.hasAnimations {
            animationTime += dt
            let duration = model.activeAnimationDuration
            if duration > 0.001 {
                animationTime = animationTime.truncatingRemainder(dividingBy: duration)
            }
            model.applyAnimation(time: animationTime)
            if outlineModel.isLoaded && outlineModel.isVisible {
                outlineModel.applyAnimation(time: animationTime)
            }
        }

        model.applyMorphWeights()
        if outlineModel.isLoaded && outlineModel.isVisible {
            outlineModel.applyMorphWeights()
        }

        if let out = outlineMaterial, out.flowAnimationSpeed != 0 {
            let nextPhase = (out.gradientPhase + dt * out.flowAnimationSpeed).truncatingRemainder(dividingBy: 1.0)
            out.gradientPhase = nextPhase >= 0 ? nextPhase : (nextPhase + 1.0)
        }

        updateDemoCamera(dt: dt)
        camera.update(dt: dt)

        if filamentView.renderFrame() {
            let fps = dt > 0 ? 1.0 / Double(dt) : 0
            onFrameRendered?(fps, camera.isAutoOrbiting)
        }
    }
}
