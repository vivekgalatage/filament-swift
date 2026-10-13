import WinSDK
import Filament
import FilamentC

@_silgen_name("GetClientRect")
private func win32GetClientRect(_ hWnd: UnsafeRawPointer?, _ lpRect: UnsafeMutablePointer<RECT>) -> Int32

/// Pure Win32 host view for Google Filament on Windows.
///
/// Manages the Filament `SwapChain` lifecycle attached to a plain Win32 `HWND`
/// (`CreateWindowExW` / `WNDCLASSEXW` / `DefWindowProcW`). There is no Windows App SDK,
/// no XAML and no WinUI runtime involved: the swap chain is bound to a window handle
/// that the host application creates itself.
@MainActor
public final class FilamentWin32View {
    public let engine: FilamentEngine
    public private(set) var hwnd: HWND?
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
        hwnd = nil
        isRendering = false
        FilamentMainActor.perform {
            if let eng = engine.engine, let sc = swapChain {
                FilamentBridge.destroySwapChain(eng, sc)
            }
        }
    }

    /// Attaches the Filament swap chain to a Win32 `HWND` created with `CreateWindowExW`.
    ///
    /// - Returns: `true` when Filament accepted the handle and created a swap chain.
    @discardableResult
    public func attach(hwnd: HWND, width: UInt32, height: UInt32) -> Bool {
        self.hwnd = hwnd
        currentWidth = max(1, width)
        currentHeight = max(1, height)
        guard let eng = engine.engine else { return false }

        if let old = swapChain {
            FilamentBridge.destroySwapChain(eng, old)
            swapChainBox.set(nil)
        }

        let nativeWindow = UnsafeMutableRawPointer(hwnd)
        let flags = isTransparent ? FilamentBridge.getSwapChainFlagTransparent() : 0
        let created = FilamentBridge.createSwapChain(eng, nativeWindow, flags)
        swapChainBox.set(created)
        if created == nil {
            print("[FilamentWin32View] Swap chain creation failed for HWND \(hwnd).")
        }
        resize(width: currentWidth, height: currentHeight)
        return created != nil
    }

    /// Updates the Filament viewport on window resize.
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

    /// Reads the current client size from the attached window and applies it.
    @discardableResult
    public func syncViewportWithWindow() -> Bool {
        guard let hwnd else { return false }
        var clientRect = RECT()
        guard win32GetClientRect(UnsafeRawPointer(hwnd), &clientRect) != 0 else { return false }
        let width = UInt32(max(1, clientRect.right - clientRect.left))
        let height = UInt32(max(1, clientRect.bottom - clientRect.top))
        resize(width: width, height: height)
        return true
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
        guard let hwnd else { return }
        attach(hwnd: hwnd, width: currentWidth, height: currentHeight)
    }
}