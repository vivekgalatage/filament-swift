import Foundation
import WinSDK

// =============================================================================
// Win32Constants & Low-level Helpers
//
// `WinSDK` does not consistently surface common-control / dialog message
// constants. The raw Win32 entry points used by the demo are declared here as
// `@_silgen_name` wrappers with exact C signatures, and the message / style
// constants are spelled out with their documented Win32 values.
// =============================================================================

// --- Window messages -------------------------------------------------------
let WM_DESTROY: UInt32 = 0x0002
let WM_SIZE: UInt32 = 0x0005
let WM_SETTEXT: UInt32 = 0x000C
let WM_QUIT: UInt32 = 0x0012
let WM_SETFONT: UInt32 = 0x0030
let WM_KEYDOWN: UInt32 = 0x0100
let WM_COMMAND: UInt32 = 0x0111
let WM_HSCROLL: UInt32 = 0x0114
let WM_CTLCOLORBTN: UInt32 = 0x0135
let WM_CTLCOLORSTATIC: UInt32 = 0x0138

// --- Mouse messages & modifier masks ---------------------------------------
let WM_MOUSEMOVE: UInt32 = 0x0200
let WM_LBUTTONDOWN: UInt32 = 0x0201
let WM_LBUTTONUP: UInt32 = 0x0202
let WM_LBUTTONDBLCLK: UInt32 = 0x0203
let WM_RBUTTONDOWN: UInt32 = 0x0204
let WM_RBUTTONUP: UInt32 = 0x0205
let WM_MBUTTONDOWN: UInt32 = 0x0207
let WM_MBUTTONUP: UInt32 = 0x0208
let WM_MOUSEWHEEL: UInt32 = 0x020A

let MK_LBUTTON: UInt64 = 0x0001
let MK_RBUTTON: UInt64 = 0x0002
let MK_SHIFT: UInt64 = 0x0004
let MK_MBUTTON: UInt64 = 0x0010
let CS_VREDRAW: UInt32 = 0x0001
let CS_HREDRAW: UInt32 = 0x0002
let CS_DBLCLKS: UInt32 = 0x0008
let CW_USEDEFAULT: Int32 = Int32(bitPattern: 0x8000_0000)
let PM_REMOVE: UInt32 = 0x0001
let QS_ALLINPUT: UInt32 = 0x04FF
let MWMO_INPUTAVAILABLE: UInt32 = 0x0004
let COINIT_APARTMENTTHREADED_VALUE: UInt32 = 0x0002

// --- Trackbar (msctls_trackbar32) messages ---------------------------------
let TBM_GETPOS: UInt32 = 0x0400
let TBM_SETPOS: UInt32 = 0x0405
let TBM_SETRANGE: UInt32 = 0x0406
let TBM_SETRANGEMIN: UInt32 = 0x0407
let TBM_SETRANGEMAX: UInt32 = 0x0408

// --- Button (BUTTON class) messages ----------------------------------------
let BM_GETCHECK: UInt32 = 0x00F0
let BM_SETCHECK: UInt32 = 0x00F1
let BN_CLICKED: Int = 0x0000
let BST_UNCHECKED: Int64 = 0
let BST_CHECKED: Int64 = 1
let BS_PUSHBUTTON: UInt32 = 0x0000
let BS_AUTOCHECKBOX: UInt32 = 0x0003

// --- Combo box (COMBOBOX class) messages -----------------------------------
let CB_ADDSTRING: UInt32 = 0x0143
let CB_RESETCONTENT: UInt32 = 0x014B
let CB_GETCURSEL: UInt32 = 0x0147
let CB_SETCURSEL: UInt32 = 0x014E
let CBN_SELCHANGE: Int = 0x0001
let CBS_DROPDOWNLIST: UInt32 = 0x0003

// --- Window / control styles ----------------------------------------------
let WS_TABSTOP: UInt32 = 0x0001_0000
let WS_VSCROLL: UInt32 = 0x0020_0000
let WS_CLIPCHILDREN: UInt32 = 0x0200_0000
let WS_CLIPSIBLINGS: UInt32 = 0x0400_0000
let WS_VISIBLE: UInt32 = 0x1000_0000
let WS_CHILD: UInt32 = 0x4000_0000
let WS_OVERLAPPEDWINDOW: UInt32 = 0x00CF_0000
let SS_LEFT: UInt32 = 0x0000_0000
let SS_RIGHT: UInt32 = 0x0000_0002
let SS_CENTERIMAGE: UInt32 = 0x0000_0200
let SS_ENDELLIPSIS: UInt32 = 0x0000_4000

// Trackbar styles (`TBS_NOTICKS` avoids drawing thousands of tick marks)
let TBS_HORZ: UInt32 = 0x0000_0000
let TBS_NOTICKS: UInt32 = 0x0000_0010

let GWLP_ID: Int32 = -12
let kTrue: Int32 = 1
let OPAQUE_BKMODE: Int32 = 2
let CLEARTYPE_QUALITY_VALUE: UInt32 = 5
let DEFAULT_CHARSET_VALUE: UInt32 = 1
let DWMWA_USE_IMMERSIVE_DARK_MODE: UInt32 = 20

// --- Sidebar theme colors (COLORREF is 0x00BBGGRR) -------------------------
@inline(__always)
func win32RGB(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt32 {
    UInt32(r) | (UInt32(g) << 8) | (UInt32(b) << 16)
}

/// Clean Windows 11 light sidebar surface (`#F4F5F8`) matching v6 standard controls.
let PANEL_BG_COLORREF: UInt32 = win32RGB(244, 245, 248)
/// Primary text color (`#181C24`).
let PANEL_TEXT_COLORREF: UInt32 = win32RGB(24, 28, 36)
/// Muted subtitle color (`#646E7D`).
let PANEL_MUTED_COLORREF: UInt32 = win32RGB(100, 110, 125)
/// Section header accent blue (`#2563EB`).
let PANEL_ACCENT_COLORREF: UInt32 = win32RGB(37, 99, 235)
/// Active model name badge color (`#0F766E`).
let PANEL_MODEL_COLORREF: UInt32 = win32RGB(15, 118, 110)

// --- Raw Win32 entry points (`@_silgen_name` wrappers) ---------------------
@_silgen_name("SendMessageW")
func win32SendMessageW(_ hWnd: UnsafeRawPointer?, _ msg: UInt32, _ wParam: UInt64, _ lParam: Int64) -> Int64

@_silgen_name("GetDlgCtrlID")
func win32GetDlgCtrlID(_ hWnd: UnsafeRawPointer?) -> Int32

@_silgen_name("SetWindowLongW")
func win32SetWindowLongW(_ hWnd: UnsafeRawPointer?, _ nIndex: Int32, _ dwNewLong: Int32) -> Int32

@_silgen_name("MoveWindow")
func win32MoveWindow(_ hWnd: UnsafeRawPointer?, _ x: Int32, _ y: Int32, _ nWidth: Int32, _ nHeight: Int32, _ bRepaint: Int32) -> Int32

@_silgen_name("GetClientRect")
func win32GetClientRect(_ hWnd: UnsafeRawPointer?, _ lpRect: UnsafeMutablePointer<RECT>) -> Int32

@_silgen_name("PeekMessageW")
func win32PeekMessageW(
    _ lpMsg: UnsafeMutablePointer<MSG>,
    _ hWnd: UnsafeRawPointer?,
    _ wMsgFilterMin: UInt32,
    _ wMsgFilterMax: UInt32,
    _ wRemoveMsg: UInt32
) -> Int32

@_silgen_name("MsgWaitForMultipleObjectsEx")
func win32MsgWaitForMultipleObjectsEx(
    _ nCount: UInt32,
    _ pHandles: UnsafeRawPointer?,
    _ dwMilliseconds: UInt32,
    _ dwWakeMask: UInt32,
    _ dwFlags: UInt32
) -> UInt32

@_silgen_name("CoInitializeEx")
func win32CoInitializeEx(_ pvReserved: UnsafeMutableRawPointer?, _ dwCoInit: UInt32) -> Int32

@_silgen_name("SetCapture")
func win32SetCapture(_ hWnd: UnsafeRawPointer?) -> UnsafeRawPointer?

@_silgen_name("ReleaseCapture")
func win32ReleaseCapture() -> Int32

@_silgen_name("SetFocus")
func win32SetFocus(_ hWnd: UnsafeRawPointer?) -> UnsafeRawPointer?

@_silgen_name("EnableWindow")
func win32EnableWindow(_ hWnd: UnsafeRawPointer?, _ bEnable: Int32) -> Int32

@_silgen_name("InvalidateRect")
func win32InvalidateRect(_ hWnd: UnsafeRawPointer?, _ lpRect: UnsafeRawPointer?, _ bErase: Int32) -> Int32

@_silgen_name("CreateSolidBrush")
func win32CreateSolidBrush(_ color: UInt32) -> UnsafeMutableRawPointer?

@_silgen_name("DeleteObject")
func win32DeleteObject(_ ho: UnsafeMutableRawPointer?) -> Int32

@_silgen_name("SetBkColor")
func win32SetBkColor(_ hdc: UnsafeRawPointer?, _ color: UInt32) -> UInt32

@_silgen_name("SetTextColor")
func win32SetTextColor(_ hdc: UnsafeRawPointer?, _ color: UInt32) -> UInt32

@_silgen_name("SetBkMode")
func win32SetBkMode(_ hdc: UnsafeRawPointer?, _ mode: Int32) -> Int32

@_silgen_name("CreateFontW")
func win32CreateFontW(
    _ cHeight: Int32,
    _ cWidth: Int32,
    _ cEscapement: Int32,
    _ cOrientation: Int32,
    _ cWeight: Int32,
    _ bItalic: UInt32,
    _ bUnderline: UInt32,
    _ bStrikeOut: UInt32,
    _ iCharSet: UInt32,
    _ iOutPrecision: UInt32,
    _ iClipPrecision: UInt32,
    _ iQuality: UInt32,
    _ iPitchAndFamily: UInt32,
    _ pszFaceName: UnsafePointer<WCHAR>?
) -> UnsafeMutableRawPointer?

@_silgen_name("DwmSetWindowAttribute")
func win32DwmSetWindowAttribute(
    _ hwnd: UnsafeRawPointer?,
    _ dwAttribute: UInt32,
    _ pvAttribute: UnsafeRawPointer?,
    _ cbAttribute: UInt32
) -> Int32

@_silgen_name("CreateActCtxW")
private func win32CreateActCtxW(_ pActCtx: UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?

@_silgen_name("ActivateActCtx")
private func win32ActivateActCtx(_ hActCtx: UnsafeMutableRawPointer?, _ lpCookie: UnsafeMutablePointer<UInt64>?) -> Int32

/// 64-bit Windows `ACTCTXW` layout (`winbase.h`, 56 bytes on x64).
private struct Win32ACTCTXW {
    var cbSize: UInt32 = UInt32(MemoryLayout<Win32ACTCTXW>.size)
    var dwFlags: UInt32 = 0
    var lpSource: UnsafePointer<WCHAR>? = nil
    var wProcessorArchitecture: UInt16 = 0
    var wLangId: UInt16 = 0
    var _pad0: UInt32 = 0
    var lpAssemblyDirectory: UnsafePointer<WCHAR>? = nil
    var lpResourceName: UnsafePointer<WCHAR>? = nil
    var lpApplicationName: UnsafePointer<WCHAR>? = nil
    var hModule: UnsafeRawPointer? = nil
}

/// Activates `Microsoft.Windows.Common-Controls` v6 at runtime so Win32 renders
/// modern Windows 10/11 visual styles (rounded buttons, smooth sliders, modern combos)
/// without requiring an external `.exe.manifest` file.
func enableWin32VisualStyles() {
    let manifestXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
      <dependency>
        <dependentAssembly>
          <assemblyIdentity
              type="win32"
              name="Microsoft.Windows.Common-Controls"
              version="6.0.0.0"
              processorArchitecture="*"
              publicKeyToken="6595b64144ccf1df"
              language="*" />
        </dependentAssembly>
      </dependency>
    </assembly>
    """
    let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("FilamentWin32Demo.v6.manifest")
    try? manifestXML.write(to: tempURL, atomically: true, encoding: .utf8)

    tempURL.path.withCString(encodedAs: UTF16.self) { pathWide in
        var actCtx = Win32ACTCTXW()
        actCtx.lpSource = pathWide
        let invalidHandle = UnsafeMutableRawPointer(bitPattern: -1)
        withUnsafeMutablePointer(to: &actCtx) { ptr in
            if let handle = win32CreateActCtxW(UnsafeMutableRawPointer(ptr)), handle != invalidHandle {
                var cookie: UInt64 = 0
                _ = win32ActivateActCtx(handle, &cookie)
            }
        }
    }
}

/// Enables the Windows 10/11 dark mode title bar on a top-level `HWND`.
func enableDarkTitleBar(_ hwnd: HWND?) {
    var dark: Int32 = 1
    withUnsafePointer(to: &dark) { ptr in
        _ = win32DwmSetWindowAttribute(
            UnsafeRawPointer(hwnd),
            DWMWA_USE_IMMERSIVE_DARK_MODE,
            UnsafeRawPointer(ptr),
            UInt32(MemoryLayout<Int32>.size)
        )
    }
}

/// Creates a ClearType `Segoe UI` `HFONT` with the requested pixel height and weight.
func createSegoeUIFont(heightPx: Int32, weight: Int32 = 400) -> UnsafeMutableRawPointer? {
    "Segoe UI".withCString(encodedAs: UTF16.self) { faceWide in
        win32CreateFontW(
            -heightPx,
            0,
            0,
            0,
            weight,
            0,
            0,
            0,
            DEFAULT_CHARSET_VALUE,
            0,
            0,
            CLEARTYPE_QUALITY_VALUE,
            0,
            faceWide
        )
    }
}

// MARK: - Small Win32 Helpers

@inline(__always)
func sendMessage(_ hwnd: HWND?, _ msg: UInt32, _ wParam: UInt64 = 0, _ lParam: Int64 = 0) -> Int {
    Int(win32SendMessageW(UnsafeRawPointer(hwnd), msg, wParam, lParam))
}

@inline(__always)
func sendMessage(_ hwnd: HWND?, _ msg: UInt32, _ text: UnsafePointer<WCHAR>) {
    _ = win32SendMessageW(UnsafeRawPointer(hwnd), msg, 0, Int64(Int(bitPattern: text)))
}

@inline(__always)
func setFont(_ hwnd: HWND?, _ hFont: UnsafeMutableRawPointer?) {
    guard let hFont else { return }
    _ = win32SendMessageW(
        UnsafeRawPointer(hwnd),
        WM_SETFONT,
        UInt64(UInt(bitPattern: hFont)),
        Int64(kTrue)
    )
}

@inline(__always)
func setText(_ hwnd: HWND?, _ text: String) {
    text.withCString(encodedAs: UTF16.self) { wide in
        sendMessage(hwnd, WM_SETTEXT, wide)
    }
    _ = win32InvalidateRect(UnsafeRawPointer(hwnd), nil, kTrue)
}

@inline(__always)
func hwndFromLPARAM(_ lParam: Int64) -> UnsafeRawPointer? {
    UnsafeRawPointer(bitPattern: Int(truncatingIfNeeded: lParam))
}

@inline(__always)
func ptrFromWPARAM(_ wParam: UInt64) -> UnsafeRawPointer? {
    UnsafeRawPointer(bitPattern: UInt(truncatingIfNeeded: wParam))
}

@inline(__always)
func lowWord(_ v: UInt64) -> Int { Int(v & 0xFFFF) }

@inline(__always)
func highWord(_ v: UInt64) -> Int { Int((v >> 16) & 0xFFFF) }

@inline(__always)
func mouseX(_ lParam: Int64) -> Int {
    Int(Int16(truncatingIfNeeded: lParam & 0xFFFF))
}

@inline(__always)
func mouseY(_ lParam: Int64) -> Int {
    Int(Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF))
}

@inline(__always)
func wheelDelta(_ wParam: UInt64) -> Double {
    Double(Int16(truncatingIfNeeded: (wParam >> 16) & 0xFFFF)) / 120.0
}
