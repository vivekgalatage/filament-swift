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
    let camera: FilamentOrbitCamera

    private var animationTime: Float = 0.0
    private var isAnimationPlaying: Bool = true
    private var lastDragOffsetX: Double = 0.0
    private var lastDragOffsetY: Double = 0.0

    private var drawingArea: OpaquePointer?
    private var lastFrameTime: Double = ProcessInfo.processInfo.systemUptime
    private var currentWidth: UInt32 = 1
    private var currentHeight: UInt32 = 1
    private var isAttached = false

    init(drawingArea: OpaquePointer?) {
        self.drawingArea = drawingArea
        let view = FilamentGTKView()
        self.hostView = view
        self.controller = FilamentPBRController(engine: view.engine)
        self.model = FilamentModel(engine: view.engine)
        self.camera = FilamentOrbitCamera(engine: view.engine)

        if let first = ModelDiscovery.discoverModels().first {
            openModel(at: first.url)
        }
    }

    // MARK: - X11 Surface Attachment & Resizing

    func attachSwapChainIfPossible() {
        guard !isAttached, let drawingArea else { return }
        guard gtk_widget_get_realized(drawingArea) != 0 else { return }

        syncSurfaceSize()

        guard let display = gdk_display_get_default() else {
            print("[GTK4Demo] No default GDK display; cannot create a Filament surface.")
            return
        }

        let getDisplayName = lookupSymbol(
            "gdk_display_get_name",
            as: (@convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?).self
        )
        let displayName = getDisplayName?(display).map { String(cString: $0) } ?? ""
        guard displayName.hasPrefix(":") else {
            print("[GTK4Demo] Filament requires an X11 display on Linux (current display: \(displayName.isEmpty ? "unknown" : displayName)).")
            return
        }

        guard
            let getXDisplay = lookupSymbol("gdk_x11_get_xdisplay", as: (@convention(c) (OpaquePointer?) -> UnsafeMutableRawPointer?).self),
            let getNative = lookupSymbol("gtk_widget_get_native", as: (@convention(c) (OpaquePointer?) -> OpaquePointer?).self),
            let getSurface = lookupSymbol("gtk_native_get_surface", as: (@convention(c) (OpaquePointer?) -> OpaquePointer?).self),
            let getXid = lookupSymbol("gdk_x11_surface_get_xid", as: (@convention(c) (OpaquePointer?) -> UInt).self)
        else {
            print("[GTK4Demo] This GDK build has no X11 backend; Filament cannot create a surface.")
            return
        }

        guard
            let native = getNative(drawingArea),
            let surface = getSurface(native),
            getXDisplay(display) != nil
        else {
            print("[GTK4Demo] Could not resolve the native X11 window handle.")
            return
        }

        let xid = getXid(surface)
        guard xid != 0, let handle = UnsafeMutableRawPointer(bitPattern: xid) else {
            print("[GTK4Demo] Native window handle is invalid (xid=\(xid)).")
            return
        }

        if hostView.attach(nativeWindow: handle, width: currentWidth, height: currentHeight) {
            isAttached = true
            print("[GTK4Demo] Filament swap chain attached (xid=\(xid), \(currentWidth)x\(currentHeight)).")
        } else {
            print("[GTK4Demo] Filament failed to create a swap chain for xid=\(xid).")
        }
    }

    private func syncSurfaceSize() {
        guard let drawingArea else { return }
        let nativeLookup = lookupSymbol("gtk_widget_get_native", as: (@convention(c) (OpaquePointer?) -> OpaquePointer?).self)
        let surfaceLookup = lookupSymbol("gtk_native_get_surface", as: (@convention(c) (OpaquePointer?) -> OpaquePointer?).self)
        guard
            let nativeLookup,
            let surfaceLookup,
            let native = nativeLookup(drawingArea),
            let surface = surfaceLookup(native)
        else { return }
        currentWidth = UInt32(max(1, gdk_surface_get_width(surface)))
        currentHeight = UInt32(max(1, gdk_surface_get_height(surface)))
    }

    // MARK: - Models, Animations & Camera Input

    func openModel(at url: URL) {
        let asset = ModelAsset(url: url)
        animationTime = 0.0

        do {
            try model.loadGlb(at: asset.url)
            print("[GTK4Demo] Loaded model: \(asset.name)")
        } catch {
            print("[GTK4Demo] Failed to load \(asset.url.path): \(error)")
            model.unload()
        }

        if model.hasAnimations {
            model.selectAnimation(at: 0)
            print("[GTK4Demo] Animations available (\(model.animations.count)): \(model.animations.map(\.name).joined(separator: ", "))")
        }

        model.setRotation(radiansY: 0.0)
    }

    func cycleNextAnimation() {
        guard model.hasAnimations else { return }
        let currentIdx = model.activeAnimationIndex ?? 0
        let nextIdx = (currentIdx + 1) % model.animations.count
        model.selectAnimation(at: nextIdx)
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

    // MARK: - Frame Tick & Teardown

    func onFrameTick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(min(0.25, max(0, now - lastFrameTime)))
        lastFrameTime = now

        attachSwapChainIfPossible()

        let previousWidth = currentWidth
        let previousHeight = currentHeight
        syncSurfaceSize()
        if isAttached && (previousWidth != currentWidth || previousHeight != currentHeight) {
            hostView.resize(width: currentWidth, height: currentHeight)
        }

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
        drawingArea = nil
    }
}
