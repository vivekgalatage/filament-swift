import Foundation
import Filament
import FilamentGTK

/// Manages the Filament Vulkan viewport, X11 surface attachment, glTF model lifecycle,
/// PBR controller, interactive orbit/pan/zoom camera, and per-frame tick for the Linux GTK 4 demo.
@MainActor
final class GTKSceneController {
    let hostView: FilamentGTKView
    let controller: FilamentPBRController
    let model: FilamentModel
    let outlineModel: FilamentModel
    let camera: FilamentOrbitCamera

    public enum ShadingMode: Int, CaseIterable {
        case standardPBR = 0
        case toonCel = 1
        case toonWithOutline = 2
        case pbrWithOutline = 3
        case outlineOnly = 4
        case comicHalftone = 5
        case halftoneWithOutline = 6
        case handdrawnSketch = 7

        var title: String {
            switch self {
            case .standardPBR: return "Standard PBR"
            case .toonCel: return "Toon Cel (Cartoon)"
            case .toonWithOutline: return "Toon + Inked Outline"
            case .pbrWithOutline: return "PBR + Inked Outline"
            case .outlineOnly: return "Outline Only (Transparent Body)"
            case .comicHalftone: return "Comic Halftone (Pop-Art / Manga)"
            case .halftoneWithOutline: return "Halftone + Inked Outline"
            case .handdrawnSketch: return "✏️ Handdrawn Technical Sketch"
            }
        }
    }

    public private(set) var currentShadingMode: ShadingMode = .standardPBR
    public private(set) var currentOutlineColor: (r: Float, g: Float, b: Float) = (0.10, 0.08, 0.06)
    public private(set) var currentOutlineThickness: Float = 2.5
    public private(set) var currentOutlineJitter: Float = 0.0
    public private(set) var currentOutlineGradientMode: FilamentToonOutlineMaterial.GradientMode = .solid
    public private(set) var currentOutlineFlowSpeed: Float = 0.0
    public private(set) var currentCelBaseColor: (r: Float, g: Float, b: Float) = (0.96, 0.95, 0.94)
    public private(set) var currentCelShadowMultiplier: (r: Float, g: Float, b: Float) = (0.45, 0.45, 0.65)
    public private(set) var toonMaterial: FilamentToonMaterial?
    public private(set) var outlineMaterial: FilamentToonOutlineMaterial?
    public private(set) var depthMaskMaterial: FilamentDepthMaskMaterial?

    private var animationTime: Float = 0.0
    private var isAnimationPlaying: Bool = true
    private var lastDragOffsetX: Double = 0.0
    private var lastDragOffsetY: Double = 0.0

    private var drawingArea: OpaquePointer?
    private var lastFrameTime: Double = ProcessInfo.processInfo.systemUptime
    private var currentWidth: UInt32 = 1
    private var currentHeight: UInt32 = 1
    private var isAttached = false
    private var hasPrintedDisplayWarning = false

    private var pixelBuffer: [UInt8] = []
    public private(set) var activeModelUrl: URL?

    init(drawingArea: OpaquePointer?) {
        self.drawingArea = drawingArea
        let view = FilamentGTKView()
        self.hostView = view
        self.controller = FilamentPBRController(engine: view.engine)
        self.model = FilamentModel(engine: view.engine)
        self.outlineModel = FilamentModel(engine: view.engine)
        self.camera = FilamentOrbitCamera(engine: view.engine)

        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = sourceDir.deletingLastPathComponent().deletingLastPathComponent()
        let fallbackPaths = [
            repoRoot.appendingPathComponent("Resources", isDirectory: true),
            repoRoot.appendingPathComponent("Examples/Resources", isDirectory: true),
        ]
        let models = ModelDiscovery.discoverModels(extraSearchPaths: fallbackPaths)
        if let first = models.first {
            openModel(at: first.url)
        }
    }

    // MARK: - Offscreen Headless Swap Chain & Cairo Drawing

    func attachSwapChainIfPossible() {
        guard !isAttached, let drawingArea else { return }
        guard gtk_widget_get_realized(drawingArea) != 0 else { return }

        let w = UInt32(max(1, gtk_widget_get_width(drawingArea)))
        let h = UInt32(max(1, gtk_widget_get_height(drawingArea)))
        guard w >= 50, h >= 50 else { return }

        currentWidth = w
        currentHeight = h
        if hostView.attachHeadless(width: currentWidth, height: currentHeight) {
            isAttached = true
            pixelBuffer = [UInt8](repeating: 0, count: Int(currentWidth * currentHeight * 4))
            print("[GTK4Demo] Filament headless swap chain attached (\(currentWidth)x\(currentHeight)).")
        }
    }

    func draw(cr: OpaquePointer?, width: Int32, height: Int32) {
        guard let cr else { return }

        // Fill entire drawing area with Filament studio background color (matches clear color)
        // so no GTK theme background shows through during resize or before the first frame.
        cairo_set_source_rgb(cr, 0.38, 0.41, 0.47)
        cairo_paint(cr)

        guard isAttached, !pixelBuffer.isEmpty else { return }
        let w = Int32(currentWidth)
        let h = Int32(currentHeight)
        guard w > 0, h > 0 else { return }
        let stride = w * 4

        pixelBuffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            guard let surface = cairo_image_surface_create_for_data(base, CAIRO_FORMAT_ARGB32, w, h, stride) else { return }
            cairo_surface_flush(surface)
            cairo_save(cr)
            if width != w || height != h {
                let sx = Double(width) / Double(w)
                let sy = Double(height) / Double(h)
                cairo_scale(cr, sx, sy)
            }
            cairo_set_source_surface(cr, surface, 0.0, 0.0)
            cairo_paint(cr)
            cairo_restore(cr)
            cairo_surface_destroy(surface)
        }
    }

    // MARK: - Models, Animations & Camera Input

    func openModel(at url: URL) {
        self.activeModelUrl = url
        let asset = ModelAsset(url: url)
        animationTime = 0.0

        do {
            try model.loadGlb(at: asset.url)
            print("[GTK4Demo] Loaded model: \(asset.name)")
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
            print("[GTK4Demo] Failed to load \(asset.url.path): \(error)")
            model.unload()
            outlineModel.unload()
        }

        if model.hasAnimations {
            model.selectAnimation(at: 0)
            print("[GTK4Demo] Animations available (\(model.animations.count)): \(model.animations.map(\.name).joined(separator: ", "))")
        }

        model.setRotation(radiansY: 0.0)
        applyCurrentShadingMode()
    }

    func cycleNextAnimation() {
        guard model.hasAnimations else { return }
        let currentIdx = model.activeAnimationIndex ?? 0
        let nextIdx = (currentIdx + 1) % model.animations.count
        model.selectAnimation(at: nextIdx)
        if outlineModel.isLoaded {
            outlineModel.selectAnimation(at: nextIdx)
        }
        animationTime = 0.0
        print("[GTK4Demo] Active animation: \(model.animations[nextIdx].name)")
    }

    func beginDrag() {
        lastDragOffsetX = 0.0
        lastDragOffsetY = 0.0
    }

    func updateDrag(offsetX: Double, offsetY: Double, button: UInt32, modifiers: UInt32) {
        let dx = offsetX - lastDragOffsetX
        let dy = offsetY - lastDragOffsetY
        lastDragOffsetX = offsetX
        lastDragOffsetY = offsetY

        let isShift = (modifiers & GDK_SHIFT_MASK) != 0
        if button == 2 || button == 3 || (button == 1 && isShift) {
            camera.pan(deltaX: dx, deltaY: dy)
        } else {
            camera.orbit(deltaX: dx, deltaY: dy)
        }
    }

    func handleScroll(dy: Double) {
        camera.zoom(delta: -dy * 1.5)
    }

    func resetCamera() {
        camera.reset()
    }

    // MARK: - Toon, Outline & Halftone Controls

    func setShadingMode(_ mode: ShadingMode) {
        currentShadingMode = mode
        applyCurrentShadingMode()
    }

    func setOutlineThickness(_ value: Float) {
        currentOutlineThickness = value
        ensureToonMaterials()
        outlineMaterial?.outlineThickness = value
    }

    func setToonBaseColor(r: Float, g: Float, b: Float) {
        currentCelBaseColor = (r, g, b)
        ensureToonMaterials()
        toonMaterial?.baseColor = (r, g, b, 1.0)
    }

    func setOutlineColor(r: Float, g: Float, b: Float) {
        currentOutlineColor = (r, g, b)
        ensureToonMaterials()
        outlineMaterial?.outlineColor = (r, g, b, 1.0)
    }

    func setOutlineGradientMode(_ mode: FilamentToonOutlineMaterial.GradientMode) {
        currentOutlineGradientMode = mode
        ensureToonMaterials()
        outlineMaterial?.gradientMode = mode
    }

    func setOutlineStops(_ stops: [FilamentToonOutlineMaterial.GradientStop]) {
        ensureToonMaterials()
        outlineMaterial?.stops = stops
    }

    func randomizeOutlineColors() {
        ensureToonMaterials()
        outlineMaterial?.randomizeColors()
    }

    func setOutlineGradientScale(_ scale: Float) {
        ensureToonMaterials()
        outlineMaterial?.gradientScale = scale
    }

    func setOutlineFlowSpeed(_ speed: Float) {
        currentOutlineFlowSpeed = speed
        ensureToonMaterials()
        outlineMaterial?.flowAnimationSpeed = speed
    }

    func setOutlineNoiseScale(_ noise: Float) {
        ensureToonMaterials()
        outlineMaterial?.noiseScale = noise
    }

    func setHalftoneMode(_ mode: FilamentToonMaterial.HalftoneMode) {
        ensureToonMaterials()
        toonMaterial?.halftoneMode = mode
    }

    func setHalftoneTarget(_ target: FilamentToonMaterial.HalftoneTarget) {
        ensureToonMaterials()
        toonMaterial?.halftoneTarget = target
    }

    func setHalftoneScale(_ scale: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneScale = scale
    }

    func setHalftoneAngle(_ angle: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneAngle = angle
    }

    func setHalftoneDotSize(_ size: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneDotSize = size
    }

    func setHalftoneHardness(_ hardness: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneHardness = hardness
    }

    func setHalftoneBlend(_ blend: Float) {
        ensureToonMaterials()
        toonMaterial?.halftoneBlend = blend
    }

    func setHalftoneDotColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureToonMaterials()
        toonMaterial?.halftoneDotColor = (r, g, b, a)
    }

    func setHalftonePaperColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureToonMaterials()
        toonMaterial?.halftonePaperColor = (r, g, b, a)
    }

    func applyHalftonePreset(_ preset: FilamentToonMaterial.HalftonePreset) {
        ensureToonMaterials()
        toonMaterial?.applyPreset(preset)
    }

    private func applyCurrentShadingMode() {
        guard let url = activeModelUrl else { return }
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
                print("[GTK4Demo] Failed to reload PBR model: \(error)")
            }

        case .toonCel:
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                toon.halftoneMode = .disabled
                toon.hatchJitter = 0.0
                toon.halftoneBlend = 0.0
                toon.baseColor = (currentCelBaseColor.r, currentCelBaseColor.g, currentCelBaseColor.b, 1.0)
                toon.shadowColorMultiplier = (currentCelShadowMultiplier.r, currentCelShadowMultiplier.g, currentCelShadowMultiplier.b)
                model.applyToonMaterial(toon)
            }

        case .toonWithOutline:
            model.setPriority(4)
            if let toon = toonMaterial {
                toon.halftoneMode = .disabled
                toon.hatchJitter = 0.0
                toon.halftoneBlend = 0.0
                toon.baseColor = (currentCelBaseColor.r, currentCelBaseColor.g, currentCelBaseColor.b, 1.0)
                toon.shadowColorMultiplier = (currentCelShadowMultiplier.r, currentCelShadowMultiplier.g, currentCelShadowMultiplier.b)
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
                outline.outlineThickness = currentOutlineThickness
                outline.outlineJitter = currentOutlineJitter
                outline.gradientMode = currentOutlineGradientMode
                outline.flowAnimationSpeed = currentOutlineFlowSpeed
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
                print("[GTK4Demo] Failed to reload PBR model: \(error)")
            }
            if !outlineModel.isLoaded {
                try? outlineModel.loadGlb(at: url)
                outlineModel.setRotation(radiansY: 0.0)
                if outlineModel.hasAnimations {
                    outlineModel.selectAnimation(at: model.activeAnimationIndex ?? 0)
                }
            }
            if let outline = outlineMaterial {
                outline.outlineThickness = currentOutlineThickness
                outline.outlineJitter = currentOutlineJitter
                outline.gradientMode = currentOutlineGradientMode
                outline.flowAnimationSpeed = currentOutlineFlowSpeed
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
                outline.outlineThickness = currentOutlineThickness
                outline.outlineJitter = currentOutlineJitter
                outline.gradientMode = currentOutlineGradientMode
                outline.flowAnimationSpeed = currentOutlineFlowSpeed
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case .comicHalftone:
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode == .disabled || toon.halftoneMode == .handdrawnSketch {
                    toon.applyPreset(FilamentToonMaterial.spiderVersePreset)
                }
                toon.hatchJitter = 0.0
                toon.halftoneBlend = 1.0
                model.applyToonMaterial(toon)
            }

        case .halftoneWithOutline:
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode == .disabled || toon.halftoneMode == .handdrawnSketch {
                    toon.applyPreset(FilamentToonMaterial.mangaScreentonePreset)
                }
                toon.hatchJitter = 0.0
                toon.halftoneBlend = 1.0
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
                outline.outlineThickness = currentOutlineThickness
                outline.outlineJitter = currentOutlineJitter
                outline.gradientMode = currentOutlineGradientMode
                outline.flowAnimationSpeed = currentOutlineFlowSpeed
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case .handdrawnSketch:
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode != .handdrawnSketch {
                    toon.applyPreset(FilamentToonMaterial.technicalArchitecturalPreset)
                }
                toon.halftoneMode = .handdrawnSketch
                toon.halftoneTarget = .fullSurface
                toon.halftoneBlend = 1.0
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
                if outline.outlineJitter < 0.001 {
                    outline.outlineJitter = 0.20
                }
                outline.outlineThickness = currentOutlineThickness
                outline.gradientMode = .graphitePencil
                outline.flowAnimationSpeed = 0.0
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)
        }
    }

    // MARK: - Handdrawn Sketch & Technical Diagram controls

    func setOutlineJitter(_ jitter: Float) {
        currentOutlineJitter = jitter
        ensureToonMaterials()
        outlineMaterial?.outlineJitter = jitter
        overlay?.setOutlineJitter(jitter)
    }

    func setOutlineJitterFreq(_ freq: Float) {
        ensureToonMaterials()
        outlineMaterial?.outlineJitterFreq = freq
        overlay?.setOutlineJitterFreq(freq)
    }

    func setHatchJitter(_ jitter: Float) {
        ensureToonMaterials()
        toonMaterial?.hatchJitter = jitter
        overlay?.setHatchJitter(jitter)
    }

    func setHatchLayers(_ layers: Int32) {
        ensureToonMaterials()
        toonMaterial?.hatchLayers = layers
        overlay?.setHatchLayers(layers)
    }

    func setHatchThresholds(t1: Float, t2: Float, t3: Float) {
        ensureToonMaterials()
        toonMaterial?.hatchThreshold1 = t1
        toonMaterial?.hatchThreshold2 = t2
        toonMaterial?.hatchThreshold3 = t3
        overlay?.setHatchThresholds(t1: t1, t2: t2, t3: t3)
    }

    func applySketchPreset(_ preset: FilamentToonMaterial.HalftonePreset) {
        ensureToonMaterials()
        toonMaterial?.applyPreset(preset)
        overlay?.applyHalftonePreset(preset)

        setOutlineColor(r: preset.dotColor.r, g: preset.dotColor.g, b: preset.dotColor.b)
        setOutlineJitter(preset.hatchJitter * 0.85)
        setOutlineThickness(preset.dotSize * 2.2)
    }

    private func ensureToonMaterials() {
        guard toonMaterial == nil || outlineMaterial == nil || depthMaskMaterial == nil else { return }
        let engine = hostView.engine
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
                    print("[GTK4Demo] Loaded ToonCel material from \(celURL.path)")
                } catch {
                    print("[GTK4Demo] Error loading ToonCel: \(error)")
                }
            }
            if FileManager.default.fileExists(atPath: outURL.path) && outlineMaterial == nil {
                do {
                    let out = try engine.createOutlineMaterial(from: outURL)
                    out.outlineColor = (currentOutlineColor.r, currentOutlineColor.g, currentOutlineColor.b, 1.0)
                    out.outlineThickness = currentOutlineThickness
                    out.outlineJitter = currentOutlineJitter
                    out.gradientMode = currentOutlineGradientMode
                    out.flowAnimationSpeed = currentOutlineFlowSpeed
                    outlineMaterial = out
                    print("[GTK4Demo] Loaded ToonOutline material from \(outURL.path)")
                } catch {
                    print("[GTK4Demo] Error loading ToonOutline: \(error)")
                }
            }
            if FileManager.default.fileExists(atPath: maskURL.path) && depthMaskMaterial == nil {
                do {
                    depthMaskMaterial = try engine.createDepthMaskMaterial(from: maskURL)
                    print("[GTK4Demo] Loaded DepthMask material from \(maskURL.path)")
                } catch {
                    print("[GTK4Demo] Error loading DepthMask: \(error)")
                }
            }
        }
    }

    // MARK: - Frame Tick & Teardown

    func onFrameTick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(min(0.25, max(0, now - lastFrameTime)))
        lastFrameTime = now

        attachSwapChainIfPossible()

        if let drawingArea, isAttached {
            let w = UInt32(max(1, gtk_widget_get_width(drawingArea)))
            let h = UInt32(max(1, gtk_widget_get_height(drawingArea)))
            if w >= 50, h >= 50, (w != currentWidth || h != currentHeight) {
                currentWidth = w
                currentHeight = h
                hostView.resize(width: currentWidth, height: currentHeight)
                pixelBuffer = [UInt8](repeating: 0, count: Int(currentWidth * currentHeight * 4))
            }
        }

        if isAnimationPlaying, model.hasAnimations {
            animationTime += dt
            let dur = model.activeAnimationDuration
            if dur > 0.001 {
                animationTime = animationTime.truncatingRemainder(dividingBy: dur)
            }
            model.applyAnimation(time: animationTime)
            if outlineModel.isLoaded && outlineModel.isVisible {
                outlineModel.applyAnimation(time: animationTime)
            }
        }

        if let out = outlineMaterial, out.flowAnimationSpeed != 0 {
            let nextPhase = (out.gradientPhase + dt * out.flowAnimationSpeed).truncatingRemainder(dividingBy: 1.0)
            out.gradientPhase = nextPhase >= 0 ? nextPhase : (nextPhase + 1.0)
        }

        camera.update(dt: dt)

        if isAttached {
            let bufferSize = pixelBuffer.count
            let rendered = pixelBuffer.withUnsafeMutableBytes { ptr -> Bool in
                guard let base = ptr.baseAddress else { return false }
                return hostView.renderFrame(readPixelsBuffer: base, bufferSize: bufferSize)
            }
            if rendered, let drawingArea {
                convertRGBAToCairoARGB32()
                gtk_widget_queue_draw(drawingArea)
            }
        }
    }

    private func convertRGBAToCairoARGB32() {
        let pixelCount = Int(currentWidth * currentHeight)
        pixelBuffer.withUnsafeMutableBufferPointer { buf in
            guard let ptr = buf.baseAddress else { return }
            var idx = 0
            for _ in 0..<pixelCount {
                let r = ptr[idx + 0]
                let g = ptr[idx + 1]
                let b = ptr[idx + 2]
                let a = ptr[idx + 3]

                if a == 255 {
                    ptr[idx + 0] = b
                    ptr[idx + 1] = g
                    ptr[idx + 2] = r
                } else if a == 0 {
                    ptr[idx + 0] = 0
                    ptr[idx + 1] = 0
                    ptr[idx + 2] = 0
                    ptr[idx + 3] = 0
                } else {
                    let scale = Float(a) / 255.0
                    ptr[idx + 0] = UInt8(Float(b) * scale)
                    ptr[idx + 1] = UInt8(Float(g) * scale)
                    ptr[idx + 2] = UInt8(Float(r) * scale)
                }
                idx += 4
            }
        }
    }

    func shutdown() {
        hostView.stopRendering()
        model.unload()
        outlineModel.unload()
        drawingArea = nil
    }
}
