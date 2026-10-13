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

        var title: String {
            switch self {
            case .standardPBR: return "Standard PBR"
            case .toonCel: return "Toon Cel (Cartoon)"
            case .toonWithOutline: return "Toon + Inked Outline"
            case .pbrWithOutline: return "PBR + Inked Outline"
            case .outlineOnly: return "Outline Only (Transparent Body)"
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
        }
        overlay.show()
        overlayWindow = overlay
        onOverlayStateChanged?(true)
        return true
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

        camera.update(dt: dt)

        if filamentView.renderFrame() {
            let fps = dt > 0 ? 1.0 / Double(dt) : 0
            onFrameRendered?(fps, camera.isAutoOrbiting)
        }
    }
}
