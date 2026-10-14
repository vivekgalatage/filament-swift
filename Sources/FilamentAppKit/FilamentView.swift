import AppKit
import QuartzCore
import Filament
import FilamentC

/// Native AppKit host view backed by a CAMetalLayer and driven by Google Filament.
/// Supports transparent and solid studio backgrounds, high-DPI scaling, and dynamic resizing.
@MainActor
public final class FilamentView: NSView {
    public let engine: FilamentEngine
    /// Optional interactive orbit/pan/zoom camera controller driven by mouse and trackpad events.
    public var orbitCamera: FilamentOrbitCamera?
    /// Optional hook invoked on mouse scroll or trackpad gestures to handle custom zoom logic (e.g. demo mode).
    /// Returns true if the gesture was handled, bypassing the standard orbitCamera zoom.
    public var onZoomDelta: ((Double) -> Bool)?

    private let swapChainBox = FilamentSwapChainBox()
    private var swapChain: OpaquePointer? { swapChainBox.handle }
    private var isRendering = false

    public var isTransparent: Bool = false {
        didSet {
            guard oldValue != isTransparent else { return }
            engine.setTransparent(isTransparent)
            if let metalLayer = self.layer as? CAMetalLayer {
                metalLayer.isOpaque = !isTransparent
            }
            // CONFIG_TRANSPARENT is fixed at swap chain creation, so it must be rebuilt.
            recreateSwapChain()
        }
    }

    public init(frame frameRect: NSRect, engine: FilamentEngine) {
        self.engine = engine
        super.init(frame: frameRect)
        setupView()
    }

    public convenience override init(frame frameRect: NSRect) {
        self.init(frame: frameRect, config: nil)
    }

    public convenience init(frame frameRect: NSRect, config: FilamentEngine.Config? = nil) {
        self.init(frame: frameRect, engine: FilamentEngine(backend: .metal, config: config))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        // Keep the engine alive until the swap chain is actually destroyed, even if the
        // teardown has to be hopped onto the main actor.
        let engine = engine
        let swapChainBox = swapChainBox
        FilamentMainActor.perform {
            if let eng = engine.engine, let sc = swapChainBox.take() {
                FilamentBridge.destroySwapChain(eng, sc)
            }
        }
    }

    private func setupView() {
        wantsLayer = true
        let metalLayer = CAMetalLayer()
        metalLayer.isOpaque = !isTransparent
        metalLayer.pixelFormat = .bgra8Unorm
        self.layer = metalLayer

        engine.setTransparent(isTransparent)
        recreateSwapChain()
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            window?.performDrag(with: event)
            return
        }
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            orbitCamera?.reset()
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let orbitCamera else { return }
        let dx = Double(event.deltaX)
        let dy = Double(event.deltaY)
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            orbitCamera.pan(deltaX: dx, deltaY: dy)
        } else {
            orbitCamera.orbit(deltaX: dx, deltaY: dy)
        }
    }

    public override func rightMouseDragged(with event: NSEvent) {
        orbitCamera?.pan(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY))
    }

    public override func otherMouseDragged(with event: NSEvent) {
        orbitCamera?.pan(deltaX: Double(event.deltaX), deltaY: Double(event.deltaY))
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let orbitCamera else { return }
        if event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.option) {
            orbitCamera.pan(deltaX: Double(event.scrollingDeltaX), deltaY: Double(event.scrollingDeltaY))
        } else {
            let scale = event.hasPreciseScrollingDeltas ? 0.04 : 0.4
            let delta = Double(event.scrollingDeltaY) * scale
            if let onZoomDelta, onZoomDelta(delta) {
                return
            }
            let cameraScale = event.hasPreciseScrollingDeltas ? 0.08 : 0.8
            orbitCamera.zoom(delta: Double(event.scrollingDeltaY) * cameraScale)
        }
    }

    public override func magnify(with event: NSEvent) {
        let delta = Double(event.magnification) * 4.0
        if let onZoomDelta, onZoomDelta(delta) {
            return
        }
        orbitCamera?.zoom(delta: Double(event.magnification) * 8.0)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            if swapChain == nil {
                recreateSwapChain()
            } else {
                updateViewport()
            }
            startRendering()
        } else {
            stopRendering()
        }
    }

    public override func layout() {
        super.layout()
        updateViewport()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateViewport()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateViewport()
    }

    /// Synchronizes Metal drawable size and Filament viewport with the view bounds and screen backing scale.
    public func updateViewport() {
        guard let metalLayer = self.layer as? CAMetalLayer else { return }

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale

        let w = max(1, Int(bounds.width * scale))
        let h = max(1, Int(bounds.height * scale))
        let newDrawableSize = CGSize(width: CGFloat(w), height: CGFloat(h))
        if metalLayer.drawableSize != newDrawableSize {
            metalLayer.drawableSize = newDrawableSize
        }

        if let v = engine.view {
            FilamentBridge.setViewport(v, 0, 0, UInt32(w), UInt32(h))
        }
        engine.setCameraProjection(fovInDegrees: 45.0, aspect: Double(w) / Double(h))
    }

    private func recreateSwapChain() {
        guard let metalLayer = self.layer as? CAMetalLayer,
              let eng = engine.engine else { return }

        if let old = swapChain {
            FilamentBridge.destroySwapChain(eng, old)
            swapChainBox.set(nil)
        }

        let nativeWindow = Unmanaged.passUnretained(metalLayer).toOpaque()
        let flags = isTransparent ? FilamentBridge.getSwapChainFlagTransparent() : 0
        swapChainBox.set(FilamentBridge.createSwapChain(eng, nativeWindow, flags))

        updateViewport()
    }

    /// Renders a single frame through the Filament pipeline.
    @discardableResult
    public func renderFrame() -> Bool {
        guard let renderer = engine.renderer,
              let view = engine.view,
              let sc = swapChain else { return false }

        if FilamentBridge.beginFrame(renderer, sc) {
            FilamentBridge.renderView(renderer, view)
            FilamentBridge.endFrame(renderer)
            return true
        }
        return false
    }

    public func startRendering() {
        guard !isRendering else { return }
        isRendering = true
    }

    public func stopRendering() {
        isRendering = false
    }
}