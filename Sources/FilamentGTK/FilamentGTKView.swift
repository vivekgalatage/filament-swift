import Foundation
import Filament
import FilamentC

/// Native GTK 4 host view for Google Filament on Linux.
/// Manages the Filament SwapChain lifecycle attached to a native surface handle.
@MainActor
public final class FilamentGTKView {
    public let engine: FilamentEngine
    public private(set) var nativeWindow: UnsafeMutableRawPointer?
    public private(set) var isHeadless = false
    private let swapChainBox = FilamentSwapChainBox()
    private var swapChain: OpaquePointer? { swapChainBox.handle }
    private var isRendering = false
    public private(set) var currentWidth: UInt32 = 1
    public private(set) var currentHeight: UInt32 = 1

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
        engine.setTransparent(isTransparent)
    }

    public convenience init() {
        self.init(engine: FilamentEngine())
    }

    deinit {
        let engine = engine
        let swapChainBox = swapChainBox
        FilamentMainActor.perform {
            if let eng = engine.engine, let sc = swapChainBox.take() {
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
        self.isHeadless = false
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
        updateViewportAndCamera()
        return created != nil
    }

    /// Attaches an offscreen headless swap chain for integration with GTK 4 drawing areas / Cairo.
    ///
    /// Offscreen rendering completely avoids GPU/Vulkan surface conflicts with GTK 4's GSK renderer.
    /// - Returns: `true` when the headless swap chain was created.
    @discardableResult
    public func attachHeadless(width: UInt32, height: UInt32) -> Bool {
        self.nativeWindow = nil
        self.isHeadless = true
        currentWidth = max(1, width)
        currentHeight = max(1, height)
        guard let eng = engine.engine else { return false }

        if let old = swapChain {
            FilamentBridge.destroySwapChain(eng, old)
            swapChainBox.set(nil)
        }

        var flags = FilamentBridge.getSwapChainFlagReadable()
        if isTransparent {
            flags |= FilamentBridge.getSwapChainFlagTransparent()
        }
        let created = FilamentBridge.createHeadlessSwapChain(eng, currentWidth, currentHeight, flags)
        swapChainBox.set(created)
        if created == nil {
            print("[FilamentGTKView] Headless swap chain creation failed (\(currentWidth)x\(currentHeight)).")
        }
        updateViewportAndCamera()
        return created != nil
    }

    /// Updates the Filament viewport on GTK widget resize.
    public func resize(width: UInt32, height: UInt32) {
        let w = max(1, width)
        let h = max(1, height)
        let sizeChanged = (w != currentWidth || h != currentHeight)
        currentWidth = w
        currentHeight = h

        if isHeadless && sizeChanged {
            guard let eng = engine.engine else { return }
            if let old = swapChain {
                FilamentBridge.destroySwapChain(eng, old)
                swapChainBox.set(nil)
            }
            var flags = FilamentBridge.getSwapChainFlagReadable()
            if isTransparent {
                flags |= FilamentBridge.getSwapChainFlagTransparent()
            }
            let created = FilamentBridge.createHeadlessSwapChain(eng, w, h, flags)
            swapChainBox.set(created)
        }

        updateViewportAndCamera()
    }

    private func updateViewportAndCamera() {
        if let v = engine.view {
            FilamentBridge.setViewport(v, 0, 0, currentWidth, currentHeight)
        }
        engine.setCameraProjection(fovInDegrees: 45.0, aspect: Double(currentWidth) / Double(currentHeight))
    }

    /// Reads pixels from the rendered frame into the supplied memory buffer.
    public func readPixels(into buffer: UnsafeMutableRawPointer, bufferSize: Int) -> Bool {
        engine.readPixels(width: currentWidth, height: currentHeight, into: buffer, bufferSize: bufferSize)
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
        if let nw = nativeWindow {
            attach(nativeWindow: nw, width: currentWidth, height: currentHeight)
        } else if isHeadless {
            attachHeadless(width: currentWidth, height: currentHeight)
        }
    }
}