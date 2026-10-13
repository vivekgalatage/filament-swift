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
let WM_SETTEXT: UInt32 = 0x000C
let WM_SIZE: UInt32 = 0x0005
let WM_KEYDOWN: UInt32 = 0x0100
let WM_COMMAND: UInt32 = 0x0111
let WM_HSCROLL: UInt32 = 0x0114
let WM_QUIT: UInt32 = 0x0012

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
let CB_GETCURSEL: UInt32 = 0x0147
let CB_ADDSTRING: UInt32 = 0x0143
let CB_SETCURSEL: UInt32 = 0x014E
let CBN_SELCHANGE: Int = 0x0001
let CBS_DROPDOWNLIST: UInt32 = 0x0003

// --- Window / control styles ----------------------------------------------
let WS_TABSTOP: UInt32 = 0x0001_0000
let WS_VSCROLL: UInt32 = 0x0020_0000
let WS_VISIBLE: UInt32 = 0x1000_0000
let WS_CHILD: UInt32 = 0x4000_0000
let WS_OVERLAPPEDWINDOW: UInt32 = 0x00CF_0000
let WS_EX_CLIENTEDGE: UInt32 = 0x0000_0200
let SS_LEFT: UInt32 = 0x0000_0000
let SS_RIGHT: UInt32 = 0x0000_0002
let SS_CENTERIMAGE: UInt32 = 0x0000_2000

// Trackbar styles
let TBS_HORZ: UInt32 = 0x0000_0000
let TBS_ENDSEL: UInt32 = 0x0000_0800
let TBS_AUTOTICKS: UInt32 = 0x0000_0100

let GWLP_ID: Int32 = -12
let kTrue: Int32 = 1

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
func setText(_ hwnd: HWND?, _ text: String) {
    text.withCString(encodedAs: UTF16.self) { wide in
        sendMessage(hwnd, WM_SETTEXT, wide)
    }
}

@inline(__always)
func hwndFromLPARAM(_ lParam: Int64) -> UnsafeRawPointer? {
    UnsafeRawPointer(bitPattern: Int(bitPattern: lParam))
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
