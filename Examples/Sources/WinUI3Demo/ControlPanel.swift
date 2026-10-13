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
    private let scrollViewer = ScrollViewer()
    private let root = StackPanel()

    private var sliders: [SliderBinding] = []
    private var toggles: [ToggleBinding] = []
    private var combo: ComboBox?
    private var antiAliasingCombo: ComboBox?
    private var modelLabel: TextBlock?
    private var animHeader: TextBlock?
    private var animCombo: ComboBox?
    private var isSyncingAnimations = false

    init(host: DemoHost) {
        self.host = host
        build()
    }

    var rootElement: UIElement { scrollViewer }

    // MARK: - Construction

    private func build() {
        root.spacing = 8
        root.padding = WinUI.Thickness(left: 16, top: 16, right: 16, bottom: 16)
        scrollViewer.content = root

        let title = TextBlock()
        title.text = "Filament Swift"
        title.fontSize = 20
        root.children.append(title)

        let subtitle = TextBlock()
        subtitle.text = "WinUI 3 island · Vulkan · glTF PBR"
        root.children.append(subtitle)

        addSection("Model")
        addModelControls()

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

        syncFromSettings()
        syncModelAndAnimations()
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