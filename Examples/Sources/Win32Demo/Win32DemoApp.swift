import Foundation
import WinSDK
import Filament
import FilamentWin32

/// Pure Win32 desktop demo application in Swift.
///
/// Integrates Google Filament with a native Win32 host window: an overlapped
/// frame window, a dedicated child `HWND` that owns the Filament `SwapChain` and
/// receives mouse Orbit / Pan / Zoom input, and a side control panel built from
/// stock Win32 controls (`Win32ControlPanel`).
@MainActor
final class Win32DemoApp {
    static weak var shared: Win32DemoApp?

    private static let frameClassName = "FilamentWin32DemoFrameClass"
    private static let panelClassName = "FilamentWin32DemoPanelClass"
    private static let renderClassName = "FilamentWin32DemoRenderClass"

    private var hwnd: HWND?
    private var renderChild: HWND?
    private var controlPanel: Win32ControlPanel?
    private var scene: Win32SceneController?

    private var isRunning: Bool = true
    private var lastFrameTime: Double = 0.0

    func run() {
        Self.shared = self
        print("[Win32Demo] Initializing Win32 host window...")
        CoInitializeEx(nil, COINIT_APARTMENTTHREADED)
        defer { CoUninitialize() }

        guard registerWindowClasses() else {
            print("[Win32Demo] Failed to register window classes.")
            return
        }

        guard createWindow() else {
            print("[Win32Demo] Failed to create desktop host window.")
            return
        }

        setupFilament()
        enterMessageLoop()
        shutdown()
    }

    // MARK: - Window Classes & Creation

    private func registerWindowClasses() -> Bool {
        let hInstance = GetModuleHandleW(nil)
        let arrow = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDC_ARROW

        return Self.frameClassName.withCString(encodedAs: UTF16.self) { frameWide in
            Self.panelClassName.withCString(encodedAs: UTF16.self) { panelWide in
                Self.renderClassName.withCString(encodedAs: UTF16.self) { renderWide in
                    var frame = WNDCLASSEXW()
                    frame.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                    frame.style = UINT(CS_HREDRAW | CS_VREDRAW)
                    frame.lpfnWndProc = { hwnd, uMsg, wParam, lParam -> LRESULT in
                        switch uMsg {
                        case WM_DESTROY:
                            PostQuitMessage(0)
                            return 0
                        case WM_KEYDOWN:
                            let key = lowWord(UInt64(wParam))
                            if key == 27 { // VK_ESCAPE
                                PostQuitMessage(0)
                                return 0
                            }
                            Task { @MainActor in
                                Win32DemoApp.shared?.handleKeyDown(key: key)
                            }
                            return 0
                        case WM_MOUSEWHEEL:
                            let delta = wheelDelta(UInt64(wParam))
                            Task { @MainActor in
                                Win32DemoApp.shared?.scene?.handleMouseWheel(delta: delta)
                            }
                            return 0
                        case WM_SIZE:
                            Task { @MainActor in
                                Win32DemoApp.shared?.handleResize()
                            }
                            return 0
                        default:
                            if Win32DemoApp.dispatchControlMessage(uMsg, UInt64(wParam), lParam) {
                                return 1
                            }
                            return DefWindowProcW(hwnd, uMsg, wParam, lParam)
                        }
                    }
                    frame.hInstance = hInstance
                    frame.lpszClassName = frameWide
                    frame.hCursor = arrow
                    guard RegisterClassExW(&frame) != 0 else { return false }

                    var panel = WNDCLASSEXW()
                    panel.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                    panel.style = UINT(CS_HREDRAW | CS_VREDRAW)
                    panel.lpfnWndProc = { hwnd, uMsg, wParam, lParam -> LRESULT in
                        if Win32DemoApp.dispatchControlMessage(uMsg, UInt64(wParam), lParam) {
                            return 1
                        }
                        return DefWindowProcW(hwnd, uMsg, wParam, lParam)
                    }
                    panel.hInstance = hInstance
                    panel.lpszClassName = panelWide
                    panel.hCursor = arrow
                    guard RegisterClassExW(&panel) != 0 else { return false }

                    var render = WNDCLASSEXW()
                    render.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
                    render.style = UINT(CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS)
                    render.lpfnWndProc = { hwnd, uMsg, wParam, lParam -> LRESULT in
                        switch uMsg {
                        case WM_LBUTTONDOWN, WM_RBUTTONDOWN, WM_MBUTTONDOWN:
                            _ = win32SetFocus(UnsafeRawPointer(hwnd))
                            _ = win32SetCapture(UnsafeRawPointer(hwnd))
                            let x = mouseX(lParam)
                            let y = mouseY(lParam)
                            Task { @MainActor in
                                Win32DemoApp.shared?.scene?.handleMouseDown(x: x, y: y)
                            }
                            return 0
                        case WM_LBUTTONUP, WM_RBUTTONUP, WM_MBUTTONUP:
                            let mask = MK_LBUTTON | MK_RBUTTON | MK_MBUTTON
                            if (UInt64(wParam) & mask) == 0 {
                                _ = win32ReleaseCapture()
                            }
                            return 0
                        case WM_LBUTTONDBLCLK:
                            Task { @MainActor in
                                Win32DemoApp.shared?.scene?.resetCamera()
                            }
                            return 0
                        case WM_MOUSEMOVE:
                            let flags = UInt64(wParam)
                            if (flags & (MK_LBUTTON | MK_RBUTTON | MK_MBUTTON)) != 0 {
                                let x = mouseX(lParam)
                                let y = mouseY(lParam)
                                Task { @MainActor in
                                    Win32DemoApp.shared?.scene?.handleMouseMove(x: x, y: y, flags: flags)
                                }
                            }
                            return 0
                        case WM_MOUSEWHEEL:
                            let delta = wheelDelta(UInt64(wParam))
                            Task { @MainActor in
                                Win32DemoApp.shared?.scene?.handleMouseWheel(delta: delta)
                            }
                            return 0
                        default:
                            return DefWindowProcW(hwnd, uMsg, wParam, lParam)
                        }
                    }
                    render.hInstance = hInstance
                    render.lpszClassName = renderWide
                    render.hCursor = arrow
                    return RegisterClassExW(&render) != 0
                }
            }
        }
    }

    private func createWindow() -> Bool {
        let windowTitle = "Filament Swift — Win32 Demo (Windows)"

        let hwnd = Self.frameClassName.withCString(encodedAs: UTF16.self) { classWide in
            windowTitle.withCString(encodedAs: UTF16.self) { titleWide in
                CreateWindowExW(
                    0,
                    classWide,
                    titleWide,
                    DWORD(WS_OVERLAPPEDWINDOW | WS_VISIBLE),
                    CW_USEDEFAULT,
                    CW_USEDEFAULT,
                    1100,
                    820,
                    nil,
                    nil,
                    GetModuleHandleW(nil),
                    nil
                )
            }
        }
        guard let hwnd else { return false }
        self.hwnd = hwnd

        self.controlPanel = Win32ControlPanel(parent: hwnd, panelClassName: Self.panelClassName)
        return true
    }

    private func setupFilament() {
        guard let hwnd else { return }

        var clientRect = RECT()
        GetClientRect(hwnd, &clientRect)
        let clientWidth = Int32(max(0, clientRect.right - clientRect.left))
        let clientHeight = Int32(max(0, clientRect.bottom - clientRect.top))
        let renderWidth = max(1, clientWidth - Win32ControlPanel.panelWidth)

        let createdChild = Self.renderClassName.withCString(encodedAs: UTF16.self) { classWide in
            CreateWindowExW(
                0,
                classWide,
                nil,
                DWORD(WS_CHILD | WS_VISIBLE | WS_TABSTOP),
                0,
                0,
                renderWidth,
                clientHeight,
                hwnd,
                nil,
                GetModuleHandleW(nil),
                nil
            )
        }
        guard let renderChild = createdChild else {
            print("[Win32Demo] Failed to create the Filament render child window.")
            return
        }
        self.renderChild = renderChild

        layoutRegions()
        controlPanel?.layoutControls()

        let width = UInt32(max(1, renderWidth))
        let height = UInt32(max(1, clientHeight))
        self.scene = Win32SceneController(renderChild: renderChild, width: width, height: height)

        print("[Win32Demo] Filament host view attached to render HWND \(renderChild).")
        print("[Win32Demo] Mouse: Left-Drag Orbit | Right/Middle/Shift-Drag Pan | Wheel Zoom | Double-Click Reset")
        print("[Win32Demo] Keys:  [O] Open Model | [R] Reset View | [Up] Next Anim | [Space] Auto-Orbit | [ESC] Quit")
    }

    private func layoutRegions() {
        guard let hwnd else { return }

        var clientRect = RECT()
        guard GetClientRect(hwnd, &clientRect) else { return }
        let clientWidth = Int32(max(0, clientRect.right - clientRect.left))
        let clientHeight = Int32(max(0, clientRect.bottom - clientRect.top))
        let panelWidth = Win32ControlPanel.panelWidth
        let renderWidth = max(1, clientWidth - panelWidth)

        if let renderChild {
            _ = win32MoveWindow(UnsafeRawPointer(renderChild), 0, 0, renderWidth, clientHeight, kTrue)
        }
        if let panelHwnd = controlPanel?.panelHwnd {
            _ = win32MoveWindow(UnsafeRawPointer(panelHwnd), renderWidth, 0, panelWidth, clientHeight, kTrue)
        }
    }

    // MARK: - Actions & Input

    func openModelFromDialog() {
        guard let url = Win32FileDialog.promptForGlbFile(owner: hwnd) else { return }
        scene?.openModel(at: url)
    }

    func handleKeyDown(key: Int) {
        switch key {
        case 79: // 'O'
            openModelFromDialog()
        case 82: // 'R'
            scene?.resetCamera()
        case 38: // VK_UP
            scene?.cycleNextAnimation()
        case 32: // VK_SPACE
            scene?.toggleAutoOrbit()
        default:
            break
        }
    }

    func handleResize() {
        layoutRegions()
        controlPanel?.layoutControls()
        scene?.syncViewportWithWindow()
    }

    // MARK: - Message Loop & Routing

    private func enterMessageLoop() {
        var msg = MSG()
        lastFrameTime = ProcessInfo.processInfo.systemUptime

        while isRunning {
            while PeekMessageW(&msg, nil, 0, 0, UINT(PM_REMOVE)) {
                if msg.message == UINT(WM_QUIT) {
                    isRunning = false
                    break
                }
                TranslateMessage(&msg)
                DispatchMessageW(&msg)
            }

            if !isRunning { break }

            _ = MsgWaitForMultipleObjectsEx(0, nil, 1000 / 60, QS_ALLINPUT, MWMO_INPUTAVAILABLE, nil)

            let now = ProcessInfo.processInfo.systemUptime
            let dt = Float(min(0.25, max(0, now - lastFrameTime)))
            lastFrameTime = now

            scene?.stepAndRender(dt: dt)
        }
    }

    private func shutdown() {
        scene?.shutdown()
        scene = nil
        controlPanel = nil
        renderChild = nil
        hwnd = nil
    }

    nonisolated static func dispatchControlMessage(_ uMsg: UInt32, _ wParam: UInt64, _ lParam: Int64) -> Bool {
        switch uMsg {
        case WM_COMMAND:
            let notification = highWord(wParam)
            let id = lowWord(wParam)
            guard id != 0, let control = hwndFromLPARAM(lParam) else { return false }

            if notification == BN_CLICKED {
                if id == ControlID.openModel {
                    Task { @MainActor in
                        Win32DemoApp.shared?.openModelFromDialog()
                    }
                    return true
                }
                if id == ControlID.resetView {
                    Task { @MainActor in
                        Win32DemoApp.shared?.scene?.resetCamera()
                    }
                    return true
                }
                if id == ControlID.resetPBR {
                    Task { @MainActor in
                        guard let app = Win32DemoApp.shared else { return }
                        app.controlPanel?.handleResetPBR(pbr: app.scene?.pbrController)
                    }
                    return true
                }
                let checked = win32SendMessageW(control, BM_GETCHECK, 0, 0) == BST_CHECKED
                Task { @MainActor in
                    guard let app = Win32DemoApp.shared else { return }
                    app.controlPanel?.handleCheckbox(id: id, checked: checked, pbr: app.scene?.pbrController)
                }
                return true
            }

            if notification == CBN_SELCHANGE {
                let selection = Int(win32SendMessageW(control, CB_GETCURSEL, 0, 0))
                guard selection >= 0 else { return false }
                Task { @MainActor in
                    guard let app = Win32DemoApp.shared else { return }
                    app.controlPanel?.handleCombo(id: id, selection: selection, pbr: app.scene?.pbrController)
                }
                return true
            }
            return false

        case WM_HSCROLL:
            guard let control = hwndFromLPARAM(lParam) else { return false }
            let id = Int(win32GetDlgCtrlID(control))
            guard id != 0 else { return false }
            let position = Int(win32SendMessageW(control, TBM_GETPOS, 0, 0))
            Task { @MainActor in
                guard let app = Win32DemoApp.shared else { return }
                app.controlPanel?.handleTrackbar(id: id, position: position, pbr: app.scene?.pbrController)
            }
            return true

        default:
            return false
        }
    }
}

@main
struct Win32DemoMain {
    static func main() {
        let app = Win32DemoApp()
        withExtendedLifetime(app) {
            app.run()
        }
    }
}
