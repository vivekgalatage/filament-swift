import WinSDK
import Filament
import FilamentC
import Foundation

// MARK: - Win32 GDI & User32 Interop via SILGen

@_silgen_name("UpdateLayeredWindow")
private func win32UpdateLayeredWindow(
    _ hWnd: UnsafeRawPointer?,
    _ hdcDst: UnsafeRawPointer?,
    _ pptDst: UnsafeMutablePointer<POINT>?,
    _ psize: UnsafeMutablePointer<SIZE>?,
    _ hdcSrc: UnsafeRawPointer?,
    _ pptSrc: UnsafeMutablePointer<POINT>?,
    _ crKey: UInt32,
    _ pblend: UnsafePointer<BLENDFUNCTION>?,
    _ dwFlags: UInt32
) -> Int32

@_silgen_name("CreateDIBSection")
private func win32CreateDIBSection(
    _ hdc: UnsafeRawPointer?,
    _ pbmi: UnsafePointer<BITMAPINFO>?,
    _ usage: UInt32,
    _ ppvBits: UnsafeMutablePointer<UnsafeMutableRawPointer?>?,
    _ hSection: UnsafeRawPointer?,
    _ offset: UInt32
) -> UnsafeMutableRawPointer?

@_silgen_name("CreateCompatibleDC")
private func win32CreateCompatibleDC(_ hdc: UnsafeRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("DeleteDC")
private func win32DeleteDC(_ hdc: UnsafeRawPointer?) -> Int32

@_silgen_name("SelectObject")
private func win32SelectObject(_ hdc: UnsafeRawPointer?, _ hgdiobj: UnsafeRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("DeleteObject")
private func win32DeleteObject(_ hObject: UnsafeRawPointer?) -> Int32

@_silgen_name("GetDC")
private func win32GetDC(_ hWnd: UnsafeRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("ReleaseDC")
private func win32ReleaseDC(_ hWnd: UnsafeRawPointer?, _ hDC: UnsafeRawPointer?) -> Int32

@_silgen_name("SetWindowPos")
private func win32SetWindowPos(
    _ hWnd: UnsafeRawPointer?,
    _ hWndInsertAfter: UnsafeRawPointer?,
    _ X: Int32, _ Y: Int32, _ cx: Int32, _ cy: Int32,
    _ uFlags: UInt32
) -> Int32

@_silgen_name("ShowWindow")
private func win32ShowWindow(_ hWnd: UnsafeRawPointer?, _ nCmdShow: Int32) -> Int32

@_silgen_name("DestroyWindow")
private func win32DestroyWindow(_ hWnd: UnsafeRawPointer?) -> Int32

@_silgen_name("GetWindowLongW")
private func win32GetWindowLongW(_ hWnd: UnsafeRawPointer?, _ nIndex: Int32) -> Int32

@_silgen_name("SetWindowLongW")
private func win32SetWindowLongW(_ hWnd: UnsafeRawPointer?, _ nIndex: Int32, _ dwNewLong: Int32) -> Int32

@_silgen_name("SendMessageW")
private func win32SendMessageW(
    _ hWnd: UnsafeRawPointer?,
    _ Msg: UInt32,
    _ wParam: UInt,
    _ lParam: Int
) -> Int

// MARK: - Constants

private let kGWL_EXSTYLE: Int32 = -20
private let kWS_POPUP: UInt32 = 0x8000_0000
private let kWS_VISIBLE: UInt32 = 0x1000_0000
private let kWS_EX_LAYERED: UInt32 = 0x0008_0000
private let kWS_EX_TOPMOST: UInt32 = 0x0000_0008
private let kWS_EX_TOOLWINDOW: UInt32 = 0x0000_0080
private let kWS_EX_TRANSPARENT: UInt32 = 0x0000_0020

private let kSW_SHOW: Int32 = 5
private let kSW_HIDE: Int32 = 0

private let kSWP_NOSIZE: UInt32 = 0x0001
private let kSWP_NOMOVE: UInt32 = 0x0002
private let kSWP_NOZORDER: UInt32 = 0x0004
private let kSWP_FRAMECHANGED: UInt32 = 0x0020
private let kSWP_SHOWWINDOW: UInt32 = 0x0040

private let kULW_ALPHA: UInt32 = 0x0000_0002
private let kAC_SRC_OVER: UInt8 = 0x00
private let kAC_SRC_ALPHA: UInt8 = 0x01
private let kDIB_RGB_COLORS: UInt32 = 0
private let kBI_RGB: UInt32 = 0

private let kWM_LBUTTONDOWN: UInt32 = 0x0201
private let kWM_NCLBUTTONDOWN: UInt32 = 0x00A1
private let kHTCAPTION: UInt = 2

/// Transparent floating companion/assistant overlay for Windows.
///
/// Hosts a 3D GLB model (with blend shapes and skeletal animations) inside a borderless,
/// top-level `WS_EX_LAYERED` window. Frames are rendered transparently by Google Filament
/// and composited by Windows DWM via `UpdateLayeredWindow` with per-pixel alpha (`AC_SRC_ALPHA`).
///
/// Because this is a top-level DWM window:
/// - It floats seamlessly above **any** application (browsers, editors, or the desktop).
/// - Has true alpha transparency (soft edges, fur/hair anti-aliasing, and contact shadows).
/// - Can be dragged with the mouse or repositioned programmatically across the screen.
/// - Supports optional click-through (`isClickThrough = true`) so user clicks pass to apps underneath.
@MainActor
public final class FilamentOverlayWindow {
    public let engine: FilamentEngine
    public let model: FilamentModel
    public let camera: FilamentOrbitCamera
    public private(set) var hwnd: HWND?

    public let width: UInt32
    public let height: UInt32

    private var headlessSwapChain: OpaquePointer?
    private var memDC: UnsafeMutableRawPointer?
    private var dibBitmap: UnsafeMutableRawPointer?
    private var oldBitmap: UnsafeMutableRawPointer?
    private var dibBits: UnsafeMutablePointer<UInt8>?

    private var rgbaBuffer: [UInt8]
    private var currentPositionX: Int32 = 100
    private var currentPositionY: Int32 = 100

    private static var isClassRegistered = false
    private static let windowClassName = "FilamentFloatingOverlayClass"

    public var isClickThrough: Bool = false {
        didSet {
            guard oldValue != isClickThrough else { return }
            updateClickThroughStyle()
        }
    }

    public init(width: UInt32 = 400, height: UInt32 = 400, engine: FilamentEngine? = nil) {
        self.width = max(64, width)
        self.height = max(64, height)

        let eng = engine ?? FilamentEngine(backend: .vulkan)
        self.engine = eng
        self.model = FilamentModel(engine: eng)
        self.camera = FilamentOrbitCamera(engine: eng)

        self.rgbaBuffer = [UInt8](repeating: 0, count: Int(self.width * self.height * 4))

        eng.setTransparent(true)
        setupHeadlessSwapChain()
        setupDIBSection()
        createOverlayWindow()
    }

    deinit {
        let eng = engine
        let sc = headlessSwapChain
        let mdc = memDC
        let bmp = dibBitmap
        let old = oldBitmap
        let wnd = hwnd

        FilamentMainActor.perform {
            if let wnd {
                _ = win32DestroyWindow(UnsafeRawPointer(wnd))
            }
            if let mdc, let old {
                _ = win32SelectObject(mdc, old)
            }
            if let bmp {
                _ = win32DeleteObject(bmp)
            }
            if let mdc {
                _ = win32DeleteDC(mdc)
            }
            if let sc {
                eng.destroySwapChain(sc)
            }
        }
    }

    // MARK: - Setup

    private func setupHeadlessSwapChain() {
        headlessSwapChain = engine.createHeadlessSwapChain(width: width, height: height, transparent: true)
        if let v = engine.view {
            FilamentBridge.setViewport(v, 0, 0, width, height)
        }
        engine.setCameraProjection(fovInDegrees: 45.0, aspect: Double(width) / Double(height))
    }

    private func setupDIBSection() {
        let screenDC = win32GetDC(nil)
        defer { _ = win32ReleaseDC(nil, screenDC) }

        memDC = win32CreateCompatibleDC(screenDC)

        var bmi = BITMAPINFO()
        bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        bmi.bmiHeader.biWidth = LONG(width)
        bmi.bmiHeader.biHeight = -LONG(height) // Negative for top-down DIB
        bmi.bmiHeader.biPlanes = 1
        bmi.bmiHeader.biBitCount = 32
        bmi.bmiHeader.biCompression = DWORD(kBI_RGB)

        var bitsPtr: UnsafeMutableRawPointer? = nil
        dibBitmap = withUnsafePointer(to: &bmi) { bmiPtr in
            win32CreateDIBSection(memDC, bmiPtr, kDIB_RGB_COLORS, &bitsPtr, nil, 0)
        }

        if let bitsPtr {
            dibBits = bitsPtr.assumingMemoryBound(to: UInt8.self)
        }

        if let memDC, let dibBitmap {
            oldBitmap = win32SelectObject(memDC, dibBitmap)
        }
    }

    private func createOverlayWindow() {
        registerClassIfNeeded()

        Self.windowClassName.withCString(encodedAs: UTF16.self) { classWide in
            let exStyle = DWORD(kWS_EX_LAYERED | kWS_EX_TOPMOST | kWS_EX_TOOLWINDOW)
            let style = DWORD(kWS_POPUP)

            guard let handle = CreateWindowExW(
                exStyle, classWide, nil, style,
                currentPositionX, currentPositionY, Int32(width), Int32(height),
                nil, nil, GetModuleHandleW(nil), nil
            ) else {
                print("[FilamentOverlayWindow] Failed to create overlay HWND")
                return
            }
            self.hwnd = handle
        }
    }

    private func registerClassIfNeeded() {
        guard !Self.isClassRegistered else { return }
        Self.windowClassName.withCString(encodedAs: UTF16.self) { classWide in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.style = UINT(CS_HREDRAW | CS_VREDRAW)
            wc.lpfnWndProc = { hwnd, msg, wParam, lParam -> LRESULT in
                if msg == kWM_LBUTTONDOWN {
                    // Allow dragging the assistant window anywhere
                    _ = win32SendMessageW(UnsafeRawPointer(hwnd), kWM_NCLBUTTONDOWN, kHTCAPTION, 0)
                    return 0
                }
                return DefWindowProcW(hwnd, msg, wParam, lParam)
            }
            wc.hInstance = GetModuleHandleW(nil)
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDC_ARROW
            wc.lpszClassName = classWide
            _ = RegisterClassExW(&wc)
            Self.isClassRegistered = true
        }
    }

    // MARK: - Window Visibility & Positioning

    public func show(atX x: Int32? = nil, y: Int32? = nil) {
        if let x { currentPositionX = x }
        if let y { currentPositionY = y }
        guard let hwnd else { return }
        _ = win32SetWindowPos(UnsafeRawPointer(hwnd), nil, currentPositionX, currentPositionY, 0, 0,
                              kSWP_NOSIZE | kSWP_NOZORDER | kSWP_SHOWWINDOW)
    }

    public func hide() {
        guard let hwnd else { return }
        _ = win32ShowWindow(UnsafeRawPointer(hwnd), kSW_HIDE)
    }

    public func setPosition(x: Int32, y: Int32) {
        currentPositionX = x
        currentPositionY = y
        guard let hwnd else { return }
        _ = win32SetWindowPos(UnsafeRawPointer(hwnd), nil, x, y, 0, 0,
                              kSWP_NOSIZE | kSWP_NOZORDER)
    }

    private func updateClickThroughStyle() {
        guard let hwnd else { return }
        let currentEx = win32GetWindowLongW(UnsafeRawPointer(hwnd), kGWL_EXSTYLE)
        let newEx: Int32
        if isClickThrough {
            newEx = currentEx | Int32(bitPattern: kWS_EX_TRANSPARENT)
        } else {
            newEx = currentEx & ~Int32(bitPattern: kWS_EX_TRANSPARENT)
        }
        _ = win32SetWindowLongW(UnsafeRawPointer(hwnd), kGWL_EXSTYLE, newEx)
        _ = win32SetWindowPos(UnsafeRawPointer(hwnd), nil, 0, 0, 0, 0,
                              kSWP_NOMOVE | kSWP_NOSIZE | kSWP_NOZORDER | kSWP_FRAMECHANGED)
    }

    // MARK: - Frame Rendering & Layered Window Update

    @discardableResult
    public func renderFrame() -> Bool {
        guard let renderer = engine.renderer,
              let view = engine.view,
              let sc = headlessSwapChain,
              let hwnd,
              let memDC,
              let dibBits else { return false }

        guard FilamentBridge.beginFrame(renderer, sc) else { return false }
        FilamentBridge.renderView(renderer, view)

        let bufferSize = rgbaBuffer.count
        let readSuccess = rgbaBuffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return engine.readPixels(width: width, height: height, into: base, bufferSize: bufferSize)
        }
        FilamentBridge.endFrame(renderer)

        guard readSuccess else { return false }

        // Convert RGBA -> Pre-multiplied BGRA for Windows AC_SRC_ALPHA
        let pixelCount = Int(width * height)
        rgbaBuffer.withUnsafeBufferPointer { src in
            guard let srcPtr = src.baseAddress else { return }
            var srcIdx = 0
            var dstIdx = 0
            for _ in 0..<pixelCount {
                let r = srcPtr[srcIdx + 0]
                let g = srcPtr[srcIdx + 1]
                let b = srcPtr[srcIdx + 2]
                let a = srcPtr[srcIdx + 3]

                if a == 0 {
                    dibBits[dstIdx + 0] = 0
                    dibBits[dstIdx + 1] = 0
                    dibBits[dstIdx + 2] = 0
                    dibBits[dstIdx + 3] = 0
                } else if a == 255 {
                    dibBits[dstIdx + 0] = b
                    dibBits[dstIdx + 1] = g
                    dibBits[dstIdx + 2] = r
                    dibBits[dstIdx + 3] = 255
                } else {
                    let alphaScale = Float(a) / 255.0
                    dibBits[dstIdx + 0] = UInt8(Float(b) * alphaScale)
                    dibBits[dstIdx + 1] = UInt8(Float(g) * alphaScale)
                    dibBits[dstIdx + 2] = UInt8(Float(r) * alphaScale)
                    dibBits[dstIdx + 3] = a
                }

                srcIdx += 4
                dstIdx += 4
            }
        }

        // Present to DWM compositor via UpdateLayeredWindow
        let screenDC = win32GetDC(nil)
        defer { _ = win32ReleaseDC(nil, screenDC) }

        var ptSrc = POINT(x: 0, y: 0)
        var size = SIZE(cx: Int32(width), cy: Int32(height))
        var ptDst = POINT(x: currentPositionX, y: currentPositionY)
        var blend = BLENDFUNCTION(
            BlendOp: kAC_SRC_OVER,
            BlendFlags: 0,
            SourceConstantAlpha: 255,
            AlphaFormat: kAC_SRC_ALPHA
        )

        _ = win32UpdateLayeredWindow(
            UnsafeRawPointer(hwnd),
            screenDC,
            &ptDst,
            &size,
            memDC,
            &ptSrc,
            0,
            &blend,
            kULW_ALPHA
        )

        return true
    }

    // MARK: - Model & Blend Shapes

    public func loadModel(from url: URL) throws {
        try model.loadGlb(at: url)
    }

    public func setBlendShape(name: String, weight: Float) {
        model.setBlendShape(name: name, weight: weight)
    }

    public func setBlendShape(index: Int, weight: Float) {
        model.setBlendShape(index: index, weight: weight)
    }
}
