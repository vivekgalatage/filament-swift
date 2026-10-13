import Foundation
import Filament
import FilamentC

/// Native GTK 4 host view for Google Filament on Linux.
/// Manages the Filament SwapChain lifecycle attached to a native surface handle.
@MainActor
public final class FilamentGTKView {
    public let engine: FilamentEngine
    public private(set) var nativeWindow: UnsafeMutableRawPointer?
    private let swapChainBox = FilamentSwapChainBox()
    private var swapChain: OpaquePointer? { swapChainBox.handle }
    private var isRendering = false
    private var currentWidth: UInt32 = 1
    private var currentHeight: UInt32 = 1

    public var isTransparent: Bool = false {
        didSet {
            guard oldValue != isTransparent else { return }
            engine.setTransparent(isTransparent)
            // CONFIG_TRANSPARENT is fixed at swap chain creation, so it must be rebuilt.
            recreateSwapChain()
        }
    }

    public init(engine: FilamentEngine) {
        self.engine = engine
    }

    public convenience init() {
        self.init(engine: FilamentEngine(backend: .vulkan))
    }

    deinit {
        let engine = engine
        let swapChain = swapChainBox.take()
        nativeWindow = nil
        isRendering = false
        FilamentMainActor.perform {
            if let eng = engine.engine, let sc = swapChain {
                FilamentBridge.destroySwapChain(eng, sc)
            }
        }
    }

    /// Attaches the Filament swap chain to a native surface handle (X11 `Window` XID on X11).
    ///
    /// - Returns: `true` when Filament accepted the handle and created a swap chain.
    @discardableResult
    public func attach(nativeWindow: UnsafeMutableRawPointer, width: UInt32, height: UInt32) -> Bool {
        self.nativeWindow = nativeWindow
        currentWidth = max(1, width)
        currentHeight = max(1, height)
        guard let eng = engine.engine else { return false }

        if let old = swapChain {
            FilamentBridge.destroySwapChain(eng, old)
            swapChainBox.set(nil)
        }

        let flags = isTransparent ? FilamentBridge.getSwapChainFlagTransparent() : 0
        let created = FilamentBridge.createSwapChain(eng, nativeWindow, flags)
        swapChainBox.set(created)
        if created == nil {
            print("[FilamentGTKView] Swap chain creation failed for the supplied native handle.")
        }
        resize(width: currentWidth, height: currentHeight)
        return created != nil
    }

    /// Updates the Filament viewport on GTK widget resize.
    public func resize(width: UInt32, height: UInt32) {
        let w = max(1, width)
        let h = max(1, height)
        currentWidth = w
        currentHeight = h
        if let v = engine.view {
            FilamentBridge.setViewport(v, 0, 0, w, h)
        }
        engine.setCameraProjection(fovInDegrees: 45.0, aspect: Double(w) / Double(h))
    }

    /// `true` once a swap chain has been created successfully.
    public var isAttached: Bool { swapChain != nil }

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
        isRendering = true
    }

    public func stopRendering() {
        isRendering = false
    }

    private func recreateSwapChain() {
        guard let nw = nativeWindow else { return }
        attach(nativeWindow: nw, width: currentWidth, height: currentHeight)
    }
}