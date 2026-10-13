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
private let CS_DBLCLKS: UInt32 = 0x0008

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
    private var renderTimer: DispatcherQueueTimer?

    // Model & animation state.
    private(set) var currentModelName: String?
    private var animationTime: Float = 0
    private var lastFrame: Double = 0
    private var lastMouseX: Int?
    private var lastMouseY: Int?

    // Windows.
    private(set) var topHwnd: HWND!
    private var renderChild: HWND?
    private var panelChild: HWND?
    private var panelWidth: Int32 = 320

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
        startRenderTimer()

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
                    CW_USEDEFAULT, CW_USEDEFAULT, 1180, 780,
                    nil, nil, hInstance, nil
                ) else {
                    fatalError("[WinUI3Demo] Failed to create the top-level window")
                }
                topHwnd = hwnd
                ShowWindow(hwnd, SW_SHOW)
                UpdateWindow(hwnd)
            }
        }

        renderChild = renderClassName.withCString(encodedAs: UTF16.self) { wide in
            CreateWindowExW(0, wide, nil, DWORD(WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS),
                            0, 0, 100, 100, topHwnd, nil, GetModuleHandleW(nil), nil)
        }
        panelChild = panelClassName.withCString(encodedAs: UTF16.self) { wide in
            CreateWindowExW(0, wide, nil, DWORD(WS_CHILD | WS_VISIBLE),
                            0, 0, Int32(panelWidth), 100, topHwnd, nil, GetModuleHandleW(nil), nil)
        }

        layoutChildren()

        if let renderChild {
            let view = FilamentWin32View()
            var rect = RECT()
            GetClientRect(renderChild, &rect)
            view.attach(hwnd: renderChild,
                        width: UInt32(max(1, rect.right - rect.left)),
                        height: UInt32(max(1, rect.bottom - rect.top)))
            hostView = view
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
        var client = RECT()
        GetClientRect(topHwnd, &client)
        let width = client.right - client.left
        let height = client.bottom - client.top
        let renderWidth = max(1, width - panelWidth)

        if let renderChild {
            MoveWindow(renderChild, 0, 0, renderWidth, height, true)
        }
        if let panelChild {
            MoveWindow(panelChild, renderWidth, 0, panelWidth, height, true)
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
        } catch {
            print("[WinUI3Demo] Failed to create the XAML island: \(error)")
        }
    }

    // MARK: - Message Loop & Mouse Input

    private func handleMessage(_ hwnd: HWND, _ msg: UInt32, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch msg {
        case WM_DESTROY:
            PostQuitMessage(0)
            return 0
        case WM_SIZE:
            layoutChildren()
            hostView?.syncViewportWithWindow()
            return 0
        case WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
            if hwnd == renderChild {
                _ = SetFocus(hwnd)
                _ = SetCapture(hwnd)
                lastMouseX = Int(Int16(truncatingIfNeeded: Int64(lParam) & 0xFFFF))
                lastMouseY = Int(Int16(truncatingIfNeeded: (Int64(lParam) >> 16) & 0xFFFF))
                return 0
            }
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        case WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP:
            if hwnd == renderChild {
                let mask = MK_LBUTTON | MK_RBUTTON | MK_MBUTTON
                if (UInt64(wParam) & mask) == 0 {
                    ReleaseCapture()
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
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }

    private func messageLoop() -> Int32 {
        var msg = MSG()
        while true {
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) {
                    return Int32(msg.wParam)
                }
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }
            _ = MsgWaitForMultipleObjects(0, nil, false, 8, QS_ALLINPUT)
        }
    }

    // MARK: - Rendering & Teardown

    private func startRenderTimer() {
        do {
            let controller = try DispatcherQueueController.createOnCurrentThread()
            let timer = controller.createTimer()
            timer.interval = Duration(milliseconds: 1000.0 / 60.0)
            timer.add_Tick { [weak self] _, _ in
                MainActor.assumeIsolated { self?.onFrame() }
            }
            timer.start()
            renderTimer = timer
        } catch {
            print("[WinUI3Demo] Failed to start the render timer: \(error)")
        }
    }

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
    }

    private func currentMediaTimeSeconds() -> Double {
        var ts = LARGE_INTEGER()
        var freq = LARGE_INTEGER()
        QueryPerformanceCounter(&ts)
        QueryPerformanceFrequency(&freq)
        return freq.QuadPart > 0 ? Double(ts.QuadPart) / Double(freq.QuadPart) : 0
    }

    private func shutdown() {
        renderTimer?.stop()
        renderTimer = nil
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
        animationTime = 0
        let asset = ModelAsset(url: url)
        do {
            try model.loadGlb(at: asset.url)
            currentModelName = asset.name
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
}
