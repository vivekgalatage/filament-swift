import Foundation
import WinSDK
import Filament
import FilamentWin32

/// Manages the Filament Vulkan swap chain, glTF model lifecycle, PBR controller,
/// interactive orbit/pan/zoom camera, and per-frame rendering for the Win32 demo.
@MainActor
final class Win32SceneController {
    let hostView: FilamentWin32View
    let pbrController: FilamentPBRController
    let model: FilamentModel
    let camera: FilamentOrbitCamera
    private(set) var currentModelName: String?

    private var animationTime: Float = 0.0
    private var isAnimationPlaying: Bool = true
    private var lastMouseX: Int?
    private var lastMouseY: Int?

    init(renderChild: HWND, width: UInt32, height: UInt32) {
        let view = FilamentWin32View()
        if !view.attach(hwnd: renderChild, width: width, height: height) {
            print("[Win32Demo] Warning: Filament could not create a swap chain for this HWND.")
        }
        self.hostView = view
        self.pbrController = FilamentPBRController(engine: view.engine)
        self.model = FilamentModel(engine: view.engine)
        self.camera = FilamentOrbitCamera(engine: view.engine)

        if let first = ModelDiscovery.discoverModels().first {
            openModel(at: first.url)
        }
    }

    // MARK: - Models & Animations

    func openModel(at url: URL) {
        let asset = ModelAsset(url: url)
        animationTime = 0.0

        do {
            try model.loadGlb(at: asset.url)
            currentModelName = asset.name
            print("[Win32Demo] Loaded model: \(asset.name)")
        } catch {
            print("[Win32Demo] Failed to load \(asset.url.path): \(error)")
            model.unload()
            currentModelName = nil
        }

        if model.hasAnimations {
            model.selectAnimation(at: 0)
            print("[Win32Demo] Animations available (\(model.animations.count)): \(model.animations.map(\.name).joined(separator: ", "))")
        }

        model.setRotation(radiansY: 0.0)
    }

    func selectAnimation(at index: Int) {
        guard model.hasAnimations, index >= 0, index < model.animations.count else { return }
        model.selectAnimation(at: index)
        animationTime = 0.0
        print("[Win32Demo] Active animation: \(model.animations[index].name)")
    }

    func cycleNextAnimation() {
        guard model.hasAnimations else { return }
        let currentIdx = model.activeAnimationIndex ?? 0
        let nextIdx = (currentIdx + 1) % model.animations.count
        selectAnimation(at: nextIdx)
    }

    // MARK: - Mouse & Camera Controls

    func handleMouseDown(x: Int, y: Int) {
        lastMouseX = x
        lastMouseY = y
    }

    func handleMouseMove(x: Int, y: Int, flags: UInt64) {
        let prevX = lastMouseX ?? x
        let prevY = lastMouseY ?? y
        lastMouseX = x
        lastMouseY = y

        let dx = Double(x - prevX)
        let dy = Double(y - prevY)
        guard dx != 0 || dy != 0 else { return }

        let leftDown = (flags & MK_LBUTTON) != 0
        let rightDown = (flags & MK_RBUTTON) != 0
        let middleDown = (flags & MK_MBUTTON) != 0
        let shiftDown = (flags & MK_SHIFT) != 0

        if rightDown || middleDown || (leftDown && shiftDown) {
            camera.pan(deltaX: dx, deltaY: dy)
        } else if leftDown {
            camera.orbit(deltaX: dx, deltaY: dy)
        }
    }

    func handleMouseWheel(delta: Double) {
        camera.zoom(delta: delta * 1.5)
    }

    func resetCamera() {
        camera.reset()
    }

    func toggleAutoOrbit() {
        camera.isAutoOrbiting.toggle()
        print("[Win32Demo] Auto-orbit \(camera.isAutoOrbiting ? "enabled" : "paused")")
    }

    func syncViewportWithWindow() {
        hostView.syncViewportWithWindow()
    }

    // MARK: - Frame Step & Teardown

    func stepAndRender(dt: Float) {
        if isAnimationPlaying, model.hasAnimations {
            animationTime += dt
            let dur = model.activeAnimationDuration
            if dur > 0.001 {
                animationTime = animationTime.truncatingRemainder(dividingBy: dur)
            }
            model.applyAnimation(time: animationTime)
        }

        camera.update(dt: dt)
        hostView.renderFrame()
    }

    func shutdown() {
        hostView.stopRendering()
        model.unload()
    }
}
