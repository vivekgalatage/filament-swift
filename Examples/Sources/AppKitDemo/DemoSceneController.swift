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
    let pbr: FilamentPBRController
    let camera: FilamentOrbitCamera

    private(set) var currentModelName: String?
    private(set) var isAnimationPlaying: Bool = true

    private var animationTime: Float = 0.0
    private var renderTimer: Timer?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()

    /// Invoked whenever the loaded model changes.
    var onModelStateChanged: (() -> Void)?
    /// Invoked after each rendered frame with the instantaneous FPS and auto-orbit state.
    var onFrameRendered: ((Double, Bool) -> Void)?

    init(frame: NSRect) {
        filamentView = FilamentView(frame: frame)
        filamentView.autoresizingMask = [.width, .height]
        filamentView.isTransparent = false

        let engine = filamentView.engine
        pbr = FilamentPBRController(engine: engine)
        model = FilamentModel(engine: engine)
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
            print("[AppKitDemo] Loaded model: \(asset.name) from \(asset.url.path)")
        } catch {
            print("[AppKitDemo] Failed to load \(asset.url.path): \(error)")
            model.unload()
            currentModelName = nil
        }

        if model.hasAnimations {
            model.selectAnimation(at: 0)
            isAnimationPlaying = true
        } else {
            model.selectAnimation(at: nil)
            isAnimationPlaying = false
        }

        model.setRotation(radiansY: 0.0)
        onModelStateChanged?()
    }

    // MARK: - Animation & camera controls

    func selectAnimation(at index: Int) {
        guard index >= 0 else { return }
        model.selectAnimation(at: index)
        animationTime = 0.0
        print("[AppKitDemo] Selected animation index: \(index)")
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
        model.unload()
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
        }

        camera.update(dt: dt)

        if filamentView.renderFrame() {
            let fps = dt > 0 ? 1.0 / Double(dt) : 0
            onFrameRendered?(fps, camera.isAutoOrbiting)
        }
    }
}
