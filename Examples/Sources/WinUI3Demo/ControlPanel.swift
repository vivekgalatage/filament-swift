// =============================================================================
// WinUI 3 control panel for the FilamentSwift demo.
//
// Same PBR controls as the AppKit and GTK demos, expressed with WinUI 3 controls and
// hosted in a DesktopWindowXamlSource island.
//
// Every API used here is taken from the working projection in vaiu/src/setu:
//   * events:            control.click.addHandler { _, _ in ... }   (Button.click is
//                        `Event<WinUI.RoutedEventHandler>`)
//   * structs:           WinUI.Thickness(left:top:right:bottom:)
//                        WinUI.CornerRadius(topLeft:topRight:bottomRight:bottomLeft:)
//   * brushes:           SolidColorBrush(UWP.Color(a:r:g:b:))
//   * sizing:            .width / .height are Double (DIPs)
//   * Grid.setColumn(element, index) throws
//
// Slider / CheckBox / ComboBox are NOT in that reference projection; they are listed
// as "NEW" in WinUIProjections/projections.json and are the most likely things to
// need adjusting.
// =============================================================================

import Foundation
import Filament
@preconcurrency @_spi(WinRTInternal) import WinUI
@preconcurrency import UWP

@MainActor
final class ControlPanel {
    private let host: DemoHost
    private let rootBorder = Border()
    private let scrollViewer = ScrollViewer()
    private let root = StackPanel()

    private var sliders: [SliderBinding] = []
    private var toggles: [ToggleBinding] = []
    private var combo: ComboBox?
    private var antiAliasingCombo: ComboBox?
    private var modelLabel: TextBlock?
    private var animHeader: TextBlock?
    private var animCombo: ComboBox?
    private var studioPresetCombo: ComboBox?
    private var overlayToggleButton: Button?
    private var overlayClickThroughToggle: CheckBox?
    private var autoOrbitToggle: CheckBox?
    private var isSyncingAnimations = false
    private var isSyncingBackground = false

    private var shadingCombo: ComboBox?
    private var outlineGradientCombo: ComboBox?
    private var outlineThicknessSlider: Slider?
    private var outlineFlowSpeedSlider: Slider?
    private var outlineGradientScaleSlider: Slider?
    private var outlineNoiseScaleSlider: Slider?
    private var halftonePresetCombo: ComboBox?
    private var halftoneModeCombo: ComboBox?
    private var halftoneTargetCombo: ComboBox?
    private var halftoneScaleSlider: Slider?
    private var halftoneAngleSlider: Slider?
    private var halftoneDotSizeSlider: Slider?
    private var halftoneHardnessSlider: Slider?
    private var halftoneBlendSlider: Slider?
    private var isSyncingStylized = false

    init(host: DemoHost) {
        self.host = host
        build()
    }

    var rootElement: UIElement { rootBorder }

    // MARK: - Construction

    private func build() {
        rootBorder.requestedTheme = .dark
        rootBorder.background = SolidColorBrush(UWP.Color(a: 255, r: 28, g: 28, b: 32))
        rootBorder.borderBrush = SolidColorBrush(UWP.Color(a: 255, r: 52, g: 52, b: 58))
        rootBorder.borderThickness = WinUI.Thickness(left: 1, top: 0, right: 0, bottom: 0)
        rootBorder.child = scrollViewer

        root.spacing = 8
        root.padding = WinUI.Thickness(left: 16, top: 16, right: 16, bottom: 16)
        scrollViewer.content = root

        let title = TextBlock()
        title.text = "Filament Swift"
        title.fontSize = 20
        root.children.append(title)

        let subtitle = TextBlock()
        subtitle.text = "WinUI 3 island · Vulkan · glTF PBR"
        subtitle.foreground = SolidColorBrush(UWP.Color(a: 255, r: 165, g: 165, b: 175))
        root.children.append(subtitle)

        addSection("Model")
        addModelControls()

        addStylizedSection()

        addSection("Lighting")
        addSlider(\.keyLightIntensity, "Key light", 0, 200_000)
        addSlider(\.fillLightIntensity, "Fill light", 0, 200_000)
        addSlider(\.ambientIntensity, "Ambient", 0, 100_000)
        addToggle(\.shadowsEnabled, "Shadows")

        addSection("Tone Mapping")
        addToneMappingCombo()
        addSlider(\.exposure, "Exposure", 0.1, 4.0, step: 0.01)
        addSlider(\.contrast, "Contrast", 0, 2.0, step: 0.01)
        addSlider(\.saturation, "Saturation", 0, 2.0, step: 0.01)
        addSlider(\.vibrance, "Vibrance", 0, 2.0, step: 0.01)
        addSlider(\.whiteBalance, "White balance", -1, 1, step: 0.01)

        addSection("Anti-Aliasing")
        addAntiAliasingCombo()
        addToggle(\.dithering, "Dithering")

        addSection("Effects")
        addToggle(\.bloomEnabled, "Bloom")
        addSlider(\.bloomStrength, "Bloom strength", 0, 1, step: 0.01)
        addToggle(\.vignetteEnabled, "Vignette")
        addToggle(\.occlusionEnabled, "Ambient occlusion")
        addToggle(\.reflectionsEnabled, "Reflections (SSR)")
        addToggle(\.depthOfFieldEnabled, "Depth of field")

        addSection("Scene")
        let orbitCheck = CheckBox()
        orbitCheck.content = "Auto-orbit camera"
        orbitCheck.isChecked = host.camera.isAutoOrbiting
        orbitCheck.checked.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.camera.isAutoOrbiting = true }
        }
        orbitCheck.unchecked.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.camera.isAutoOrbiting = false }
        }
        root.children.append(orbitCheck)
        self.autoOrbitToggle = orbitCheck

        let resetCam = Button()
        resetCam.content = "Reset View"
        resetCam.click.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.resetCamera() }
        }
        root.children.append(resetCam)

        let reset = Button()
        reset.content = "Reset PBR Settings"
        reset.click.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.host.resetPBR()
                self?.syncFromSettings()
            }
        }
        root.children.append(reset)

        addBackgroundSection()
        addAssistantOverlaySection()

        syncFromSettings()
        syncModelAndAnimations()
    }

    private func addAssistantOverlaySection() {
        addSection("Floating Assistant Overlay")

        let toggleBtn = Button()
        toggleBtn.content = host.isOverlayVisible ? "Hide Floating Assistant" : "Show Floating Assistant"
        toggleBtn.click.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.host.toggleAssistantOverlay()
            }
        }
        root.children.append(toggleBtn)
        self.overlayToggleButton = toggleBtn

        let clickCheck = CheckBox()
        clickCheck.content = "Click-through (pass clicks to desktop)"
        clickCheck.isChecked = false
        clickCheck.checked.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.setOverlayClickThrough(true) }
        }
        clickCheck.unchecked.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.setOverlayClickThrough(false) }
        }
        root.children.append(clickCheck)
        self.overlayClickThroughToggle = clickCheck

        let desc = TextBlock()
        desc.textWrapping = .wrap
        desc.fontSize = 12
        desc.foreground = SolidColorBrush(UWP.Color(a: 255, r: 160, g: 165, b: 175))
        desc.margin = WinUI.Thickness(left: 0, top: 4, right: 0, bottom: 4)
        desc.text = "Spawns a transparent borderless 3D companion window (press [A]). Floats over ANY application or the desktop with soft per-pixel alpha. Drag with mouse to move!"
        root.children.append(desc)
    }

    func syncAssistantOverlayUI() {
        overlayToggleButton?.content = host.isOverlayVisible ? "Hide Floating Assistant" : "Show Floating Assistant"
    }

    private func addBackgroundSection() {
        addSection("Studio Background")

        let studioCombo = ComboBox()
        for preset in StudioPreset.allCases {
            let item = ComboBoxItem()
            item.content = preset.rawValue
            studioCombo.items.append(item)
        }
        studioCombo.selectedIndex = Int32(StudioPreset.allCases.firstIndex(of: host.currentStudioPreset) ?? 0)
        studioCombo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingBackground else { return }
                let idx = Int(studioCombo.selectedIndex)
                guard idx >= 0, idx < StudioPreset.allCases.count else { return }
                self.host.setStudioPreset(StudioPreset.allCases[idx])
            }
        }
        root.children.append(studioCombo)
        self.studioPresetCombo = studioCombo

        let desc = TextBlock()
        desc.textWrapping = .wrap
        desc.fontSize = 12
        desc.foreground = SolidColorBrush(UWP.Color(a: 255, r: 160, g: 165, b: 175))
        desc.margin = WinUI.Thickness(left: 0, top: 4, right: 0, bottom: 4)
        desc.text = "Solid studio backdrop via Filament clear color (press [B] to cycle). Desktop see-through is not supported by Windows Vulkan HWND swapchains."
        root.children.append(desc)
    }

    private func addSection(_ text: String) {
        let header = TextBlock()
        header.text = text.uppercased()
        header.foreground = SolidColorBrush(UWP.Color(a: 255, r: 140, g: 140, b: 140))
        header.margin = WinUI.Thickness(left: 0, top: 8, right: 0, bottom: 0)
        root.children.append(header)
    }

    private func addModelControls() {
        let label = TextBlock()
        label.text = "No model loaded"
        root.children.append(label)
        modelLabel = label

        let openBtn = Button()
        openBtn.content = "Open Model…"
        openBtn.click.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.openModelFromDialog() }
        }
        root.children.append(openBtn)

        let animCaption = TextBlock()
        animCaption.text = "Animation"
        animCaption.visibility = .collapsed
        root.children.append(animCaption)
        animHeader = animCaption

        let animSelector = ComboBox()
        animSelector.visibility = .collapsed
        animSelector.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingAnimations else { return }
                let idx = Int(animSelector.selectedIndex)
                guard idx >= 0 else { return }
                self.host.selectAnimation(at: idx)
            }
        }
        root.children.append(animSelector)
        animCombo = animSelector
    }

    /// Updates the model name label and animation selector to match the currently loaded model.
    func syncModelAndAnimations() {
        modelLabel?.text = host.currentModelName ?? "No model loaded"

        guard let animCombo, let animHeader, let model = host.model else { return }
        isSyncingAnimations = true
        defer { isSyncingAnimations = false }

        animCombo.items.clear()
        if model.hasAnimations {
            for clip in model.animations {
                let item = ComboBoxItem()
                item.content = String(format: "%@ (%.1fs)", clip.name, clip.duration)
                animCombo.items.append(item)
            }
            animCombo.selectedIndex = Int32(model.activeAnimationIndex ?? 0)
            animHeader.visibility = .visible
            animCombo.visibility = .visible
        } else {
            animHeader.visibility = .collapsed
            animCombo.visibility = .collapsed
        }
    }

    private func addToneMappingCombo() {
        let combo = ComboBox()
        for mapping in FilamentToneMapping.allCases {
            let item = ComboBoxItem()
            item.content = mapping.displayName
            combo.items.append(item)
        }
        if let index = FilamentToneMapping.allCases.firstIndex(of: host.pbrSettings().toneMapping) {
            combo.selectedIndex = Int32(index)
        }
        combo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                let index = Int(combo.selectedIndex)
                let options = FilamentToneMapping.allCases
                guard index >= 0, index < options.count else { return }
                self?.host.mutatePBR { $0.toneMapping = options[index] }
            }
        }
        root.children.append(combo)
        self.combo = combo
    }

    private func addAntiAliasingCombo() {
        let combo = ComboBox()
        for aa in FilamentAntiAliasing.allCases {
            let item = ComboBoxItem()
            item.content = aa.displayName
            combo.items.append(item)
        }
        if let index = FilamentAntiAliasing.allCases.firstIndex(of: host.pbrSettings().antiAliasing) {
            combo.selectedIndex = Int32(index)
        }
        combo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                let index = Int(combo.selectedIndex)
                let options = FilamentAntiAliasing.allCases
                guard index >= 0, index < options.count else { return }
                self?.host.mutatePBR { $0.antiAliasing = options[index] }
            }
        }
        root.children.append(combo)
        self.antiAliasingCombo = combo
    }

    private func addSlider(_ keyPath: WritableKeyPath<FilamentPBRSettings, Float>,
                           _ label: String,
                           _ min: Double, _ max: Double,
                           step: Double = 1.0) {
        let caption = TextBlock()
        caption.text = label
        root.children.append(caption)

        let slider = Slider()
        slider.minimum = min
        slider.maximum = max
        slider.stepFrequency = step
        slider.value = Double(host.pbrSettings()[keyPath: keyPath])

        slider.valueChanged.addHandler { [weak self] _, args in
            MainActor.assumeIsolated {
                guard let self, let args else { return }
                let newValue = args.newValue
                self.host.mutatePBR { $0[keyPath: keyPath] = Float(newValue) }
            }
        }

        root.children.append(slider)
        sliders.append(SliderBinding(keyPath: keyPath, slider: slider))
    }

    private func addToggle(_ keyPath: WritableKeyPath<FilamentPBRSettings, Bool>, _ label: String) {
        let check = CheckBox()
        check.content = label
        check.isChecked = host.pbrSettings()[keyPath: keyPath]

        check.checked.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.mutatePBR { $0[keyPath: keyPath] = true } }
        }
        check.unchecked.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.mutatePBR { $0[keyPath: keyPath] = false } }
        }

        root.children.append(check)
        toggles.append(ToggleBinding(keyPath: keyPath, check: check))
    }

    private func addStylizedSection() {
        addSection("Stylized Shading & Ink")

        let combo = ComboBox()
        for mode in DemoHost.ShadingMode.allCases {
            let item = ComboBoxItem()
            item.content = mode.title
            combo.items.append(item)
        }
        combo.selectedIndex = Int32(host.currentShadingMode.rawValue)
        combo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingStylized else { return }
                let idx = Int(combo.selectedIndex)
                guard idx >= 0, idx < DemoHost.ShadingMode.allCases.count else { return }
                self.host.setShadingMode(DemoHost.ShadingMode.allCases[idx])
            }
        }
        root.children.append(combo)
        self.shadingCombo = combo

        // Inked Outlines
        addSection("Inked Outline")

        outlineThicknessSlider = addFloatSlider("Outline thickness", min: 0.001, max: 0.05, step: 0.001, initial: Double(host.outlineMaterial?.outlineThickness ?? 0.015)) { [weak self] val in
            self?.host.setOutlineThickness(Float(val))
        }

        let gradCombo = ComboBox()
        for mode in FilamentToonOutlineMaterial.GradientMode.allCases {
            let item = ComboBoxItem()
            item.content = mode.title
            gradCombo.items.append(item)
        }
        gradCombo.selectedIndex = Int32(host.outlineMaterial?.gradientMode.rawValue ?? 0)
        gradCombo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingStylized else { return }
                let idx = Int(gradCombo.selectedIndex)
                guard idx >= 0, idx < FilamentToonOutlineMaterial.GradientMode.allCases.count else { return }
                self.host.setOutlineGradientMode(FilamentToonOutlineMaterial.GradientMode.allCases[idx])
            }
        }
        root.children.append(gradCombo)
        self.outlineGradientCombo = gradCombo

        outlineFlowSpeedSlider = addFloatSlider("Flow animation speed", min: 0.0, max: 5.0, step: 0.1, initial: Double(host.outlineMaterial?.flowAnimationSpeed ?? 0.0)) { [weak self] val in
            self?.host.setOutlineFlowSpeed(Float(val))
        }

        outlineGradientScaleSlider = addFloatSlider("Gradient frequency", min: 0.1, max: 10.0, step: 0.1, initial: Double(host.outlineMaterial?.gradientScale ?? 1.0)) { [weak self] val in
            self?.host.setOutlineGradientScale(Float(val))
        }

        outlineNoiseScaleSlider = addFloatSlider("Noise distortion", min: 0.1, max: 20.0, step: 0.5, initial: Double(host.outlineMaterial?.noiseScale ?? 0.0)) { [weak self] val in
            self?.host.setOutlineNoiseScale(Float(val))
        }

        let randBtn = Button()
        randBtn.content = "Randomize Outline Colors"
        randBtn.click.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated { self?.host.randomizeOutlineColors() }
        }
        root.children.append(randBtn)

        // Halftone Section
        addSection("Comic Halftone & Screentone")

        let presetCombo = ComboBox()
        let presets = ["Custom", "Spider-Verse Pop-Art", "Manga Screentone", "Vintage CMYK Newspaper", "Woodcut / Pen Hatching"]
        for p in presets {
            let item = ComboBoxItem()
            item.content = p
            presetCombo.items.append(item)
        }
        presetCombo.selectedIndex = 0
        presetCombo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingStylized else { return }
                switch presetCombo.selectedIndex {
                case 1: self.host.applyHalftonePreset(FilamentToonMaterial.spiderVersePreset)
                case 2: self.host.applyHalftonePreset(FilamentToonMaterial.mangaScreentonePreset)
                case 3: self.host.applyHalftonePreset(FilamentToonMaterial.cmykNewspaperPreset)
                case 4: self.host.applyHalftonePreset(FilamentToonMaterial.comicHatchingPreset)
                default: break
                }
                self.syncStylizedUI()
            }
        }
        root.children.append(presetCombo)
        self.halftonePresetCombo = presetCombo

        let modeCombo = ComboBox()
        for mode in FilamentToonMaterial.HalftoneMode.allCases {
            let item = ComboBoxItem()
            item.content = mode.title
            modeCombo.items.append(item)
        }
        modeCombo.selectedIndex = Int32(host.toonMaterial?.halftoneMode.rawValue ?? 0)
        modeCombo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingStylized else { return }
                let idx = Int(modeCombo.selectedIndex)
                guard idx >= 0, idx < FilamentToonMaterial.HalftoneMode.allCases.count else { return }
                self.host.setHalftoneMode(FilamentToonMaterial.HalftoneMode.allCases[idx])
            }
        }
        root.children.append(modeCombo)
        self.halftoneModeCombo = modeCombo

        let targetCombo = ComboBox()
        for target in FilamentToonMaterial.HalftoneTarget.allCases {
            let item = ComboBoxItem()
            item.content = target.title
            targetCombo.items.append(item)
        }
        targetCombo.selectedIndex = Int32(host.toonMaterial?.halftoneTarget.rawValue ?? 0)
        targetCombo.selectionChanged.addHandler { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingStylized else { return }
                let idx = Int(targetCombo.selectedIndex)
                guard idx >= 0, idx < FilamentToonMaterial.HalftoneTarget.allCases.count else { return }
                self.host.setHalftoneTarget(FilamentToonMaterial.HalftoneTarget.allCases[idx])
            }
        }
        root.children.append(targetCombo)
        self.halftoneTargetCombo = targetCombo

        halftoneScaleSlider = addFloatSlider("Dot frequency scale", min: 2.0, max: 120.0, step: 1.0, initial: Double(host.toonMaterial?.halftoneScale ?? 24.0)) { [weak self] val in
            self?.host.setHalftoneScale(Float(val))
        }

        halftoneAngleSlider = addFloatSlider("Screen angle (°)", min: 0.0, max: 180.0, step: 1.0, initial: Double(host.toonMaterial?.halftoneAngle ?? 45.0)) { [weak self] val in
            self?.host.setHalftoneAngle(Float(val))
        }

        halftoneDotSizeSlider = addFloatSlider("Dot radius", min: 0.1, max: 2.0, step: 0.05, initial: Double(host.toonMaterial?.halftoneDotSize ?? 1.0)) { [weak self] val in
            self?.host.setHalftoneDotSize(Float(val))
        }

        halftoneHardnessSlider = addFloatSlider("Edge hardness", min: 0.0, max: 1.0, step: 0.01, initial: Double(host.toonMaterial?.halftoneHardness ?? 0.85)) { [weak self] val in
            self?.host.setHalftoneHardness(Float(val))
        }

        halftoneBlendSlider = addFloatSlider("Effect blend", min: 0.0, max: 1.0, step: 0.01, initial: Double(host.toonMaterial?.halftoneBlend ?? 1.0)) { [weak self] val in
            self?.host.setHalftoneBlend(Float(val))
        }
    }

    @discardableResult
    private func addFloatSlider(_ label: String, min: Double, max: Double, step: Double, initial: Double, onChange: @escaping (Double) -> Void) -> Slider {
        let caption = TextBlock()
        caption.text = label
        root.children.append(caption)

        let slider = Slider()
        slider.minimum = min
        slider.maximum = max
        slider.stepFrequency = step
        slider.value = initial

        slider.valueChanged.addHandler { [weak self] _, args in
            MainActor.assumeIsolated {
                guard let self, !self.isSyncingStylized, let args else { return }
                onChange(args.newValue)
            }
        }
        root.children.append(slider)
        return slider
    }

    /// Pushes the host's current settings back into the widgets (after a reset).
    func syncFromSettings() {
        let settings = host.pbrSettings()
        for binding in sliders {
            binding.slider.value = Double(settings[keyPath: binding.keyPath])
        }
        for binding in toggles {
            binding.check.isChecked = settings[keyPath: binding.keyPath]
        }
        if let combo,
           let index = FilamentToneMapping.allCases.firstIndex(of: settings.toneMapping) {
            combo.selectedIndex = Int32(index)
        }
        if let antiAliasingCombo,
           let index = FilamentAntiAliasing.allCases.firstIndex(of: settings.antiAliasing) {
            antiAliasingCombo.selectedIndex = Int32(index)
        }
        syncBackgroundUI()
        syncAutoOrbit()
        syncStylizedUI()
    }

    func syncStylizedUI() {
        isSyncingStylized = true
        defer { isSyncingStylized = false }

        if let shadingCombo {
            shadingCombo.selectedIndex = Int32(host.currentShadingMode.rawValue)
        }
        if let outline = host.outlineMaterial {
            outlineGradientCombo?.selectedIndex = Int32(outline.gradientMode.rawValue)
            outlineThicknessSlider?.value = Double(outline.outlineThickness)
            outlineFlowSpeedSlider?.value = Double(outline.flowAnimationSpeed)
            outlineGradientScaleSlider?.value = Double(outline.gradientScale)
            outlineNoiseScaleSlider?.value = Double(outline.noiseScale)
        }
        if let toon = host.toonMaterial {
            halftoneModeCombo?.selectedIndex = Int32(toon.halftoneMode.rawValue)
            halftoneTargetCombo?.selectedIndex = Int32(toon.halftoneTarget.rawValue)
            halftoneScaleSlider?.value = Double(toon.halftoneScale)
            halftoneAngleSlider?.value = Double(toon.halftoneAngle)
            halftoneDotSizeSlider?.value = Double(toon.halftoneDotSize)
            halftoneHardnessSlider?.value = Double(toon.halftoneHardness)
            halftoneBlendSlider?.value = Double(toon.halftoneBlend)
        }
    }

    func syncBackgroundUI() {
        isSyncingBackground = true
        defer { isSyncingBackground = false }

        if let studioPresetCombo {
            studioPresetCombo.selectedIndex = Int32(StudioPreset.allCases.firstIndex(of: host.currentStudioPreset) ?? 0)
        }
    }

    func syncAutoOrbit() {
        autoOrbitToggle?.isChecked = host.camera.isAutoOrbiting
    }

    private struct SliderBinding {
        let keyPath: WritableKeyPath<FilamentPBRSettings, Float>
        let slider: Slider
    }

    private struct ToggleBinding {
        let keyPath: WritableKeyPath<FilamentPBRSettings, Bool>
        let check: CheckBox
    }
}