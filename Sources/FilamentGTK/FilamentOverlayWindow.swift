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

private let kExposureMask: Int = 1 << 15
private let kStructureNotifyMask: Int = 1 << 17
private let kButtonPressMask: Int = 1 << 2
private let kButtonReleaseMask: Int = 1 << 3
private let kPointerMotionMask: Int = 1 << 6

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
    private final class Storage: @unchecked Sendable {
        var display: OpaquePointer?
        var xid: UInt = 0
        var colormap: UInt = 0
        var gc: OpaquePointer?
        var ximage: UnsafeMutableRawPointer?
        var ownsDisplay = false
        var headlessSwapChain: OpaquePointer?

        func detach() -> (display: OpaquePointer?, xid: UInt, colormap: UInt, gc: OpaquePointer?, ximage: UnsafeMutableRawPointer?, ownsDisplay: Bool, sc: OpaquePointer?) {
            let res = (display, xid, colormap, gc, ximage, ownsDisplay, headlessSwapChain)
            display = nil
            xid = 0
            colormap = 0
            gc = nil
            ximage = nil
            ownsDisplay = false
            headlessSwapChain = nil
            return res
        }
    }

    private let storage = Storage()

    public let engine: FilamentEngine
    public let pbr: FilamentPBRController
    public let model: FilamentModel
    public let camera: FilamentOrbitCamera

    public var xid: UInt { storage.xid }
    public let width: UInt32
    public let height: UInt32

    public private(set) var currentPositionX: Int32
    public private(set) var currentPositionY: Int32

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
            let (disp, win, cmap, gc, img, owns, sc) = storage.detach()
            if let sc {
                eng.destroySwapChain(sc)
            }
            if let disp {
                if let img {
                    // Reset data pointer to avoid XDestroyImage freeing Swift managed memory.
                    img.advanced(by: 16).assumingMemoryBound(to: UnsafeMutableRawPointer?.self).pointee = nil
                    _ = x11DestroyImage(img)
                }
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
        var display = resolveGdkXDisplay()
        var owns = false
        if display == nil {
            display = x11OpenDisplay(nil)
            owns = true
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

        var attrs = XSetWindowAttributes()
        attrs.background_pixel = 0
        attrs.border_pixel = 0
        attrs.colormap = colormap
        attrs.event_mask = kExposureMask | kStructureNotifyMask | kButtonPressMask | kButtonReleaseMask | kPointerMotionMask

        let valuemask = kCWBackPixel | kCWBorderPixel | kCWEventMask | (colormap != 0 ? kCWColormap : 0)

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

    // MARK: - Frame Rendering & Alpha Blitting

    @discardableResult
    public func renderFrame() -> Bool {
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

    // MARK: - Model & Blend Shapes

    public func loadModel(from url: URL) throws {
        try model.loadGlb(at: url)
        model.setRotation(radiansY: 0)
        if model.hasAnimations {
            model.selectAnimation(at: 0)
        }
    }

    public func setBlendShape(name: String, weight: Float) {
        model.setBlendShape(name: name, weight: weight)
    }

    public func setBlendShape(index: Int, weight: Float) {
        model.setBlendShape(index: index, weight: weight)
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
