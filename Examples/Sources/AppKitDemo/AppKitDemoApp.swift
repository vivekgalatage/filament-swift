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
            title: "Reset Morph Targets",
            action: #selector(resetMorphTargetsMenuClicked),
            keyEquivalent: "m"
        ))
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Orbit",
            action: #selector(toggleOrbitMenuClicked),
            keyEquivalent: " "
        ))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Floating Companion Window",
            action: #selector(toggleOverlayMenuClicked),
            keyEquivalent: "l"
        ))
        let viewItem = NSMenuItem()
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let shadingMenu = NSMenu(title: "Shading")
        shadingMenu.addItem(NSMenuItem(
            title: "Standard PBR",
            action: #selector(pbrShadingMenuClicked),
            keyEquivalent: "1"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "Toon Cel (Cartoon)",
            action: #selector(toonCelShadingMenuClicked),
            keyEquivalent: "2"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "Toon + Inked Outline",
            action: #selector(toonWithOutlineShadingMenuClicked),
            keyEquivalent: "3"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "PBR + Inked Outline",
            action: #selector(pbrWithOutlineShadingMenuClicked),
            keyEquivalent: "4"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "Outline Only (Transparent Body)",
            action: #selector(outlineOnlyShadingMenuClicked),
            keyEquivalent: "5"
        ))

        shadingMenu.addItem(NSMenuItem.separator())
        let outlineColorMenu = NSMenu(title: "Outline Color")
        outlineColorMenu.addItem(NSMenuItem(title: "Charcoal Ink (Classic)", action: #selector(outlineColorCharcoalClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Pure Black", action: #selector(outlineColorBlackClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Drafting Sepia", action: #selector(outlineColorSepiaClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Navy Blueprint", action: #selector(outlineColorNavyClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Anime Brown", action: #selector(outlineColorBrownClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Crimson Inked", action: #selector(outlineColorCrimsonClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Chalk White", action: #selector(outlineColorWhiteClicked), keyEquivalent: ""))
        outlineColorMenu.addItem(NSMenuItem(title: "Neon Cyan", action: #selector(outlineColorCyanClicked), keyEquivalent: ""))
        let outlineColorItem = NSMenuItem(title: "Solid Outline Color", action: nil, keyEquivalent: "")
        outlineColorItem.submenu = outlineColorMenu
        shadingMenu.addItem(outlineColorItem)

        let outlineStyleMenu = NSMenu(title: "Outline Pattern & Gradient")
        outlineStyleMenu.addItem(NSMenuItem(title: "Solid Single Color", action: #selector(outlineStyleSolidClicked), keyEquivalent: ""))
        outlineStyleMenu.addItem(NSMenuItem(title: "Vertical Height Gradient", action: #selector(outlineStyleVerticalClicked), keyEquivalent: ""))
        outlineStyleMenu.addItem(NSMenuItem(title: "Radial Angle Gradient (360°)", action: #selector(outlineStyleRadialClicked), keyEquivalent: ""))
        outlineStyleMenu.addItem(NSMenuItem(title: "VIBGYOR Rainbow Spectrum", action: #selector(outlineStyleRainbowClicked), keyEquivalent: ""))
        outlineStyleMenu.addItem(NSMenuItem(title: "Random Multi-Color Facets", action: #selector(outlineStyleFacetsClicked), keyEquivalent: ""))
        let outlineStyleItem = NSMenuItem(title: "Outline Pattern & Gradient", action: nil, keyEquivalent: "")
        outlineStyleItem.submenu = outlineStyleMenu
        shadingMenu.addItem(outlineStyleItem)

        shadingMenu.addItem(NSMenuItem.separator())
        shadingMenu.addItem(NSMenuItem(
            title: "🎲 Randomize Outline Colors",
            action: #selector(randomizeOutlineColorsMenuClicked),
            keyEquivalent: "k"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "Apply VIBGYOR Rainbow Palette",
            action: #selector(vibgyorPaletteMenuClicked),
            keyEquivalent: ""
        ))

        let shadingItem = NSMenuItem()
        shadingItem.submenu = shadingMenu
        mainMenu.addItem(shadingItem)

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
        scene.onOverlayStateChanged = { [weak self] active in
            self?.inspector.syncOverlayUI(active: active)
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

    @objc private func resetMorphTargetsMenuClicked() {
        inspector.resetAllMorphTargetsClicked()
    }

    @objc private func toggleOrbitMenuClicked() {
        inspector.toggleOrbitClicked()
    }

    @objc private func toggleOverlayMenuClicked() {
        inspector.toggleOverlayClicked()
    }

    @objc private func pbrShadingMenuClicked() {
        scene?.setShadingMode(.standardPBR)
        inspector?.syncShadingMode()
    }

    @objc private func toonCelShadingMenuClicked() {
        scene?.setShadingMode(.toonCel)
        inspector?.syncShadingMode()
    }

    @objc private func toonWithOutlineShadingMenuClicked() {
        scene?.setShadingMode(.toonWithOutline)
        inspector?.syncShadingMode()
    }

    @objc private func pbrWithOutlineShadingMenuClicked() {
        scene?.setShadingMode(.pbrWithOutline)
        inspector?.syncShadingMode()
    }

    @objc private func outlineOnlyShadingMenuClicked() {
        scene?.setShadingMode(.outlineOnly)
        inspector?.syncShadingMode()
    }

    @objc private func outlineColorCharcoalClicked() { inspector?.setOutlineColorPreset(index: 0) }
    @objc private func outlineColorBlackClicked() { inspector?.setOutlineColorPreset(index: 1) }
    @objc private func outlineColorSepiaClicked() { inspector?.setOutlineColorPreset(index: 2) }
    @objc private func outlineColorNavyClicked() { inspector?.setOutlineColorPreset(index: 3) }
    @objc private func outlineColorBrownClicked() { inspector?.setOutlineColorPreset(index: 4) }
    @objc private func outlineColorCrimsonClicked() { inspector?.setOutlineColorPreset(index: 5) }
    @objc private func outlineColorWhiteClicked() { inspector?.setOutlineColorPreset(index: 6) }
    @objc private func outlineColorCyanClicked() { inspector?.setOutlineColorPreset(index: 7) }

    @objc private func outlineStyleSolidClicked() { inspector?.setOutlineGradientMode(.solid) }
    @objc private func outlineStyleVerticalClicked() { inspector?.setOutlineGradientMode(.vertical) }
    @objc private func outlineStyleRadialClicked() { inspector?.setOutlineGradientMode(.radial) }
    @objc private func outlineStyleRainbowClicked() { inspector?.setOutlineGradientMode(.rainbow) }
    @objc private func outlineStyleFacetsClicked() { inspector?.setOutlineGradientMode(.randomFacets) }
    @objc private func randomizeOutlineColorsMenuClicked() { inspector?.onRandomizeColorsClicked() }
    @objc private func vibgyorPaletteMenuClicked() {
        inspector?.applyVibgyorPalette()
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
