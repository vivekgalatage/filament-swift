import Foundation
import FilamentC

#if os(macOS)
import AppKit
import QuartzCore

/// Native AppKit host view backed by a CAMetalLayer and driven by Google Filament.
/// Supports transparent backgrounds, high-DPI scaling, and auto-resizing.
@MainActor
public final class FilamentView: NSView {
    public let engine: FilamentEngine
    private var swapChain: OpaquePointer?
    private var isRendering = false

    public var isTransparent: Bool = true {
        didSet {
            engine.setTransparent(isTransparent)
            if let metalLayer = self.layer as? CAMetalLayer {
                metalLayer.isOpaque = !isTransparent
            }
        }
    }

    public init(frame frameRect: NSRect, engine: FilamentEngine = FilamentEngine(backend: .METAL)) {
        self.engine = engine
        super.init(frame: frameRect)
        setupView()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        MainActor.assumeIsolated {
            stopRendering()
            if let eng = engine.engine, let sc = swapChain {
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

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            recreateSwapChain()
            startRendering()
        } else {
            stopRendering()
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        recreateSwapChain()
    }

    private func recreateSwapChain() {
        guard let metalLayer = self.layer as? CAMetalLayer,
              let eng = engine.engine else { return }

        if let old = swapChain {
            FilamentBridge.destroySwapChain(eng, old)
            swapChain = nil
        }

        let scale = window?.backingScaleFactor ?? 2.0
        metalLayer.contentsScale = scale

        let nativeWindow = Unmanaged.passUnretained(metalLayer).toOpaque()
        self.swapChain = FilamentBridge.createSwapChain(eng, nativeWindow)

        let w = UInt32(max(1, bounds.width * scale))
        let h = UInt32(max(1, bounds.height * scale))
        if let v = engine.view {
            FilamentBridge.setViewport(v, 0, 0, w, h)
        }
    }

    public func renderFrame() {
        guard let renderer = engine.renderer,
              let view = engine.view,
              let sc = swapChain else { return }

        if FilamentBridge.beginFrame(renderer, sc) {
            FilamentBridge.renderView(renderer, view)
            FilamentBridge.endFrame(renderer)
        }
    }

    public func startRendering() {
        guard !isRendering else { return }
        isRendering = true
    }

    public func stopRendering() {
        isRendering = false
    }
}
#endif
