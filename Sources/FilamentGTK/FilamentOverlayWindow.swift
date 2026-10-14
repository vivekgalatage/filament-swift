import Foundation
import Filament
import FilamentC

// MARK: - X11 Interop via SILGen & Runtime Dynamic Lookup

@_silgen_name("XOpenDisplay")
private func x11OpenDisplay(_ name: UnsafePointer<CChar>?) -> OpaquePointer?

@_silgen_name("XCloseDisplay")
private func x11CloseDisplay(_ display: OpaquePointer?) -> Int32

@_silgen_name("XDefaultScreen")
private func x11DefaultScreen(_ display: OpaquePointer?) -> Int32

@_silgen_name("XRootWindow")
private func x11RootWindow(_ display: OpaquePointer?, _ screen: Int32) -> UInt

@_silgen_name("XMatchVisualInfo")
private func x11MatchVisualInfo(
    _ display: OpaquePointer?,
    _ screen: Int32,
    _ depth: Int32,
    _ classVal: Int32,
    _ vinfo_return: UnsafeMutableRawPointer?
) -> Int32

@_silgen_name("XCreateColormap")
private func x11CreateColormap(
    _ display: OpaquePointer?,
    _ w: UInt,
    _ visual: UnsafeMutableRawPointer?,
    _ alloc: Int32
) -> UInt

@_silgen_name("XFreeColormap")
private func x11FreeColormap(_ display: OpaquePointer?, _ colormap: UInt) -> Int32

@_silgen_name("XCreateWindow")
private func x11CreateWindow(
    _ display: OpaquePointer?,
    _ parent: UInt,
    _ x: Int32,
    _ y: Int32,
    _ width: UInt32,
    _ height: UInt32,
    _ border_width: UInt32,
    _ depth: Int32,
    _ classVal: UInt32,
    _ visual: UnsafeMutableRawPointer?,
    _ valuemask: UInt,
    _ attributes: UnsafeMutableRawPointer?
) -> UInt

@_silgen_name("XDestroyWindow")
private func x11DestroyWindow(_ display: OpaquePointer?, _ w: UInt) -> Int32

@_silgen_name("XMapWindow")
private func x11MapWindow(_ display: OpaquePointer?, _ w: UInt) -> Int32

@_silgen_name("XUnmapWindow")
private func x11UnmapWindow(_ display: OpaquePointer?, _ w: UInt) -> Int32

@_silgen_name("XMoveWindow")
private func x11MoveWindow(_ display: OpaquePointer?, _ w: UInt, _ x: Int32, _ y: Int32) -> Int32

@_silgen_name("XCreateGC")
private func x11CreateGC(
    _ display: OpaquePointer?,
    _ d: UInt,
    _ valuemask: UInt,
    _ values: UnsafeMutableRawPointer?
) -> OpaquePointer?

@_silgen_name("XFreeGC")
private func x11FreeGC(_ display: OpaquePointer?, _ gc: OpaquePointer?) -> Int32

@_silgen_name("XCreateImage")
private func x11CreateImage(
    _ display: OpaquePointer?,
    _ visual: UnsafeMutableRawPointer?,
    _ depth: UInt32,
    _ format: Int32,
    _ offset: Int32,
    _ data: UnsafeMutablePointer<CChar>?,
    _ width: UInt32,
    _ height: UInt32,
    _ bitmap_pad: Int32,
    _ bytes_per_line: Int32
) -> UnsafeMutableRawPointer?

@_silgen_name("XPutImage")
private func x11PutImage(
    _ display: OpaquePointer?,
    _ d: UInt,
    _ gc: OpaquePointer?,
    _ image: UnsafeMutableRawPointer?,
    _ src_x: Int32,
    _ src_y: Int32,
    _ dest_x: Int32,
    _ dest_y: Int32,
    _ width: UInt32,
    _ height: UInt32
) -> Int32

@_silgen_name("XDestroyImage")
private func x11DestroyImage(_ ximage: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("XInternAtom")
private func x11InternAtom(
    _ display: OpaquePointer?,
    _ atom_name: UnsafePointer<CChar>?,
    _ only_if_exists: Int32
) -> UInt

@_silgen_name("XChangeProperty")
private func x11ChangeProperty(
    _ display: OpaquePointer?,
    _ w: UInt,
    _ property: UInt,
    _ type: UInt,
    _ format: Int32,
    _ mode: Int32,
    _ data: UnsafePointer<UInt8>?,
    _ nelements: Int32
) -> Int32

@_silgen_name("XFlush")
private func x11Flush(_ display: OpaquePointer?) -> Int32

@_silgen_name("XPending")
private func x11Pending(_ display: OpaquePointer?) -> Int32

@_silgen_name("XNextEvent")
private func x11NextEvent(_ display: OpaquePointer?, _ event: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("XCreateFontCursor")
private func x11CreateFontCursor(_ display: OpaquePointer?, _ shape: UInt32) -> UInt

@_silgen_name("XFreeCursor")
private func x11FreeCursor(_ display: OpaquePointer?, _ cursor: UInt) -> Int32

@_silgen_name("dlsym")
private func dlsym(_ handle: UnsafeMutableRawPointer?, _ symbol: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?

// MARK: - X11 Constants & Data Structures

private let kTrueColor: Int32 = 4
private let kAllocNone: Int32 = 0
private let kInputOutput: UInt32 = 1
private let kZPixmap: Int32 = 2
private let kPropModeReplace: Int32 = 0

private let kCWBackPixel: UInt = 1 << 1
private let kCWBorderPixel: UInt = 1 << 3
private let kCWEventMask: UInt = 1 << 11
private let kCWColormap: UInt = 1 << 13
private let kCWCursor: UInt = 1 << 14

private let kExposureMask: Int = 1 << 15
private let kStructureNotifyMask: Int = 1 << 17
private let kButtonPressMask: Int = 1 << 2
private let kButtonReleaseMask: Int = 1 << 3
private let kPointerMotionMask: Int = 1 << 6
private let kButtonMotionMask: Int = 1 << 13

private let kXC_left_ptr: UInt32 = 68

private let kShapeInput: Int32 = 2
private let kShapeSet: Int32 = 0

/// 64-byte layout matching Xlib's `XVisualInfo` struct on 64-bit Linux.
private struct XVisualInfo {
    var visual: UnsafeMutableRawPointer?
    var visualid: UInt = 0
    var screen: Int32 = 0
    var depth: Int32 = 0
    var classVal: Int32 = 0
    var pad: Int32 = 0
    var red_mask: UInt = 0
    var green_mask: UInt = 0
    var blue_mask: UInt = 0
    var colormap_size: Int32 = 0
    var bits_per_rgb: Int32 = 0
}

/// 112-byte layout matching Xlib's `XSetWindowAttributes` on 64-bit Linux.
private struct XSetWindowAttributes {
    var background_pixmap: UInt = 0
    var background_pixel: UInt = 0
    var border_pixmap: UInt = 0
    var border_pixel: UInt = 0
    var bit_gravity: Int32 = 0
    var win_gravity: Int32 = 0
    var backing_store: Int32 = 0
    var pad1: Int32 = 0
    var backing_planes: UInt = 0
    var backing_pixel: UInt = 0
    var save_under: Int32 = 0
    var pad2: Int32 = 0
    var event_mask: Int = 0
    var do_not_propagate_mask: Int = 0
    var override_redirect: Int32 = 0
    var pad3: Int32 = 0
    var colormap: UInt = 0
    var cursor: UInt = 0
}

private struct MotifWmHints {
    var flags: UInt = 2        // MWM_HINTS_DECORATIONS
    var functions: UInt = 0
    var decorations: UInt = 0  // 0 = borderless
    var input_mode: Int = 0
    var status: UInt = 0
}

/// 192-byte layout matching Xlib's `XEvent` union on 64-bit Linux.
private struct RawXEvent {
    var pad: (UInt64, UInt64, UInt64, UInt64,
              UInt64, UInt64, UInt64, UInt64,
              UInt64, UInt64, UInt64, UInt64,
              UInt64, UInt64, UInt64, UInt64,
              UInt64, UInt64, UInt64, UInt64,
              UInt64, UInt64, UInt64, UInt64) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    var type: Int32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 0, as: Int32.self) }
    }
    var window: UInt {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 32, as: UInt.self) }
    }
    var x: Int32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 64, as: Int32.self) }
    }
    var y: Int32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 68, as: Int32.self) }
    }
    var x_root: Int32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 72, as: Int32.self) }
    }
    var y_root: Int32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 76, as: Int32.self) }
    }
    var state: UInt32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 80, as: UInt32.self) }
    }
    var button: UInt32 {
        withUnsafeBytes(of: self) { $0.load(fromByteOffset: 84, as: UInt32.self) }
    }
}

/// Transparent floating companion/assistant overlay for Linux (X11 / Xwayland).
///
/// Hosts a 3D GLB model (with blend shapes and skeletal animations) inside a borderless,
/// top-level 32-bit ARGB X11 window. Frames are rendered transparently by Google Filament
/// offscreen and blitted directly to the composited X11 visual with per-pixel alpha.
///
/// Features:
/// - Floats seamlessly above **any** application (browsers, editors, terminals, or desktop).
/// - Has true alpha transparency composited by Mutter, KWin, or Picom (soft edges & hair/fur).
/// - Can be dragged or repositioned programmatically across the screen.
/// - Supports optional click-through (`isClickThrough = true`) via the XShape extension.
@MainActor
public final class FilamentOverlayWindow {
    public enum InteractionMode: Sendable {
        /// Left-drag moves the floating window across the desktop; Right-drag (or Shift+Left-drag) orbits the 3D model.
        case windowMove
        /// Left-drag orbits the 3D model; Right-drag (or Shift+Left-drag) moves the floating window.
        case modelOrbit
    }

    private final class Storage: @unchecked Sendable {
        var display: OpaquePointer?
        var xid: UInt = 0
        var colormap: UInt = 0
        var gc: OpaquePointer?
        var ximage: UnsafeMutableRawPointer?
        var cursor: UInt = 0
        var ownsDisplay = false
        var headlessSwapChain: OpaquePointer?

        func detach() -> (display: OpaquePointer?, xid: UInt, colormap: UInt, gc: OpaquePointer?, ximage: UnsafeMutableRawPointer?, cursor: UInt, ownsDisplay: Bool, sc: OpaquePointer?) {
            let res = (display, xid, colormap, gc, ximage, cursor, ownsDisplay, headlessSwapChain)
            display = nil
            xid = 0
            colormap = 0
            gc = nil
            ximage = nil
            cursor = 0
            ownsDisplay = false
            headlessSwapChain = nil
            return res
        }
    }

    private let storage = Storage()

    public let engine: FilamentEngine
    public let pbr: FilamentPBRController
    public let model: FilamentModel
    public let outlineModel: FilamentModel
    public let camera: FilamentOrbitCamera

    public private(set) var currentModelURL: URL?
    public private(set) var toonMaterial: FilamentToonMaterial?
    public private(set) var outlineMaterial: FilamentToonOutlineMaterial?
    public private(set) var depthMaskMaterial: FilamentDepthMaskMaterial?
    public private(set) var currentShadingMode: Int = 0
    public private(set) var currentOutlineColor: (r: Float, g: Float, b: Float) = (0.10, 0.08, 0.06)

    public var xid: UInt { storage.xid }
    public let width: UInt32
    public let height: UInt32

    public private(set) var currentPositionX: Int32
    public private(set) var currentPositionY: Int32

    /// Determines whether primary Left-drag moves the floating window or orbits the 3D model.
    /// Defaults to `.windowMove`.
    public var primaryInteractionMode: InteractionMode = .windowMove

    private var isDraggingWindow = false
    private var dragStartMouseRootX: Int32 = 0
    private var dragStartMouseRootY: Int32 = 0
    private var dragStartWinX: Int32 = 0
    private var dragStartWinY: Int32 = 0

    private var isOrbitingCamera = false
    private var isPanningCamera = false
    private var lastMouseX: Int32 = 0
    private var lastMouseY: Int32 = 0
    private var lastClickTime: Double = 0.0

    private var animationTime: Float = 0.0
    private var lastFrameTime: Double = ProcessInfo.processInfo.systemUptime

    private var rgbaBuffer: [UInt8]
    private var bgraBuffer: [UInt8]

    public var isClickThrough: Bool = false {
        didSet {
            guard oldValue != isClickThrough else { return }
            updateClickThrough()
        }
    }

    public init(
        width: UInt32 = 420,
        height: UInt32 = 560,
        initialX: Int32 = 100,
        initialY: Int32 = 100,
        engine: FilamentEngine? = nil
    ) {
        self.width = max(64, width)
        self.height = max(64, height)
        self.currentPositionX = initialX
        self.currentPositionY = initialY

        let eng = engine ?? FilamentEngine(backend: .vulkan)
        self.engine = eng
        self.pbr = FilamentPBRController(engine: eng)
        self.model = FilamentModel(engine: eng)
        self.outlineModel = FilamentModel(engine: eng)
        self.camera = FilamentOrbitCamera(engine: eng)

        let pixelCount = Int(self.width * self.height * 4)
        self.rgbaBuffer = [UInt8](repeating: 0, count: pixelCount)
        self.bgraBuffer = [UInt8](repeating: 0, count: pixelCount)

        eng.setTransparent(true)
        setupHeadlessSwapChain()
        setupX11OverlayWindow()
    }

    deinit {
        let eng = engine
        let storage = storage

        FilamentMainActor.perform {
            let (disp, win, cmap, gc, img, cur, owns, sc) = storage.detach()
            if let sc {
                eng.destroySwapChain(sc)
            }
            if let disp {
                if let img {
                    // Reset data pointer to avoid XDestroyImage freeing Swift managed memory.
                    img.advanced(by: 16).assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee = nil
                    _ = x11DestroyImage(img)
                }
                if cur != 0 { _ = x11FreeCursor(disp, cur) }
                if let gc { _ = x11FreeGC(disp, gc) }
                if win != 0 { _ = x11DestroyWindow(disp, win) }
                if cmap != 0 { _ = x11FreeColormap(disp, cmap) }
                _ = x11Flush(disp)
                if owns { _ = x11CloseDisplay(disp) }
            }
        }
    }

    // MARK: - Setup

    private func setupHeadlessSwapChain() {
        storage.headlessSwapChain = engine.createHeadlessSwapChain(width: width, height: height, transparent: true)
        if let v = engine.view {
            FilamentBridge.setViewport(v, 0, 0, width, height)
        }
        engine.setCameraProjection(fovInDegrees: 45.0, aspect: Double(width) / Double(height))
    }

    private func setupX11OverlayWindow() {
        var display = x11OpenDisplay(nil)
        var owns = true
        if display == nil {
            display = resolveGdkXDisplay()
            owns = false
        }

        guard let display else {
            print("[FilamentOverlayWindow] Could not connect to an X11 display. Transparency overlay unavailable.")
            return
        }

        storage.display = display
        storage.ownsDisplay = owns

        let screen = x11DefaultScreen(display)
        let root = x11RootWindow(display, screen)

        var vinfo = XVisualInfo()
        let matchStatus = withUnsafeMutablePointer(to: &vinfo) { ptr in
            x11MatchVisualInfo(display, screen, 32, kTrueColor, UnsafeMutableRawPointer(ptr))
        }

        let visualPtr: UnsafeMutableRawPointer?
        let depth: Int32

        if matchStatus != 0, let vis = vinfo.visual {
            visualPtr = vis
            depth = 32
        } else {
            print("[FilamentOverlayWindow] 32-bit ARGB visual not found; falling back to root visual.")
            visualPtr = nil
            depth = 24
        }

        let colormap = visualPtr != nil ? x11CreateColormap(display, root, visualPtr, kAllocNone) : 0
        storage.colormap = colormap

        let cursor = x11CreateFontCursor(display, kXC_left_ptr)
        storage.cursor = cursor

        var attrs = XSetWindowAttributes()
        attrs.background_pixel = 0
        attrs.border_pixel = 0
        attrs.colormap = colormap
        attrs.cursor = cursor
        attrs.event_mask = kExposureMask | kStructureNotifyMask | kButtonPressMask | kButtonReleaseMask | kPointerMotionMask | kButtonMotionMask

        let valuemask = kCWBackPixel | kCWBorderPixel | kCWEventMask | (colormap != 0 ? kCWColormap : 0) | (cursor != 0 ? kCWCursor : 0)

        let win = withUnsafeMutablePointer(to: &attrs) { ptr in
            x11CreateWindow(
                display,
                root,
                currentPositionX,
                currentPositionY,
                width,
                height,
                0,
                depth,
                kInputOutput,
                visualPtr,
                valuemask,
                UnsafeMutableRawPointer(ptr)
            )
        }

        guard win != 0 else {
            print("[FilamentOverlayWindow] Failed to create overlay X11 window.")
            return
        }

        storage.xid = win
        storage.gc = x11CreateGC(display, win, 0, nil)

        // Make window borderless via _MOTIF_WM_HINTS
        var motifHints = MotifWmHints()
        let motifAtom = x11InternAtom(display, "_MOTIF_WM_HINTS", 0)
        withUnsafePointer(to: &motifHints) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<MotifWmHints>.size) { bytePtr in
                _ = x11ChangeProperty(display, win, motifAtom, motifAtom, 32, kPropModeReplace, bytePtr, 5)
            }
        }

        // Float on top of all windows via _NET_WM_STATE_ABOVE
        let wmState = x11InternAtom(display, "_NET_WM_STATE", 0)
        let stateAbove = x11InternAtom(display, "_NET_WM_STATE_ABOVE", 0)
        let stateSkipTaskbar = x11InternAtom(display, "_NET_WM_STATE_SKIP_TASKBAR", 0)
        let stateSkipPager = x11InternAtom(display, "_NET_WM_STATE_SKIP_PAGER", 0)
        var atoms: [UInt] = [stateAbove, stateSkipTaskbar, stateSkipPager]
        atoms.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            base.withMemoryRebound(to: UInt8.self, capacity: buf.count * MemoryLayout<UInt>.size) { bytePtr in
                let atomType = x11InternAtom(display, "ATOM", 0)
                _ = x11ChangeProperty(display, win, wmState, atomType, 32, kPropModeReplace, bytePtr, Int32(atoms.count))
            }
        }

        // Set utility window type
        let wmType = x11InternAtom(display, "_NET_WM_WINDOW_TYPE", 0)
        let typeUtility = x11InternAtom(display, "_NET_WM_WINDOW_TYPE_UTILITY", 0)
        var typeAtom = typeUtility
        withUnsafePointer(to: &typeAtom) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<UInt>.size) { bytePtr in
                let atomType = x11InternAtom(display, "ATOM", 0)
                _ = x11ChangeProperty(display, win, wmType, atomType, 32, kPropModeReplace, bytePtr, 1)
            }
        }

        // Create persistent XImage wrapper around the BGRA buffer
        bgraBuffer.withUnsafeMutableBufferPointer { buf in
            guard let base = buf.baseAddress else { return }
            let charPtr = UnsafeMutableRawPointer(base).assumingMemoryBound(to: CChar.self)
            storage.ximage = x11CreateImage(
                display,
                visualPtr,
                UInt32(depth),
                kZPixmap,
                0,
                charPtr,
                width,
                height,
                32,
                Int32(width * 4)
            )
        }

        _ = x11Flush(display)
    }

    private func resolveGdkXDisplay() -> OpaquePointer? {
        typealias GdkGetDefault = @convention(c) () -> OpaquePointer?
        typealias GdkGetXDisplay = @convention(c) (OpaquePointer?) -> UnsafeMutableRawPointer?

        guard
            let getDefault = lookupDynSymbol("gdk_display_get_default", as: GdkGetDefault.self),
            let display = getDefault()
        else { return nil }

        let getXDisplay = lookupDynSymbol("gdk_x11_display_get_xdisplay", as: GdkGetXDisplay.self)
            ?? lookupDynSymbol("gdk_x11_get_xdisplay", as: GdkGetXDisplay.self)

        guard let getXDisplay, let raw = getXDisplay(display) else { return nil }
        return OpaquePointer(raw)
    }

    // MARK: - Window Visibility & Positioning

    public func show(atX x: Int32? = nil, y: Int32? = nil) {
        if let x { currentPositionX = x }
        if let y { currentPositionY = y }
        guard let display = storage.display, storage.xid != 0 else { return }
        _ = x11MoveWindow(display, storage.xid, currentPositionX, currentPositionY)
        _ = x11MapWindow(display, storage.xid)
        _ = x11Flush(display)
    }

    public func hide() {
        guard let display = storage.display, storage.xid != 0 else { return }
        _ = x11UnmapWindow(display, storage.xid)
        _ = x11Flush(display)
    }

    public func setPosition(x: Int32, y: Int32) {
        currentPositionX = x
        currentPositionY = y
        guard let display = storage.display, storage.xid != 0 else { return }
        _ = x11MoveWindow(display, storage.xid, x, y)
        _ = x11Flush(display)
    }

    public func dragTo(screenX: Int32, screenY: Int32) {
        setPosition(x: screenX, y: screenY)
    }

    private func updateClickThrough() {
        guard let display = storage.display, storage.xid != 0 else { return }

        typealias ShapeRectFn = @convention(c) (OpaquePointer?, UInt, Int32, Int32, Int32, UnsafeRawPointer?, Int32, Int32, Int32) -> Void
        typealias ShapeMaskFn = @convention(c) (OpaquePointer?, UInt, Int32, Int32, Int32, UInt, Int32) -> Void

        let shapeRect = lookupDynSymbol("XShapeCombineRectangles", as: ShapeRectFn.self)
        let shapeMask = lookupDynSymbol("XShapeCombineMask", as: ShapeMaskFn.self)

        if isClickThrough {
            // Empty rectangle list makes entire window click-through
            shapeRect?(display, storage.xid, kShapeInput, 0, 0, nil, 0, kShapeSet, 0)
        } else {
            // None mask restores default bounding box interactivity
            shapeMask?(display, storage.xid, kShapeInput, 0, 0, 0, kShapeSet)
        }
        _ = x11Flush(display)
    }

    // MARK: - Event Polling & User Interaction

    /// Polls pending X11 events for the overlay window, handling dragging, orbiting, panning, and zooming.
    public func pollEvents() {
        guard let display = storage.display, storage.xid != 0 else { return }

        while x11Pending(display) > 0 {
            var ev = RawXEvent()
            _ = withUnsafeMutablePointer(to: &ev) { ptr in
                x11NextEvent(display, UnsafeMutableRawPointer(ptr))
            }

            switch ev.type {
            case 4: // ButtonPress
                let btn = ev.button
                let isShift = (ev.state & 1) != 0

                if btn == 1 {
                    if isShift || primaryInteractionMode == .modelOrbit {
                        isOrbitingCamera = true
                        lastMouseX = ev.x
                        lastMouseY = ev.y
                    } else {
                        let now = ProcessInfo.processInfo.systemUptime
                        if now - lastClickTime < 0.35 {
                            camera.reset()
                        }
                        lastClickTime = now

                        isDraggingWindow = true
                        dragStartMouseRootX = ev.x_root
                        dragStartMouseRootY = ev.y_root
                        dragStartWinX = currentPositionX
                        dragStartWinY = currentPositionY
                    }
                } else if btn == 2 {
                    isPanningCamera = true
                    lastMouseX = ev.x
                    lastMouseY = ev.y
                } else if btn == 3 {
                    if primaryInteractionMode == .modelOrbit {
                        isDraggingWindow = true
                        dragStartMouseRootX = ev.x_root
                        dragStartMouseRootY = ev.y_root
                        dragStartWinX = currentPositionX
                        dragStartWinY = currentPositionY
                    } else {
                        isOrbitingCamera = true
                        lastMouseX = ev.x
                        lastMouseY = ev.y
                    }
                } else if btn == 4 {
                    camera.zoom(delta: 1.5)
                } else if btn == 5 {
                    camera.zoom(delta: -1.5)
                }

            case 5: // ButtonRelease
                let btn = ev.button
                if btn == 1 {
                    if isDraggingWindow { isDraggingWindow = false }
                    if isOrbitingCamera { isOrbitingCamera = false }
                } else if btn == 2 {
                    isPanningCamera = false
                } else if btn == 3 {
                    isOrbitingCamera = false
                    isDraggingWindow = false
                }

            case 6: // MotionNotify
                if isDraggingWindow {
                    let dx = ev.x_root - dragStartMouseRootX
                    let dy = ev.y_root - dragStartMouseRootY
                    setPosition(x: dragStartWinX + dx, y: dragStartWinY + dy)
                } else if isOrbitingCamera {
                    let dx = Double(ev.x - lastMouseX)
                    let dy = Double(ev.y - lastMouseY)
                    lastMouseX = ev.x
                    lastMouseY = ev.y
                    camera.orbit(deltaX: dx, deltaY: dy)
                } else if isPanningCamera {
                    let dx = Double(ev.x - lastMouseX)
                    let dy = Double(ev.y - lastMouseY)
                    lastMouseX = ev.x
                    lastMouseY = ev.y
                    camera.pan(deltaX: dx, deltaY: dy)
                }

            default:
                break
            }
        }
    }

    // MARK: - Frame Rendering & Alpha Blitting

    @discardableResult
    public func renderFrame() -> Bool {
        pollEvents()

        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(min(0.25, max(0, now - lastFrameTime)))
        lastFrameTime = now

        if model.hasAnimations {
            animationTime += dt
            let dur = model.activeAnimationDuration
            if dur > 0.001 {
                animationTime = animationTime.truncatingRemainder(dividingBy: dur)
            }
            model.applyAnimation(time: animationTime)
            if outlineModel.isLoaded && outlineModel.isVisible {
                outlineModel.applyAnimation(time: animationTime)
            }
        }

        if let out = outlineMaterial, out.flowAnimationSpeed != 0 {
            let nextPhase = (out.gradientPhase + dt * out.flowAnimationSpeed).truncatingRemainder(dividingBy: 1.0)
            out.gradientPhase = nextPhase >= 0 ? nextPhase : (nextPhase + 1.0)
        }

        camera.update(dt: dt)

        guard
            let renderer = engine.renderer,
            let view = engine.view,
            let sc = storage.headlessSwapChain,
            let display = storage.display,
            let gc = storage.gc,
            let ximage = storage.ximage,
            storage.xid != 0
        else { return false }

        guard FilamentBridge.beginFrame(renderer, sc) else { return false }
        FilamentBridge.renderView(renderer, view)

        let bufferSize = rgbaBuffer.count
        let readSuccess = rgbaBuffer.withUnsafeMutableBytes { ptr -> Bool in
            guard let base = ptr.baseAddress else { return false }
            return engine.readPixels(width: width, height: height, into: base, bufferSize: bufferSize)
        }
        FilamentBridge.endFrame(renderer)

        guard readSuccess else { return false }

        // Convert RGBA -> Pre-multiplied BGRA for 32-bit TrueColor X11 visual
        let pixelCount = Int(width * height)
        rgbaBuffer.withUnsafeBufferPointer { srcBuf in
            guard let src = srcBuf.baseAddress else { return }
            bgraBuffer.withUnsafeMutableBufferPointer { dstBuf in
                guard let dst = dstBuf.baseAddress else { return }
                var idx = 0
                for _ in 0..<pixelCount {
                    let r = src[idx + 0]
                    let g = src[idx + 1]
                    let b = src[idx + 2]
                    let a = src[idx + 3]

                    if a == 0 {
                        dst[idx + 0] = 0
                        dst[idx + 1] = 0
                        dst[idx + 2] = 0
                        dst[idx + 3] = 0
                    } else if a == 255 {
                        dst[idx + 0] = b
                        dst[idx + 1] = g
                        dst[idx + 2] = r
                        dst[idx + 3] = 255
                    } else {
                        let scale = Float(a) / 255.0
                        dst[idx + 0] = UInt8(Float(b) * scale)
                        dst[idx + 1] = UInt8(Float(g) * scale)
                        dst[idx + 2] = UInt8(Float(r) * scale)
                        dst[idx + 3] = a
                    }
                    idx += 4
                }
            }
        }

        _ = x11PutImage(display, storage.xid, gc, ximage, 0, 0, 0, 0, width, height)
        _ = x11Flush(display)
        return true
    }

    // MARK: - Model, Shading & Halftone Controls

    public func loadModel(from url: URL) throws {
        self.currentModelURL = url
        try model.loadGlb(at: url)
        model.setRotation(radiansY: 0)
        model.setPriority(4)
        if model.hasAnimations {
            model.selectAnimation(at: 0)
        }

        try? outlineModel.loadGlb(at: url)
        outlineModel.setRotation(radiansY: 0)
        outlineModel.setPriority(6)
        if outlineModel.hasAnimations {
            outlineModel.selectAnimation(at: 0)
        }

        ensureMaterials()
        applyShadingMode()
    }

    public func setBlendShape(name: String, weight: Float) {
        model.setBlendShape(name: name, weight: weight)
        if outlineModel.isLoaded {
            outlineModel.setBlendShape(name: name, weight: weight)
        }
    }

    public func setBlendShape(index: Int, weight: Float) {
        model.setBlendShape(index: index, weight: weight)
        if outlineModel.isLoaded {
            outlineModel.setBlendShape(index: index, weight: weight)
        }
    }

    public func setShadingMode(index: Int) {
        currentShadingMode = index
        applyShadingMode()
    }

    public func setOutlineColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        currentOutlineColor = (r, g, b)
        ensureMaterials()
        outlineMaterial?.outlineColor = (r, g, b, a)
    }

    public func setOutlineThickness(_ thickness: Float) {
        ensureMaterials()
        outlineMaterial?.outlineThickness = thickness
    }

    public func setOutlineGradientMode(_ mode: FilamentToonOutlineMaterial.GradientMode) {
        ensureMaterials()
        outlineMaterial?.gradientMode = mode
    }

    public func setOutlineStops(_ stops: [FilamentToonOutlineMaterial.GradientStop]) {
        ensureMaterials()
        outlineMaterial?.stops = stops
    }

    public func setOutlineGradientScale(_ scale: Float) {
        ensureMaterials()
        outlineMaterial?.gradientScale = scale
    }

    public func setOutlineGradientPhase(_ phase: Float) {
        ensureMaterials()
        outlineMaterial?.gradientPhase = phase
    }

    public func setOutlineFlowSpeed(_ speed: Float) {
        ensureMaterials()
        outlineMaterial?.flowAnimationSpeed = speed
    }

    public func setOutlineNoiseScale(_ noise: Float) {
        ensureMaterials()
        outlineMaterial?.noiseScale = noise
    }

    public func setHalftoneMode(_ mode: FilamentToonMaterial.HalftoneMode) {
        ensureMaterials()
        toonMaterial?.halftoneMode = mode
    }

    public func setHalftoneTarget(_ target: FilamentToonMaterial.HalftoneTarget) {
        ensureMaterials()
        toonMaterial?.halftoneTarget = target
    }

    public func setHalftoneScale(_ scale: Float) {
        ensureMaterials()
        toonMaterial?.halftoneScale = scale
    }

    public func setHalftoneAngle(_ angle: Float) {
        ensureMaterials()
        toonMaterial?.halftoneAngle = angle
    }

    public func setHalftoneDotSize(_ size: Float) {
        ensureMaterials()
        toonMaterial?.halftoneDotSize = size
    }

    public func setHalftoneHardness(_ hardness: Float) {
        ensureMaterials()
        toonMaterial?.halftoneHardness = hardness
    }

    public func setHalftoneBlend(_ blend: Float) {
        ensureMaterials()
        toonMaterial?.halftoneBlend = blend
    }

    public func setHalftoneDotColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureMaterials()
        toonMaterial?.halftoneDotColor = (r, g, b, a)
    }

    public func setHalftonePaperColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureMaterials()
        toonMaterial?.halftonePaperColor = (r, g, b, a)
    }

    public func applyHalftonePreset(_ preset: FilamentToonMaterial.HalftonePreset) {
        ensureMaterials()
        toonMaterial?.applyPreset(preset)
    }

    public func setOutlineJitter(_ jitter: Float) {
        ensureMaterials()
        outlineMaterial?.outlineJitter = jitter
    }

    public func setOutlineJitterFreq(_ freq: Float) {
        ensureMaterials()
        outlineMaterial?.outlineJitterFreq = freq
    }

    public func setHatchJitter(_ jitter: Float) {
        ensureMaterials()
        toonMaterial?.hatchJitter = jitter
    }

    public func setHatchLayers(_ layers: Int32) {
        ensureMaterials()
        toonMaterial?.hatchLayers = layers
    }

    public func setHatchThresholds(t1: Float, t2: Float, t3: Float) {
        ensureMaterials()
        toonMaterial?.hatchThreshold1 = t1
        toonMaterial?.hatchThreshold2 = t2
        toonMaterial?.hatchThreshold3 = t3
    }

    private func applyShadingMode() {
        guard let url = currentModelURL else { return }
        ensureMaterials()

        switch currentShadingMode {
        case 0: // Standard PBR
            outlineModel.setVisible(false)
            try? model.loadGlb(at: url)
            model.setRotation(radiansY: 0.0)
            model.setPriority(4)
            if model.hasAnimations {
                model.selectAnimation(at: 0)
            }

        case 1: // Toon Cel
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                model.applyToonMaterial(toon)
            }

        case 2: // Toon + Outline
            model.setPriority(4)
            if let toon = toonMaterial {
                model.applyToonMaterial(toon)
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case 3: // PBR + Outline
            try? model.loadGlb(at: url)
            model.setRotation(radiansY: 0.0)
            model.setPriority(4)
            if model.hasAnimations {
                model.selectAnimation(at: 0)
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case 4: // Outline Only (Transparent Body)
            model.setPriority(4)
            if let mask = depthMaskMaterial {
                model.applyDepthMaskMaterial(mask)
            }
            model.setVisible(true)
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case 5: // Comic Halftone (Pop-Art / Manga)
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode == .disabled {
                    toon.halftoneMode = .screenDots
                }
                model.applyToonMaterial(toon)
            }

        case 6: // Halftone + Inked Outline
            model.setPriority(4)
            if let toon = toonMaterial {
                if toon.halftoneMode == .disabled {
                    toon.halftoneMode = .screenDots
                }
                model.applyToonMaterial(toon)
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case 7: // Handdrawn Technical Sketch
            model.setPriority(4)
            if let toon = toonMaterial {
                toon.halftoneMode = .handdrawnSketch
                toon.halftoneTarget = .fullSurface
                model.applyToonMaterial(toon)
            }
            if let outline = outlineMaterial {
                if outline.outlineJitter < 0.001 {
                    outline.outlineJitter = 0.25
                }
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        default: break
        }
    }

    private func ensureMaterials() {
        guard toonMaterial == nil || outlineMaterial == nil || depthMaskMaterial == nil else { return }
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = sourceDir.deletingLastPathComponent().deletingLastPathComponent()
        let candidateDirs = [
            repoRoot.appendingPathComponent("Resources/Materials", isDirectory: true),
            repoRoot.appendingPathComponent("Examples/Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "Examples/Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "../Resources/Materials", isDirectory: true),
        ]

        for dir in candidateDirs {
            let celURL = dir.appendingPathComponent("ToonCel.filamat")
            let outURL = dir.appendingPathComponent("ToonOutline.filamat")
            let maskURL = dir.appendingPathComponent("DepthMask.filamat")
            if FileManager.default.fileExists(atPath: celURL.path) && toonMaterial == nil {
                toonMaterial = try? engine.createToonMaterial(from: celURL)
                toonMaterial?.syncWithDirectionalLight(direction: (0.2, -1.0, -0.6), color: (1.0, 0.98, 0.95))
            }
            if FileManager.default.fileExists(atPath: outURL.path) && outlineMaterial == nil {
                outlineMaterial = try? engine.createOutlineMaterial(from: outURL)
            }
            if FileManager.default.fileExists(atPath: maskURL.path) && depthMaskMaterial == nil {
                depthMaskMaterial = try? engine.createDepthMaskMaterial(from: maskURL)
            }
        }
    }
}

// MARK: - Dynamic Symbol Resolution

private func lookupDynSymbol<T>(_ name: String, as type: T.Type) -> T? {
    if let symbol = name.withCString({ dlsym(nil, $0) }) {
        return unsafeBitCast(symbol, to: T.self)
    }
    #if os(Linux)
    for lib in ["libX11.so.6", "libX11.so", "libXext.so.6", "libXext.so", "libgtk-4.so.1", "libgtk-4.so"] {
        if let handle = dlopen(lib, RTLD_LAZY | RTLD_GLOBAL) {
            if let symbol = name.withCString({ dlsym(handle, $0) }) {
                return unsafeBitCast(symbol, to: T.self)
            }
        }
    }
    #endif
    return nil
}
