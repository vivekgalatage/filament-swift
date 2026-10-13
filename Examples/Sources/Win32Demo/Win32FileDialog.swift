import Foundation
import WinSDK

@_silgen_name("GetOpenFileNameW")
private func win32GetOpenFileNameW(_ lpofn: UnsafeMutableRawPointer) -> Int32

private let OFN_NOCHANGEDIR: UInt32 = 0x0000_0008
private let OFN_PATHMUSTEXIST: UInt32 = 0x0000_0800
private let OFN_FILEMUSTEXIST: UInt32 = 0x0000_1000

/// Exact 64-bit Windows ABI layout for `OPENFILENAMEW` (`commdlg.h`, 152 bytes on x64).
private struct Win32OPENFILENAMEW {
    var lStructSize: UInt32 = UInt32(MemoryLayout<Win32OPENFILENAMEW>.size)
    var _pad0: UInt32 = 0
    var hwndOwner: UnsafeRawPointer? = nil
    var hInstance: UnsafeRawPointer? = nil
    var lpstrFilter: UnsafePointer<WCHAR>? = nil
    var lpstrCustomFilter: UnsafeMutablePointer<WCHAR>? = nil
    var nMaxCustFilter: UInt32 = 0
    var nFilterIndex: UInt32 = 1
    var lpstrFile: UnsafeMutablePointer<WCHAR>? = nil
    var nMaxFile: UInt32 = 0
    var _pad1: UInt32 = 0
    var lpstrFileTitle: UnsafeMutablePointer<WCHAR>? = nil
    var nMaxFileTitle: UInt32 = 0
    var _pad2: UInt32 = 0
    var lpstrInitialDir: UnsafePointer<WCHAR>? = nil
    var lpstrTitle: UnsafePointer<WCHAR>? = nil
    var Flags: UInt32 = 0
    var nFileOffset: UInt16 = 0
    var nFileExtension: UInt16 = 0
    var lpstrDefExt: UnsafePointer<WCHAR>? = nil
    var lCustData: Int64 = 0
    var lpfnHook: UnsafeRawPointer? = nil
    var lpTemplateName: UnsafePointer<WCHAR>? = nil
    var pvReserved: UnsafeRawPointer? = nil
    var dwReserved: UInt32 = 0
    var FlagsEx: UInt32 = 0
}

/// Presents the native Win32 Open File dialog (`GetOpenFileNameW`) filtered to `.glb` files.
enum Win32FileDialog {
    static func promptForGlbFile(owner: HWND?) -> URL? {
        let filterString = "glTF Binary (*.glb)\0*.glb\0All Files (*.*)\0*.*\0\0"
        let filterWide = Array(filterString.utf16)
        let titleString = "Select glTF Binary (.glb) Model"
        let defExtString = "glb"
        var fileBuffer = [WCHAR](repeating: 0, count: 1024)

        let chosen: Bool = filterWide.withUnsafeBufferPointer { filterBuf in
            titleString.withCString(encodedAs: UTF16.self) { titleWide in
                defExtString.withCString(encodedAs: UTF16.self) { defExtWide in
                    fileBuffer.withUnsafeMutableBufferPointer { fileBuf in
                        var ofn = Win32OPENFILENAMEW()
                        ofn.hwndOwner = UnsafeRawPointer(owner)
                        ofn.lpstrFilter = filterBuf.baseAddress
                        ofn.lpstrFile = fileBuf.baseAddress
                        ofn.nMaxFile = UInt32(fileBuf.count)
                        ofn.lpstrTitle = titleWide
                        ofn.lpstrDefExt = defExtWide
                        ofn.Flags = OFN_PATHMUSTEXIST | OFN_FILEMUSTEXIST | OFN_NOCHANGEDIR
                        return withUnsafeMutablePointer(to: &ofn) { ptr in
                            win32GetOpenFileNameW(UnsafeMutableRawPointer(ptr)) != 0
                        }
                    }
                }
            }
        }
        guard chosen else { return nil }
        let end = fileBuffer.firstIndex(of: 0) ?? fileBuffer.count
        let path = String(decoding: fileBuffer[..<end], as: UTF16.self)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }
}
