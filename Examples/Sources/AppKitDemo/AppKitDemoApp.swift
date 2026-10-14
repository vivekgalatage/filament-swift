import AppKit
import UniformTypeIdentifiers
import Filament
import FilamentAppKit

/// macOS AppKit application delegate and window controller for the FilamentSwift demo.
@MainActor
final class AppKitDemoDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSToolbarDelegate {
    private var window: NSWindow!
    private var scene: DemoSceneController!
    private var inspector: InspectorView!
    private var demoHUD: DemoHUDView?
    private var demoToolbarItem: NSToolbarItem?
    private var demoMenuItem: NSMenuItem?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        setupWindow()
        setupSceneAndInspector()
        setupKeyMonitor()
        scene.loadInitialModel()
        scene.startRenderLoop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
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
        let demoItem = NSMenuItem(
            title: "🎬 Start Demo Reel (Auto-Cycle)",
            action: #selector(toggleDemoModeMenuClicked),
            keyEquivalent: "d"
        )
        self.demoMenuItem = demoItem
        viewMenu.addItem(demoItem)
        viewMenu.addItem(NSMenuItem.separator())

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
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Inspector Panel",
            action: #selector(toggleInspectorMenuClicked),
            keyEquivalent: "i"
        ))
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Floating Companion Window",
            action: #selector(toggleOverlayMenuClicked),
            keyEquivalent: "l"
        ))
        viewMenu.addItem(NSMenuItem(
            title: "Toggle Overlay Event Passthrough",
            action: #selector(toggleOverlayPassthroughMenuClicked),
            keyEquivalent: "p"
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
            title: "Comic Halftone (Pop-Art / Manga)",
            action: #selector(comicHalftoneShadingMenuClicked),
            keyEquivalent: "4"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "Halftone + Inked Outline",
            action: #selector(halftoneWithOutlineShadingMenuClicked),
            keyEquivalent: "5"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "PBR + Inked Outline",
            action: #selector(pbrWithOutlineShadingMenuClicked),
            keyEquivalent: "6"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "Outline Only (Transparent Body)",
            action: #selector(outlineOnlyShadingMenuClicked),
            keyEquivalent: "7"
        ))
        shadingMenu.addItem(NSMenuItem(
            title: "✏️ Handdrawn Technical Sketch",
            action: #selector(handdrawnSketchShadingMenuClicked),
            keyEquivalent: "8"
        ))

        shadingMenu.addItem(NSMenuItem.separator())
        let halftoneMenu = NSMenu(title: "Halftone Preset")
        halftoneMenu.addItem(NSMenuItem(title: "🦸 Spider-Verse Pop-Art", action: #selector(halftoneSpiderVerseClicked), keyEquivalent: ""))
        halftoneMenu.addItem(NSMenuItem(title: "🎌 Manga Screentone", action: #selector(halftoneMangaClicked), keyEquivalent: ""))
        halftoneMenu.addItem(NSMenuItem(title: "📰 Vintage CMYK Newspaper", action: #selector(halftoneCMYKClicked), keyEquivalent: ""))
        halftoneMenu.addItem(NSMenuItem(title: "✒️ Woodcut / Pen Hatching", action: #selector(halftoneHatchingClicked), keyEquivalent: ""))
        halftoneMenu.addItem(NSMenuItem(title: "🚫 Disable Halftone (Clean Cel)", action: #selector(halftoneDisabledClicked), keyEquivalent: ""))
        let halftoneItem = NSMenuItem(title: "Halftone Preset", action: nil, keyEquivalent: "")
        halftoneItem.submenu = halftoneMenu
        shadingMenu.addItem(halftoneItem)

        let sketchMenu = NSMenu(title: "Sketch Preset")
        sketchMenu.addItem(NSMenuItem(title: "📐 Architectural Drafting (White + Graphite)", action: #selector(sketchArchitecturalClicked), keyEquivalent: ""))
        sketchMenu.addItem(NSMenuItem(title: "📘 Technical Blueprint (Cyan + Navy)", action: #selector(sketchBlueprintClicked), keyEquivalent: ""))
        sketchMenu.addItem(NSMenuItem(title: "✏️ Handdrawn 2B Pencil (Wobble on Vellum)", action: #selector(sketchPencilClicked), keyEquivalent: ""))
        sketchMenu.addItem(NSMenuItem(title: "✒️ CAD Vector Wireframe (Crisp Ink)", action: #selector(sketchCADClicked), keyEquivalent: ""))
        sketchMenu.addItem(NSMenuItem(title: "📄 Transparent Mylar (Figma Ready)", action: #selector(sketchMylarClicked), keyEquivalent: ""))
        let sketchItem = NSMenuItem(title: "Technical Sketch Preset", action: nil, keyEquivalent: "")
        sketchItem.submenu = sketchMenu
        shadingMenu.addItem(sketchItem)

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

        let toolbar = NSToolbar(identifier: "AppKitDemoToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.toolbarStyle = .unified

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

        inspector.onToggleDemoModeRequested = { [weak self] in
            self?.toggleDemoMode()
        }

        scene.onModelStateChanged = { [weak self] in
            self?.inspector.syncModelUI()
        }
        scene.onOverlayStateChanged = { [weak self] active in
            self?.inspector.syncOverlayUI(active: active)
        }
        scene.onFrameRendered = { [weak self] fps, orbiting in
            self?.inspector.updateStatusBadge(fps: fps, isOrbiting: orbiting)
        }
        scene.onDemoModeStateChanged = { [weak self] active in
            self?.updateDemoModeUI(active: active)
        }
        scene.onDemoTurntableToggled = { [weak self] enabled in
            self?.demoHUD?.setTurntableState(enabled: enabled)
        }
        scene.onDemoModeStepChanged = { [weak self] stepIndex, total, title, subtitle in
            self?.demoHUD?.update(step: stepIndex + 1, total: total, title: title, subtitle: subtitle)
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

    @objc private func toggleOverlayPassthroughMenuClicked() {
        inspector.toggleEventPassthrough()
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

    @objc private func comicHalftoneShadingMenuClicked() {
        scene?.setShadingMode(.comicHalftone)
        inspector?.syncShadingMode()
    }

    @objc private func halftoneWithOutlineShadingMenuClicked() {
        scene?.setShadingMode(.halftoneWithOutline)
        inspector?.syncShadingMode()
    }

    @objc private func halftoneSpiderVerseClicked() {
        inspector?.applyHalftonePreset(FilamentToonMaterial.spiderVersePreset)
    }

    @objc private func halftoneMangaClicked() {
        inspector?.applyHalftonePreset(FilamentToonMaterial.mangaScreentonePreset)
    }

    @objc private func halftoneCMYKClicked() {
        inspector?.applyHalftonePreset(FilamentToonMaterial.cmykNewspaperPreset)
    }

    @objc private func halftoneHatchingClicked() {
        inspector?.applyHalftonePreset(FilamentToonMaterial.comicHatchingPreset)
    }

    @objc private func halftoneDisabledClicked() {
        scene?.setHalftoneMode(.disabled)
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

    @objc private func handdrawnSketchShadingMenuClicked() {
        scene?.setShadingMode(.handdrawnSketch)
        inspector?.syncShadingMode()
    }

    @objc private func sketchArchitecturalClicked() {
        scene?.setShadingMode(.handdrawnSketch)
        scene?.applySketchPreset(FilamentToonMaterial.technicalArchitecturalPreset)
        inspector?.syncShadingMode()
    }

    @objc private func sketchBlueprintClicked() {
        scene?.setShadingMode(.handdrawnSketch)
        scene?.applySketchPreset(FilamentToonMaterial.blueprintPatentPreset)
        inspector?.syncShadingMode()
    }

    @objc private func sketchPencilClicked() {
        scene?.setShadingMode(.handdrawnSketch)
        scene?.applySketchPreset(FilamentToonMaterial.handdrawnPencil2BPreset)
        inspector?.syncShadingMode()
    }

    @objc private func sketchCADClicked() {
        scene?.setShadingMode(.handdrawnSketch)
        scene?.applySketchPreset(FilamentToonMaterial.cadVectorWireframePreset)
        inspector?.syncShadingMode()
    }

    @objc private func sketchMylarClicked() {
        scene?.setShadingMode(.handdrawnSketch)
        scene?.applySketchPreset(FilamentToonMaterial.transparentMylarPreset)
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

    // MARK: - Demo Mode & Keyboard Monitoring

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                if self.scene?.isDemoModeActive == true {
                    self.stopDemoMode()
                    return nil
                }
            }

            if let firstResponder = self.window?.firstResponder as? NSTextView, firstResponder.isEditable {
                return event
            }
            if let firstResponder = self.window?.firstResponder as? NSTextField, firstResponder.isEditable {
                return event
            }

            let chars = event.charactersIgnoringModifiers?.lowercased()
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                if chars == "d" {
                    self.toggleDemoMode()
                    return nil
                } else if chars == "r" && self.scene?.isDemoModeActive == true {
                    self.toggleDemoTurntable()
                    return nil
                } else if chars == "h" && self.scene?.isDemoModeActive == true {
                    if let hud = self.demoHUD {
                        hud.isHidden.toggle()
                    }
                    return nil
                }
            }
            return event
        }
    }

    @objc func toggleDemoMode() {
        guard let window, let scene else { return }
        _ = scene.toggleDemoMode(in: window)
    }

    @objc func toggleDemoTurntable() {
        guard let scene, scene.isDemoModeActive else { return }
        let enabled = scene.toggleDemoTurntable()
        demoHUD?.setTurntableState(enabled: enabled)
    }

    func stopDemoMode() {
        guard let window, let scene, scene.isDemoModeActive else { return }
        scene.stopDemoMode(in: window)
    }

    @objc private func toggleDemoModeMenuClicked() {
        toggleDemoMode()
    }

    @objc private func toggleInspectorMenuClicked() {
        inspector.setHidden(!inspector.isHidden)
    }

    private func updateDemoModeUI(active: Bool) {
        inspector.syncDemoModeUI(active: active)
        inspector.setHidden(active)
        window.titleVisibility = active ? .hidden : .visible

        if active {
            demoMenuItem?.title = "⏹ Stop Demo Reel"
            demoToolbarItem?.label = "Stop Reel"
            demoToolbarItem?.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Stop Reel")

            if demoHUD == nil, let contentView = window.contentView {
                let hud = DemoHUDView()
                hud.onExitRequested = { [weak self] in
                    self?.stopDemoMode()
                }
                hud.onTurntableToggleRequested = { [weak self] in
                    self?.toggleDemoTurntable()
                }
                hud.setTurntableState(enabled: scene.isDemoTurntableEnabled)
                hud.present(in: contentView)
                demoHUD = hud
            }
        } else {
            demoMenuItem?.title = "🎬 Start Demo Reel (Auto-Cycle)"
            demoToolbarItem?.label = "Demo Reel"
            demoToolbarItem?.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Demo Reel")

            demoHUD?.dismiss()
            demoHUD = nil
            inspector.syncShadingMode()
        }
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .demoMode:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Demo Reel"
            item.paletteLabel = "Demo Reel"
            item.toolTip = "Start automated product showcase reel (D or Esc)"
            item.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Demo Reel")
            item.target = self
            item.action = #selector(toggleDemoModeMenuClicked)
            demoToolbarItem = item
            return item

        case .openModel:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Open Model"
            item.paletteLabel = "Open Model"
            item.toolTip = "Load glTF binary (.glb) model"
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Open Model")
            item.target = self
            item.action = #selector(openModelMenuClicked)
            return item

        case .toggleOverlay:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Companion"
            item.paletteLabel = "Companion Window"
            item.toolTip = "Toggle Floating Transparent Companion Window"
            item.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Companion")
            item.target = self
            item.action = #selector(toggleOverlayMenuClicked)
            return item

        case .toggleInspector:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Inspector"
            item.paletteLabel = "Toggle Inspector"
            item.toolTip = "Show or hide inspector panel"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: "Inspector")
            item.target = self
            item.action = #selector(toggleInspectorMenuClicked)
            return item

        default:
            return nil
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.demoMode, .flexibleSpace, .openModel, .toggleOverlay, .toggleInspector]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.demoMode, .openModel, .toggleOverlay, .toggleInspector, .flexibleSpace, .space]
    }
}

extension NSToolbarItem.Identifier {
    static let demoMode = NSToolbarItem.Identifier("com.filament.appkit.demoMode")
    static let openModel = NSToolbarItem.Identifier("com.filament.appkit.openModel")
    static let toggleOverlay = NSToolbarItem.Identifier("com.filament.appkit.toggleOverlay")
    static let toggleInspector = NSToolbarItem.Identifier("com.filament.appkit.toggleInspector")
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
