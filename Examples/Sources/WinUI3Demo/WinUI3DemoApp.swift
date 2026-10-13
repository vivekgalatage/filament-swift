@preconcurrency import WinSDK
import Foundation
@preconcurrency import CWinRT
@preconcurrency @_spi(WinRTInternal) @_spi(WinRTImplements) import WindowsFoundation
@preconcurrency import UWP
@preconcurrency import WinAppSDK
@preconcurrency @_spi(WinRTInternal) import WinUI

/// A WinUI 3 `Application` is required even for XAML islands: XAML consults it for
/// `IXamlMetadataProvider` to resolve control types.
final class DemoApplication: Application, IXamlMetadataProvider {
    /// Set before any XAML type lookup; read by XAML on the UI thread.
    nonisolated(unsafe) static var metadataProvider: XamlControlsXamlMetaDataProvider?

    override public init() { super.init() }

    override open func queryInterface(_ iid: WindowsFoundation.IID) -> IUnknownRef? {
        switch iid {
        case __ABI_Microsoft_UI_Xaml_Markup.IXamlMetadataProviderWrapper.IID:
            let ixmp = __ABI_Microsoft_UI_Xaml_Markup.IXamlMetadataProviderWrapper(self)
            return ixmp?.queryInterface(iid)
        default:
            return super.queryInterface(iid)
        }
    }

    public func getXamlType(_ type: WinUI.TypeName) throws -> WinUI.AnyIXamlType! {
        try Self.metadataProvider?.getXamlType(type)
    }

    public func getXamlType(_ fullName: String) throws -> WinUI.AnyIXamlType! {
        try Self.metadataProvider?.getXamlType(fullName)
    }

    public func getXmlnsDefinitions() throws -> [WinUI.XmlnsDefinition] {
        try Self.metadataProvider?.getXmlnsDefinitions() ?? []
    }
}

/// Initializes the Windows App SDK bootstrapper and WinUI 3 XAML island thread context.
@MainActor
enum WinAppSDKBootstrap {
    /// Windows App SDK runtime version handed to `MddBootstrapInitialize2` (0x00010006 == 1.6).
    private static let bootstrapVersion: UInt32 = 0x0001_0006

    static func initializeRuntime() -> Bool {
        let exeDir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        let bootstrapPath = exeDir + "\\Microsoft.WindowsAppRuntime.Bootstrap.dll"
        guard let handle = bootstrapPath.withCString(encodedAs: UTF16.self, { LoadLibraryW($0) }) else {
            print("[WinUI3Demo] LoadLibraryW failed for \(bootstrapPath) (error \(GetLastError())). "
                + "Install the Windows App Runtime, or ship it next to the exe.")
            return false
        }
        guard let proc = GetProcAddress(handle, "MddBootstrapInitialize2") else {
            print("[WinUI3Demo] MddBootstrapInitialize2 not found; wrong Windows App Runtime version.")
            return false
        }
        typealias InitFn = @convention(c) (UInt32, UnsafePointer<UInt16>?, UInt64, UInt32) -> Int32
        let hr = unsafeBitCast(proc, to: InitFn.self)(bootstrapVersion, nil, 0, 0)
        if hr < 0 {
            print("[WinUI3Demo] MddBootstrapInitialize2 failed: 0x\(String(UInt32(bitPattern: hr), radix: 16))")
            return false
        }
        return true
    }

    static func createWinUIApplication() -> DemoApplication? {
        do {
            _ = try DispatcherQueueController.createOnCurrentThread()
            DemoApplication.metadataProvider = XamlControlsXamlMetaDataProvider()
            let app = DemoApplication()
            _ = try WindowsXamlManager.initializeForCurrentThread()
            app.dispatcherShutdownMode = .onLastWindowClose
            app.resources.mergedDictionaries.append(XamlControlsResources())
            return app
        } catch {
            print("[WinUI3Demo] WinUI 3 initialisation failed: \(error)")
            return nil
        }
    }
}

@main
struct WinUI3DemoMain {
    static func main() {
        let exitCode = DemoHost.shared.run()
        exit(exitCode)
    }
}
