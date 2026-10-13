import AppKit
import UniformTypeIdentifiers
import Filament
import FilamentAppKit

/// macOS AppKit application delegate and window controller for the FilamentSwift demo.
@MainActor
final class AppKitDemoDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var scene: DemoSceneController!
    private var inspector: InspectorView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupWindow()
        setupSceneAndInspector()
        scene.loadInitialModel()
        scene.startRenderLoop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        scene?.shutdown()
    }

    func windowDidResize(_ notification: Notification) {
        scene?.updateViewport()
    }

    // MARK: - Window & Menu setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(
            title: "Quit Filament AppKit Demo",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        appMenuItem.submenu = appMenu

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(
            title: "Open Model…",
            action: #selector(openModelMenuClicked),
            keyEquivalent: "o"
        ))
        let fileItem = NSMenuItem()
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(
            title: "Reset PBR Settings",
            action: #selector(resetPBRMenuClicked),
            keyEquivalent: "r"
        ))
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Orbit",
            action: #selector(toggleOrbitMenuClicked),
            keyEquivalent: " "
        ))
        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        NSApplication.shared.mainMenu = mainMenu
    }

    private func setupWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 1180, height: 760)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Filament Swift — AppKit PBR Demo"
        window.titlebarAppearsTransparent = true
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.minSize = NSSize(width: 940, height: 620)
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func setupSceneAndInspector() {
        guard let contentView = window.contentView else { return }

        scene = DemoSceneController(frame: contentView.bounds)
        contentView.addSubview(scene.filamentView)

        inspector = InspectorView(
            scene: scene,
            in: contentView,
            onOpenModelRequested: { [weak self] in
                self?.presentOpenModelPanel()
            },
            onToggleTransparencyRequested: { [weak self] in
                guard let self else { return false }
                return self.scene.toggleTransparency(in: self.window)
            }
        )

        scene.onModelStateChanged = { [weak self] in
            self?.inspector.syncModelUI()
        }
        scene.onFrameRendered = { [weak self] fps, orbiting in
            self?.inspector.updateStatusBadge(fps: fps, isOrbiting: orbiting)
        }
    }

    // MARK: - Native File Open Dialog

    func presentOpenModelPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select glTF Binary (.glb) Model"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let glbType = UTType(filenameExtension: "glb") {
            panel.allowedContentTypes = [glbType]
        }
        if panel.runModal() == .OK, let url = panel.url {
            scene.loadModel(from: url)
        }
    }

    @objc private func openModelMenuClicked() {
        presentOpenModelPanel()
    }

    @objc private func resetPBRMenuClicked() {
        inspector.resetPBRClicked()
    }

    @objc private func toggleOrbitMenuClicked() {
        inspector.toggleOrbitClicked()
    }
}

@main
struct AppKitDemoApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppKitDemoDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
