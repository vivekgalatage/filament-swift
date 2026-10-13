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
    private var hasPrintedDisplayWarning = false

    private var pixelBuffer: [UInt8] = []
    public private(set) var activeModelUrl: URL?

    init(drawingArea: OpaquePointer?) {
        self.drawingArea = drawingArea
        let view = FilamentGTKView()
        self.hostView = view
        self.controller = FilamentPBRController(engine: view.engine)
        self.model = FilamentModel(engine: view.engine)
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
        drawingArea = nil
    }
}
