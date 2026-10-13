// =============================================================================
// FilamentSwift — WinUI 3 demo host (Windows)
//
// Architecture:
//   Win32 top-level window  (WS_CLIPCHILDREN)
//     ├── render child HWND  -> Filament swap chain + mouse Orbit/Pan/Zoom
//     └── panel  child HWND  -> WinUI 3 XAML island (DesktopWindowXamlSource)
// =============================================================================

@preconcurrency import WinSDK
import Foundation
import Filament
import FilamentWin32
@preconcurrency import CWinRT
@preconcurrency @_spi(WinRTInternal) @_spi(WinRTImplements) import WindowsFoundation
@preconcurrency import UWP
@preconcurrency import WinAppSDK
@preconcurrency @_spi(WinRTInternal) import WinUI

// Win32 mouse message constants
private let WM_DESTROY: UInt32 = 0x0002
private let WM_SIZE: UInt32 = 0x0005
private let WM_QUIT: UInt32 = 0x0012
private let WM_ERASEBKGND: UInt32 = 0x0014
private let WM_KEYDOWN: UInt32 = 0x0100
private let WM_MOUSEMOVE: UInt32 = 0x0200
private let WM_LBUTTONDOWN: UInt32 = 0x0201
private let WM_LBUTTONUP: UInt32 = 0x0202
private let WM_LBUTTONDBLCLK: UInt32 = 0x0203
private let WM_RBUTTONDOWN: UInt32 = 0x0204
private let WM_RBUTTONUP: UInt32 = 0x0205
private let WM_MBUTTONDOWN: UInt32 = 0x0207
private let WM_MBUTTONUP: UInt32 = 0x0208
private let WM_MOUSEWHEEL: UInt32 = 0x020A

private let MK_LBUTTON: UInt64 = 0x0001
private let MK_RBUTTON: UInt64 = 0x0002
private let MK_SHIFT: UInt64 = 0x0004
private let MK_MBUTTON: UInt64 = 0x0010
private let CS_VREDRAW: UInt32 = 0x0001
private let CS_HREDRAW: UInt32 = 0x0002
private let CS_DBLCLKS: UInt32 = 0x0008
private let CW_USEDEFAULT: Int32 = Int32(bitPattern: 0x8000_0000)
private let PM_REMOVE: UInt32 = 0x0001
private let QS_ALLINPUT: UInt32 = 0x04FF
private let MWMO_INPUTAVAILABLE: UInt32 = 0x0004
private let WS_CLIPCHILDREN: UInt32 = 0x0200_0000
private let WS_CLIPSIBLINGS: UInt32 = 0x0400_0000
private let WS_VISIBLE: UInt32 = 0x1000_0000
private let WS_CHILD: UInt32 = 0x4000_0000
private let WS_OVERLAPPEDWINDOW: UInt32 = 0x00CF_0000
private let kTrue: Int32 = 1

private struct MARGINS {
    var cxLeftWidth: Int32
    var cxRightWidth: Int32
    var cyTopHeight: Int32
    var cyBottomHeight: Int32
}

@_silgen_name("MoveWindow")
private func win32MoveWindow(_ hWnd: UnsafeRawPointer?, _ x: Int32, _ y: Int32, _ nWidth: Int32, _ nHeight: Int32, _ bRepaint: Int32) -> Int32

@_silgen_name("GetClientRect")
private func win32GetClientRect(_ hWnd: UnsafeRawPointer?, _ lpRect: UnsafeMutablePointer<RECT>) -> Int32

@_silgen_name("PeekMessageW")
private func win32PeekMessageW(
    _ lpMsg: UnsafeMutablePointer<MSG>,
    _ hWnd: UnsafeRawPointer?,
    _ wMsgFilterMin: UInt32,
    _ wMsgFilterMax: UInt32,
    _ wRemoveMsg: UInt32
) -> Int32

@_silgen_name("MsgWaitForMultipleObjectsEx")
private func win32MsgWaitForMultipleObjectsEx(
    _ nCount: UInt32,
    _ pHandles: UnsafeRawPointer?,
    _ dwMilliseconds: UInt32,
    _ dwWakeMask: UInt32,
    _ dwFlags: UInt32
) -> UInt32

@_silgen_name("SetCapture")
private func win32SetCapture(_ hWnd: UnsafeRawPointer?) -> UnsafeRawPointer?

@_silgen_name("ReleaseCapture")
private func win32ReleaseCapture() -> Int32

@_silgen_name("SetFocus")
private func win32SetFocus(_ hWnd: UnsafeRawPointer?) -> UnsafeRawPointer?

private let GWL_EXSTYLE: Int32 = -20
private let WS_EX_LAYERED: UInt32 = 0x0008_0000
private let LWA_COLORKEY: UInt32 = 0x0001
private let LWA_ALPHA: UInt32 = 0x0002

private let SWP_NOSIZE: UInt32 = 0x0001
private let SWP_NOMOVE: UInt32 = 0x0002
private let SWP_NOZORDER: UInt32 = 0x0004
private let SWP_FRAMECHANGED: UInt32 = 0x0020

@_silgen_name("GetWindowLongW")
private func win32GetWindowLongW(_ hWnd: UnsafeRawPointer?, _ nIndex: Int32) -> Int32

@_silgen_name("SetWindowLongW")
private func win32SetWindowLongW(_ hWnd: UnsafeRawPointer?, _ nIndex: Int32, _ dwNewLong: Int32) -> Int32

@_silgen_name("SetLayeredWindowAttributes")
private func win32SetLayeredWindowAttributes(_ hwnd: UnsafeRawPointer?, _ crKey: UInt32, _ bAlpha: UInt8, _ dwFlags: UInt32) -> Int32

@_silgen_name("SetWindowPos")
private func win32SetWindowPos(
    _ hWnd: UnsafeRawPointer?,
    _ hWndInsertAfter: UnsafeRawPointer?,
    _ X: Int32, _ Y: Int32, _ cx: Int32, _ cy: Int32,
    _ uFlags: UInt32
) -> Int32

@_silgen_name("DwmSetWindowAttribute")
private func win32DwmSetWindowAttribute(
    _ hwnd: UnsafeRawPointer?,
    _ dwAttribute: UInt32,
    _ pvAttribute: UnsafeRawPointer,
    _ cbAttribute: UInt32
) -> Int32

@_silgen_name("DwmExtendFrameIntoClientArea")
private func win32DwmExtendFrameIntoClientArea(
    _ hWnd: UnsafeRawPointer?,
    _ pMarInset: UnsafePointer<MARGINS>?
) -> Int32

/// Main-actor-isolated host managing the Win32 windows, XAML island, and Filament scene.
@MainActor
final class DemoHost {
    static let shared = DemoHost()

    // Filament.
    private(set) var engine: FilamentEngine!
    private(set) var model: FilamentModel!
    private(set) var pbr: FilamentPBRController!
    private(set) var camera: FilamentOrbitCamera!
    private var hostView: FilamentWin32View?

    // Model & animation state.
    private(set) var currentModelName: String?
    private var animationTime: Float = 0
    private var lastFrame: Double = 0
    private var lastMouseX: Int?
    private var lastMouseY: Int?

    // Floating assistant overlay.
    private var overlay: FilamentOverlayWindow?
    public private(set) var isOverlayVisible = false
    private var currentModelUrl: URL?

    // Windows.
    private(set) var topHwnd: HWND!
    private var renderChild: HWND?
    private var panelChild: HWND?
    private var panelWidth: Int32 = 340

    /// The XAML island hosting the control panel, and its retained Swift controller.
    private var winuiApp: DemoApplication?
    private var xamlSource: DesktopWindowXamlSource?
    private var controlPanel: ControlPanel?

    private let className = "FilamentSwiftWinUI3DemoClass"
    private let panelClassName = "FilamentSwiftPanelClass"
    private let renderClassName = "FilamentSwiftRenderClass"

    // MARK: - Lifecycle

    func run() -> Int32 {
        _ = RoInitialize(RO_INIT_SINGLETHREADED)
        guard WinAppSDKBootstrap.initializeRuntime() else { return 1 }
        winuiApp = WinAppSDKBootstrap.createWinUIApplication()
        setupFilament()
        createWindows()
        createPanelIsland()
        lastFrame = currentMediaTimeSeconds()

        let exitCode = messageLoop()
        shutdown()
        return exitCode
    }

    private func setupFilament() {
        engine = FilamentEngine(backend: .vulkan)
        pbr = FilamentPBRController(engine: engine)
        model = FilamentModel(engine: engine)
        camera = FilamentOrbitCamera(engine: engine)
    }

    // MARK: - Windows & XAML Island

    private func createWindows() {
        let hInstance = GetModuleHandleW(nil)

        registerChildClass(renderClassName)
        registerChildClass(panelClassName)

        className.withCString(encodedAs: UTF16.self) { classWide in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.style = UINT(CS_HREDRAW | CS_VREDRAW)
            wc.lpfnWndProc = { hwnd, msg, wParam, lParam -> LRESULT in
                MainActor.assumeIsolated { DemoHost.shared.handleMessage(hwnd, msg, wParam, lParam) }
            }
            wc.hInstance = hInstance
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDC_ARROW
            wc.lpszClassName = classWide
            _ = RegisterClassExW(&wc)

            let title = "Filament Swift — WinUI 3 PBR Demo"
            title.withCString(encodedAs: UTF16.self) { titleWide in
                guard let hwnd = CreateWindowExW(
                    0, classWide, titleWide,
                    DWORD(WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN),
                    CW_USEDEFAULT, CW_USEDEFAULT, 1220, 820,
                    nil, nil, hInstance, nil
                ) else {
                    fatalError("[WinUI3Demo] Failed to create the top-level window")
                }
                topHwnd = hwnd
                var useDarkMode: Int32 = 1
                _ = win32DwmSetWindowAttribute(UnsafeRawPointer(hwnd), 20, &useDarkMode, 4)
                _ = ShowWindow(hwnd, SW_SHOW)
                _ = UpdateWindow(hwnd)
            }
        }

        renderChild = renderClassName.withCString(encodedAs: UTF16.self) { wide in
            CreateWindowExW(0, wide, nil, DWORD(WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS),
                            0, 0, 100, 100, topHwnd, nil, GetModuleHandleW(nil), nil)
        }
        panelChild = panelClassName.withCString(encodedAs: UTF16.self) { wide in
            CreateWindowExW(0, wide, nil, DWORD(WS_CHILD | WS_VISIBLE | WS_CLIPCHILDREN | WS_CLIPSIBLINGS),
                            0, 0, Int32(panelWidth), 100, topHwnd, nil, GetModuleHandleW(nil), nil)
        }

        layoutChildren()

        if let renderChild {
            let view = FilamentWin32View(engine: engine)
            var rect = RECT()
            _ = win32GetClientRect(UnsafeRawPointer(renderChild), &rect)
            view.attach(hwnd: renderChild,
                        width: UInt32(max(1, rect.right - rect.left)),
                        height: UInt32(max(1, rect.bottom - rect.top)))
            hostView = view
            let c = currentStudioPreset.color
            engine.setClearColor(r: c.r, g: c.g, b: c.b, a: 1.0)
            if let first = ModelDiscovery.discoverModels().first {
                loadModel(from: first.url)
            }
        }
    }

    private func registerChildClass(_ name: String) {
        name.withCString(encodedAs: UTF16.self) { wide in
            var wc = WNDCLASSEXW()
            wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
            wc.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS)
            wc.lpfnWndProc = { hwnd, msg, wParam, lParam -> LRESULT in
                MainActor.assumeIsolated { DemoHost.shared.handleMessage(hwnd, msg, wParam, lParam) }
            }
            wc.hInstance = GetModuleHandleW(nil)
            wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512))
            wc.lpszClassName = wide
            _ = RegisterClassExW(&wc)
        }
    }

    private func layoutChildren() {
        guard let topHwnd else { return }
        var client = RECT()
        _ = win32GetClientRect(UnsafeRawPointer(topHwnd), &client)
        let width = client.right - client.left
        let height = max(1, client.bottom - client.top)
        let renderWidth = max(1, width - panelWidth)

        if let renderChild {
            _ = win32MoveWindow(UnsafeRawPointer(renderChild), 0, 0, renderWidth, height, kTrue)
        }
        if let panelChild {
            _ = win32MoveWindow(UnsafeRawPointer(panelChild), renderWidth, 0, panelWidth, height, kTrue)
        }
        if let bridge = xamlSource?.siteBridge {
            let bridgeHwndVal = bridge.windowId.value
            if bridgeHwndVal != 0,
               let bridgeHwnd = HWND(bitPattern: UInt(truncatingIfNeeded: bridgeHwndVal)) {
                _ = win32MoveWindow(UnsafeRawPointer(bridgeHwnd), 0, 0, panelWidth, height, kTrue)
            }
            try? bridge.moveAndResize(UWP.RectInt32(x: 0, y: 0, width: panelWidth, height: height))
        }
    }

    private func createPanelIsland() {
        guard let panelChild else { return }
        do {
            let source = DesktopWindowXamlSource()
            let windowId = WinAppSDK.WindowId(value: UInt64(UInt(bitPattern: panelChild)))
            try source.initialize(windowId)
            let panel = ControlPanel(host: self)
            source.content = panel.rootElement
            controlPanel = panel
            xamlSource = source

            var rect = RECT()
            _ = win32GetClientRect(UnsafeRawPointer(panelChild), &rect)
            let w = max(1, rect.right - rect.left)
            let h = max(1, rect.bottom - rect.top)
            if let bridge = source.siteBridge {
                let bridgeHwndVal = bridge.windowId.value
                if bridgeHwndVal != 0,
                   let bridgeHwnd = HWND(bitPattern: UInt(truncatingIfNeeded: bridgeHwndVal)) {
                    _ = win32MoveWindow(UnsafeRawPointer(bridgeHwnd), 0, 0, w, h, kTrue)
                }
                try bridge.moveAndResize(UWP.RectInt32(x: 0, y: 0, width: w, height: h))
                try bridge.show()
            }
            if currentModelName != nil {
                panel.syncModelAndAnimations()
            }
        } catch {
            print("[WinUI3Demo] Failed to create the XAML island: \(error)")
        }
    }

    // MARK: - Message Loop & Mouse Input

    private func handleMessage(_ hwnd: HWND?, _ msg: UInt32, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch msg {
        case WM_DESTROY:
            if hwnd == topHwnd {
                PostQuitMessage(0)
            }
            return 0
        case WM_ERASEBKGND:
            if hwnd == renderChild {
                return 1
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_SIZE:
            if hwnd == topHwnd, wParam != 1 {
                layoutChildren()
                hostView?.syncViewportWithWindow()
            }
            return 0
        case WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
            if hwnd == renderChild {
                _ = win32SetFocus(UnsafeRawPointer(hwnd))
                _ = win32SetCapture(UnsafeRawPointer(hwnd))
                lastMouseX = Int(Int16(truncatingIfNeeded: Int64(lParam) & 0xFFFF))
                lastMouseY = Int(Int16(truncatingIfNeeded: (Int64(lParam) >> 16) & 0xFFFF))
                return 0
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP:
            if hwnd == renderChild {
                let mask = MK_LBUTTON | MK_RBUTTON | MK_MBUTTON
                if (UInt64(wParam) & mask) == 0 {
                    _ = win32ReleaseCapture()
                }
                return 0
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_LBUTTONDBLCLK:
            if hwnd == renderChild {
                camera?.reset()
                return 0
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_MOUSEMOVE:
            if hwnd == renderChild {
                let flags = UInt64(wParam)
                let x = Int(Int16(truncatingIfNeeded: Int64(lParam) & 0xFFFF))
                let y = Int(Int16(truncatingIfNeeded: (Int64(lParam) >> 16) & 0xFFFF))
                let prevX = lastMouseX ?? x
                let prevY = lastMouseY ?? y
                lastMouseX = x
                lastMouseY = y

                let dx = Double(x - prevX)
                let dy = Double(y - prevY)
                let leftDown = (flags & MK_LBUTTON) != 0
                let rightDown = (flags & MK_RBUTTON) != 0
                let middleDown = (flags & MK_MBUTTON) != 0
                let shiftDown = (flags & MK_SHIFT) != 0

                if rightDown || middleDown || (leftDown && shiftDown) {
                    camera?.pan(deltaX: dx, deltaY: dy)
                } else if leftDown {
                    camera?.orbit(deltaX: dx, deltaY: dy)
                }
                return 0
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_MOUSEWHEEL:
            let delta = Double(Int16(truncatingIfNeeded: (UInt64(wParam) >> 16) & 0xFFFF)) / 120.0
            camera?.zoom(delta: delta * 1.5)
            return 0
        case WM_KEYDOWN:
            let key = Int(wParam)
            switch key {
            case 65: // 'A'
                toggleAssistantOverlay()
                return 0
            case 66, 84: // 'B' or 'T'
                cycleNextStudioPreset()
                return 0
            case 82: // 'R'
                resetCamera()
                return 0
            case 79: // 'O'
                openModelFromDialog()
                return 0
            case 32: // VK_SPACE
                if let camera {
                    camera.isAutoOrbiting.toggle()
                    controlPanel?.syncAutoOrbit()
                }
                return 0
            default:
                break
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }

    private func messageLoop() -> Int32 {
        var msg = MSG()
        while true {
            while win32PeekMessageW(&msg, nil, 0, 0, PM_REMOVE) != 0 {
                if msg.message == UINT(WM_QUIT) {
                    return Int32(msg.wParam)
                }
                _ = TranslateMessage(&msg)
                _ = DispatchMessageW(&msg)
            }
            onFrame()
            _ = win32MsgWaitForMultipleObjectsEx(0, nil, 8, QS_ALLINPUT, MWMO_INPUTAVAILABLE)
        }
    }

    // MARK: - Rendering & Teardown

    private func onFrame() {
        guard let hostView else { return }
        let now = currentMediaTimeSeconds()
        let dt = Float(min(0.25, max(0, now - lastFrame)))
        lastFrame = now

        if model.hasAnimations {
            animationTime += dt
            let duration = model.activeAnimationDuration
            if duration > 0.001 {
                animationTime = animationTime.truncatingRemainder(dividingBy: duration)
            }
            model.applyAnimation(time: animationTime)
        }

        camera.update(dt: dt)
        hostView.renderFrame()

        if let overlay, isOverlayVisible {
            overlay.camera.update(dt: dt)
            if overlay.model.hasAnimations {
                overlay.model.applyAnimation(time: animationTime)
            }
            overlay.renderFrame()
        }
    }

    private func currentMediaTimeSeconds() -> Double {
        var ts = LARGE_INTEGER()
        var freq = LARGE_INTEGER()
        QueryPerformanceCounter(&ts)
        QueryPerformanceFrequency(&freq)
        return freq.QuadPart > 0 ? Double(ts.QuadPart) / Double(freq.QuadPart) : 0
    }

    private func shutdown() {
        overlay?.hide()
        overlay = nil
        hostView?.stopRendering()
        model?.unload()
        model = nil
        hostView = nil
        controlPanel = nil
        xamlSource = nil
        winuiApp = nil
    }

    // MARK: - Model + PBR Actions

    func loadModel(from url: URL) {
        currentModelUrl = url
        animationTime = 0
        let asset = ModelAsset(url: url)
        do {
            try model.loadGlb(at: asset.url)
            currentModelName = asset.name
            try? overlay?.loadModel(from: asset.url)
        } catch {
            print("[WinUI3Demo] Failed to load \(asset.url.path): \(error)")
            model.unload()
            currentModelName = nil
        }
        if model.hasAnimations {
            model.selectAnimation(at: 0)
        }
        model.setRotation(radiansY: 0)
        controlPanel?.syncModelAndAnimations()
    }

    func openModelFromDialog() {
        guard let url = WinUI3FileDialog.promptForGlbFile(owner: topHwnd) else { return }
        loadModel(from: url)
    }

    func resetCamera() {
        camera?.reset()
    }

    func selectAnimation(at index: Int) {
        animationTime = 0
        model?.selectAnimation(at: index)
    }

    func pbrSettings() -> FilamentPBRSettings { pbr.settings }
    func mutatePBR(_ body: (inout FilamentPBRSettings) -> Void) { pbr.mutate(body) }
    func resetPBR() { pbr.reset() }

    // MARK: - Floating Assistant Overlay

    func toggleAssistantOverlay() {
        if overlay == nil {
            let ov = FilamentOverlayWindow(width: 380, height: 380)
            if let currentModelUrl {
                try? ov.loadModel(from: currentModelUrl)
            }
            ov.camera.isAutoOrbiting = true
            overlay = ov
        }

        isOverlayVisible.toggle()
        if isOverlayVisible {
            overlay?.show(atX: 120, y: 120)
        } else {
            overlay?.hide()
        }
        controlPanel?.syncAssistantOverlayUI()
    }

    func setOverlayClickThrough(_ enabled: Bool) {
        overlay?.isClickThrough = enabled
    }

    // MARK: - Studio Background

    private(set) var currentStudioPreset: StudioPreset = .studioSlate

    func setStudioPreset(_ preset: StudioPreset) {
        currentStudioPreset = preset
        let c = preset.color
        engine.setClearColor(r: c.r, g: c.g, b: c.b, a: 1.0)
        controlPanel?.syncBackgroundUI()
    }

    func cycleNextStudioPreset() {
        let all = StudioPreset.allCases
        let currentIdx = all.firstIndex(of: currentStudioPreset) ?? 0
        let next = all[(currentIdx + 1) % all.count]
        setStudioPreset(next)
    }
}

enum StudioPreset: String, CaseIterable {
    case studioSlate = "Studio Slate (#1E222A)"
    case darkCharcoal = "Dark Charcoal (#121316)"
    case neutralGray = "Neutral Gray (#404040)"
    case pureBlack = "Pure Black (#000000)"
    case studioWhite = "Studio White (#F5F5F7)"

    var color: (r: Float, g: Float, b: Float) {
        switch self {
        case .studioSlate:   return (0.12, 0.13, 0.16)
        case .darkCharcoal:  return (0.07, 0.07, 0.09)
        case .neutralGray:   return (0.25, 0.25, 0.25)
        case .pureBlack:     return (0.00, 0.00, 0.00)
        case .studioWhite:   return (0.96, 0.96, 0.97)
        }
    }
}
