import AppKit
import Filament

/// A flipped document view so Auto Layout content starts at the top of a scroll view.
private final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
}

/// Builds and synchronizes the right-hand AppKit inspector panel for PBR settings,
/// model navigation, animation selection, and scene actions.
@MainActor
final class InspectorView: NSObject {
    static let panelWidth: CGFloat = 330

    private let scene: DemoSceneController
    private let onOpenModelRequested: () -> Void
    private let onToggleTransparencyRequested: () -> Bool

    private var inspectorBackdrop: NSVisualEffectView!
    private var modelLabel: NSTextField!
    private var modelPopup: NSPopUpButton!
    private var discoveredModels: [ModelAsset] = []
    private var animationContainer: NSStackView!
    private var animationPopup: NSPopUpButton!
    private var playPauseAnimButton: NSButton!
    private var morphTargetsSection: NSStackView!
    private var morphTargetsHeader: NSTextField!
    private var morphTargetsList: NSStackView!
    private var morphSearchField: NSSearchField?
    private var statusBadge: NSTextField!
    private var transparencyLabel: NSTextField!

    private var sliderBindings: [SliderBinding] = []
    private var toggleBindings: [ToggleBinding] = []
    private var popupBindings: [PopupBinding] = []
    private var morphBindings: [MorphBinding] = []

    private struct MorphBinding {
        let id: Int
        let name: String
        let rowView: NSView
        let slider: NSSlider
        let valueLabel: NSTextField
    }

    private struct SliderBinding {
        let key: String
        let slider: NSSlider
        let valueLabel: NSTextField
        let range: ClosedRange<Double>
        let format: (Double) -> String
        let apply: (Double) -> Void
    }

    private struct ToggleBinding {
        let key: String
        let button: NSButton
        let apply: (Bool) -> Void
    }

    private struct PopupBinding {
        let key: String
        let popup: NSPopUpButton
        let apply: (Int) -> Void
    }

    init(
        scene: DemoSceneController,
        in contentView: NSView,
        onOpenModelRequested: @escaping () -> Void,
        onToggleTransparencyRequested: @escaping () -> Bool
    ) {
        self.scene = scene
        self.onOpenModelRequested = onOpenModelRequested
        self.onToggleTransparencyRequested = onToggleTransparencyRequested
        super.init()
        build(in: contentView)
    }

    // MARK: - Construction

    private func build(in contentView: NSView) {
        let inspectorWidth = Self.panelWidth

        inspectorBackdrop = NSVisualEffectView()
        inspectorBackdrop.translatesAutoresizingMaskIntoConstraints = false
        inspectorBackdrop.material = .sidebar
        inspectorBackdrop.blendingMode = .withinWindow
        inspectorBackdrop.state = .active
        inspectorBackdrop.wantsLayer = true
        inspectorBackdrop.layer?.cornerRadius = 12.0
        inspectorBackdrop.layer?.masksToBounds = true
        contentView.addSubview(inspectorBackdrop)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView, positioned: .above, relativeTo: inspectorBackdrop)

        let container = FlippedContainer(frame: NSRect(x: 0, y: 0, width: inspectorWidth, height: 10))
        container.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = container

        NSLayoutConstraint.activate([
            inspectorBackdrop.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            inspectorBackdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
            inspectorBackdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            inspectorBackdrop.widthAnchor.constraint(equalToConstant: inspectorWidth),

            scrollView.topAnchor.constraint(equalTo: inspectorBackdrop.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: inspectorBackdrop.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: inspectorBackdrop.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: inspectorBackdrop.trailingAnchor),
        ])

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 6.0
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            content.widthAnchor.constraint(equalToConstant: inspectorWidth - 32),
        ])

        addHeader(to: content)
        addModelSection(to: content)
        addToonShadingSection(to: content)
        addMorphTargetsSection(to: content)
        addLightingSection(to: content)
        addToneMappingSection(to: content)
        addAntiAliasingSection(to: content)
        addEffectsSection(to: content)
        addSceneSection(to: content)

        syncControlsFromSettings()
    }

    private func addHeader(to stack: NSStackView) {
        let title = NSTextField(labelWithString: "Filament Swift")
        title.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "AppKit · Metal · glTF PBR")
        subtitle.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        let hint = NSTextField(labelWithString: "Drag: Orbit | Right/Shift-Drag: Pan | Scroll: Zoom")
        hint.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        hint.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(hint)
    }

    private func addModelSection(to stack: NSStackView) {
        stack.addArrangedSubview(makeSectionHeader("Model"))

        let modelRow = NSStackView()
        modelRow.translatesAutoresizingMaskIntoConstraints = false
        modelRow.orientation = .horizontal
        modelRow.alignment = .centerY
        modelRow.spacing = 8.0

        modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        modelPopup.target = self
        modelPopup.action = #selector(onModelPopupChanged(_:))
        modelPopup.controlSize = .small
        modelPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        modelRow.addArrangedSubview(modelPopup)

        let openButton = makeButton("Open…", action: #selector(openModelClicked))
        modelRow.addArrangedSubview(openButton)
        stack.addArrangedSubview(modelRow)

        modelLabel = NSTextField(labelWithString: "No model loaded")
        modelLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        modelLabel.textColor = .systemCyan
        modelLabel.lineBreakMode = .byTruncatingMiddle
        stack.addArrangedSubview(modelLabel)

        animationContainer = NSStackView()
        animationContainer.orientation = .horizontal
        animationContainer.alignment = .centerY
        animationContainer.spacing = 8.0
        animationContainer.isHidden = true

        animationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        animationPopup.target = self
        animationPopup.action = #selector(onAnimationPopupChanged(_:))
        animationPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        animationContainer.addArrangedSubview(animationPopup)

        playPauseAnimButton = makeButton("⏸", action: #selector(toggleAnimationPlayClicked))
        animationContainer.addArrangedSubview(playPauseAnimButton)
        stack.addArrangedSubview(animationContainer)

        NSLayoutConstraint.activate([
            modelRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modelLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            animationContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func addToonShadingSection(to stack: NSStackView) {
        stack.addArrangedSubview(makeSectionHeader("Cartoon Cel Shader"))

        addPopup(to: stack, title: "Style",
                 items: DemoSceneController.ShadingMode.allCases.map(\.title),
                 selected: scene.currentShadingMode.rawValue) { [weak self] index in
            guard let mode = DemoSceneController.ShadingMode(rawValue: index) else { return }
            self?.scene.setShadingMode(mode)
        }

        addPopup(to: stack, title: "Cel color",
                 items: ["Cartoon White (Furu)", "Warm Peach", "Classic Gray", "Jerry Brown", "Anime Sky Blue"],
                 selected: 0) { [weak self] index in
            switch index {
            case 0: self?.scene.setToonBaseColor(r: 0.96, g: 0.95, b: 0.94)
            case 1: self?.scene.setToonBaseColor(r: 0.95, g: 0.70, b: 0.50)
            case 2: self?.scene.setToonBaseColor(r: 0.65, g: 0.70, b: 0.75)
            case 3: self?.scene.setToonBaseColor(r: 0.75, g: 0.55, b: 0.35)
            case 4: self?.scene.setToonBaseColor(r: 0.40, g: 0.70, b: 0.95)
            default: break
            }
        }

        addSlider(to: stack, title: "Shadow band", range: -0.5...0.8,
                  value: 0.05,
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setToonShadowThreshold(Float(val))
        }

        addSlider(to: stack, title: "Highlight band", range: 0.2...1.0,
                  value: 0.75,
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setToonHighlightThreshold(Float(val))
        }

        addSlider(to: stack, title: "Edge feather", range: 0.001...0.1,
                  value: 0.015,
                  format: { String(format: "%.3f", $0) }) { [weak self] val in
            self?.scene.setToonEdgeFeather(Float(val))
        }

        addSlider(to: stack, title: "Outline width", range: 0.5...8.0,
                  value: 2.5,
                  format: { String(format: "%.1f px", $0) }) { [weak self] val in
            self?.scene.setOutlineThickness(Float(val))
        }
    }

    private func addMorphTargetsSection(to stack: NSStackView) {
        morphTargetsSection = NSStackView()
        morphTargetsSection.translatesAutoresizingMaskIntoConstraints = false
        morphTargetsSection.orientation = .vertical
        morphTargetsSection.alignment = .leading
        morphTargetsSection.spacing = 6.0

        morphTargetsHeader = makeSectionHeader("Morph Targets")
        morphTargetsSection.addArrangedSubview(morphTargetsHeader)

        morphTargetsList = NSStackView()
        morphTargetsList.translatesAutoresizingMaskIntoConstraints = false
        morphTargetsList.orientation = .vertical
        morphTargetsList.alignment = .leading
        morphTargetsList.spacing = 6.0
        morphTargetsSection.addArrangedSubview(morphTargetsList)

        stack.addArrangedSubview(morphTargetsSection)

        NSLayoutConstraint.activate([
            morphTargetsSection.widthAnchor.constraint(equalTo: stack.widthAnchor),
            morphTargetsList.widthAnchor.constraint(equalTo: morphTargetsSection.widthAnchor),
        ])
    }

    private func addLightingSection(to stack: NSStackView) {
        let pbr = scene.pbr
        stack.addArrangedSubview(makeSectionHeader("Lighting"))

        addSlider(to: stack, title: "Key light",
                  range: 0...200_000, value: Double(pbr.settings.keyLightIntensity),
                  format: { String(format: "%.0f lx", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.keyLightIntensity = Float(value) }
        }

        addSlider(to: stack, title: "Fill light",
                  range: 0...200_000, value: Double(pbr.settings.fillLightIntensity),
                  format: { String(format: "%.0f lx", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.fillLightIntensity = Float(value) }
        }

        addSlider(to: stack, title: "Ambient",
                  range: 0...100_000, value: Double(pbr.settings.ambientIntensity),
                  format: { String(format: "%.0f lx", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.ambientIntensity = Float(value) }
        }

        addSlider(to: stack, title: "Light angle", range: 0...360, value: 0,
                  format: { String(format: "%.0f°", $0) }) { [weak self] value in
            let radians = value * .pi / 180.0
            self?.scene.pbr.setKeyLightDirection((Float(cos(radians)), -1.0, Float(sin(radians))))
        }

        addToggle(to: stack, title: "Shadows", isOn: pbr.settings.shadowsEnabled) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.shadowsEnabled = isOn }
        }
    }

    private func addToneMappingSection(to stack: NSStackView) {
        let pbr = scene.pbr
        stack.addArrangedSubview(makeSectionHeader("Tone Mapping"))

        addPopup(to: stack, title: "Operator",
                 items: FilamentToneMapping.allCases.map(\.displayName),
                 selected: FilamentToneMapping.allCases.firstIndex(of: pbr.settings.toneMapping) ?? 2) { [weak self] index in
            let mapping = FilamentToneMapping.allCases[index]
            self?.scene.pbr.mutate { $0.toneMapping = mapping }
        }

        addSlider(to: stack, title: "Exposure", range: 0.1...4.0, value: Double(pbr.settings.exposure),
                  format: { String(format: "%.2f×", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.exposure = Float(value) }
        }

        addSlider(to: stack, title: "Contrast", range: 0...2, value: Double(pbr.settings.contrast),
                  format: { String(format: "%.2f", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.contrast = Float(value) }
        }

        addSlider(to: stack, title: "Saturation", range: 0...2, value: Double(pbr.settings.saturation),
                  format: { String(format: "%.2f", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.saturation = Float(value) }
        }

        addSlider(to: stack, title: "Vibrance", range: 0...2, value: Double(pbr.settings.vibrance),
                  format: { String(format: "%.2f", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.vibrance = Float(value) }
        }

        addSlider(to: stack, title: "White balance", range: -1...1,
                  value: Double(pbr.settings.whiteBalance),
                  format: { String(format: "%+.2f", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.whiteBalance = Float(value) }
        }
    }

    private func addAntiAliasingSection(to stack: NSStackView) {
        let pbr = scene.pbr
        stack.addArrangedSubview(makeSectionHeader("Anti-Aliasing"))

        addPopup(to: stack, title: "Post AA",
                 items: FilamentAntiAliasing.allCases.map(\.displayName),
                 selected: FilamentAntiAliasing.allCases.firstIndex(of: pbr.settings.antiAliasing) ?? 1) { [weak self] index in
            self?.scene.pbr.mutate { $0.antiAliasing = FilamentAntiAliasing.allCases[index] }
        }

        addPopup(to: stack, title: "MSAA", items: ["1", "2", "4", "8"],
                 selected: max(0, [1, 2, 4, 8].firstIndex(of: pbr.settings.multiSampleCount) ?? 0)) { [weak self] index in
            self?.scene.pbr.mutate { $0.multiSampleCount = [1, 2, 4, 8][index] }
        }

        addPopup(to: stack, title: "HDR buffer",
                 items: FilamentHDRQuality.allCases.map(\.displayName),
                 selected: FilamentHDRQuality.allCases.firstIndex(of: pbr.settings.hdrQuality) ?? 2) { [weak self] index in
            self?.scene.pbr.mutate { $0.hdrQuality = FilamentHDRQuality.allCases[index] }
        }

        addToggle(to: stack, title: "Dithering", isOn: pbr.settings.dithering) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.dithering = isOn }
        }
    }

    private func addEffectsSection(to stack: NSStackView) {
        let pbr = scene.pbr
        stack.addArrangedSubview(makeSectionHeader("Screen-Space Effects"))

        addToggle(to: stack, title: "Bloom", isOn: pbr.settings.bloomEnabled) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.bloomEnabled = isOn }
        }
        addSlider(to: stack, title: "Bloom strength", range: 0...1, value: Double(pbr.settings.bloomStrength),
                  format: { String(format: "%.2f", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.bloomStrength = Float(value) }
        }

        addToggle(to: stack, title: "Vignette", isOn: pbr.settings.vignetteEnabled) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.vignetteEnabled = isOn }
        }
        addSlider(to: stack, title: "Vignette strength", range: 0...1, value: Double(pbr.settings.vignetteStrength),
                  format: { String(format: "%.2f", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.vignetteStrength = Float(value) }
        }

        addToggle(to: stack, title: "Ambient occlusion", isOn: pbr.settings.occlusionEnabled) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.occlusionEnabled = isOn }
        }
        addPopup(to: stack, title: "Occlusion type",
                 items: FilamentOcclusionMode.allCases.map(\.displayName),
                 selected: FilamentOcclusionMode.allCases.firstIndex(of: pbr.settings.occlusionMode) ?? 0) { [weak self] index in
            self?.scene.pbr.mutate { $0.occlusionMode = FilamentOcclusionMode.allCases[index] }
        }
        addSlider(to: stack, title: "Occlusion radius", range: 0...3, value: Double(pbr.settings.occlusionRadius),
                  format: { String(format: "%.2f m", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.occlusionRadius = Float(value) }
        }

        addToggle(to: stack, title: "Reflections (SSR)", isOn: pbr.settings.reflectionsEnabled) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.reflectionsEnabled = isOn }
        }
        addSlider(to: stack, title: "Reflection distance", range: 0...10,
                  value: Double(pbr.settings.reflectionMaxDistance),
                  format: { String(format: "%.1f m", $0) }) { [weak self] value in
            self?.scene.pbr.mutate { $0.reflectionMaxDistance = Float(value) }
        }

        addToggle(to: stack, title: "Depth of field", isOn: pbr.settings.depthOfFieldEnabled) { [weak self] isOn in
            self?.scene.pbr.mutate { $0.depthOfFieldEnabled = isOn }
        }
    }

    private func addSceneSection(to stack: NSStackView) {
        stack.addArrangedSubview(makeSectionHeader("Scene"))

        let resetButton = makeButton("Reset PBR Settings", action: #selector(resetPBRClicked))
        stack.addArrangedSubview(resetButton)

        let orbitButton = makeButton("Toggle Orbit", action: #selector(toggleOrbitClicked))
        stack.addArrangedSubview(orbitButton)

        let resetCamButton = makeButton("Reset View", action: #selector(resetCameraClicked))
        stack.addArrangedSubview(resetCamButton)

        let transparencyButton = makeButton("Toggle Alpha", action: #selector(toggleTransparencyClicked))
        stack.addArrangedSubview(transparencyButton)

        transparencyLabel = NSTextField(labelWithString: "Alpha Transparency: Disabled")
        transparencyLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        transparencyLabel.textColor = .systemBlue
        stack.addArrangedSubview(transparencyLabel)

        statusBadge = NSTextField(labelWithString: "● Rendering | Orbit: ON")
        statusBadge.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        statusBadge.textColor = .systemGreen
        stack.addArrangedSubview(statusBadge)
    }

    // MARK: - Widget factories

    private func makeSectionHeader(_ title: String) -> NSTextField {
        let header = NSTextField(labelWithString: title.uppercased())
        header.font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        header.textColor = .tertiaryLabelColor
        return header
    }

    private func makeButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .small
        return button
    }

    private func addSlider(
        to stack: NSStackView,
        title: String,
        range: ClosedRange<Double>,
        value: Double,
        format: @escaping (Double) -> String,
        onChange: @escaping (Double) -> Void
    ) {
        let valueLabel = NSTextField(labelWithString: format(value))
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right

        let slider = NSSlider(
            value: min(max(value, range.lowerBound), range.upperBound),
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: self,
            action: #selector(sliderChanged(_:))
        )
        slider.controlSize = .small
        slider.isContinuous = true

        let row = NSStackView(views: [
            NSTextField(labelWithString: title),
            valueLabel
        ])
        row.orientation = .horizontal
        row.distribution = .fill
        stack.addArrangedSubview(row)
        stack.addArrangedSubview(slider)

        sliderBindings.append(SliderBinding(
            key: title,
            slider: slider,
            valueLabel: valueLabel,
            range: range,
            format: format,
            apply: onChange
        ))
    }

    private func addToggle(
        to stack: NSStackView,
        title: String,
        isOn: Bool,
        onChange: @escaping (Bool) -> Void
    ) {
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(toggleChanged(_:)))
        button.state = isOn ? .on : .off
        button.controlSize = .small
        stack.addArrangedSubview(button)
        toggleBindings.append(ToggleBinding(key: title, button: button, apply: onChange))
    }

    private func addPopup(
        to stack: NSStackView,
        title: String,
        items: [String],
        selected: Int,
        onChange: @escaping (Int) -> Void
    ) {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        popup.selectItem(at: min(max(selected, 0), max(0, items.count - 1)))
        popup.target = self
        popup.action = #selector(popupChanged(_:))
        popup.controlSize = .small

        let row = NSStackView(views: [NSTextField(labelWithString: title), popup])
        row.orientation = .horizontal
        row.distribution = .fill
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(row)

        popupBindings.append(PopupBinding(key: title, popup: popup, apply: onChange))
    }

    // MARK: - Synchronization

    func syncModelUI() {
        let currentName = scene.currentModelName ?? "No model loaded"
        modelLabel.stringValue = currentName

        discoveredModels = ModelDiscovery.discoverModels()
        modelPopup.removeAllItems()
        for m in discoveredModels {
            modelPopup.addItem(withTitle: m.name)
        }
        if let current = scene.currentModelName, let idx = discoveredModels.firstIndex(where: { $0.name == current }) {
            modelPopup.selectItem(at: idx)
        } else if let current = scene.currentModelName {
            modelPopup.addItem(withTitle: current)
            modelPopup.selectItem(at: modelPopup.numberOfItems - 1)
        }

        if scene.model.hasAnimations {
            animationContainer.isHidden = false
            animationPopup.removeAllItems()
            for anim in scene.model.animations {
                let durationStr = String(format: "%.1f", anim.duration)
                animationPopup.addItem(withTitle: "\(anim.name) (\(durationStr)s)")
            }
            animationPopup.selectItem(at: 0)
            playPauseAnimButton.title = scene.isAnimationPlaying ? "⏸" : "▶"
        } else {
            animationContainer.isHidden = true
            animationPopup.removeAllItems()
        }

        syncMorphTargetsUI()
        syncShadingMode()
    }

    func syncShadingMode() {
        for binding in popupBindings where binding.key == "Style" {
            binding.popup.selectItem(at: scene.currentShadingMode.rawValue)
        }
    }

    func syncMorphTargetsUI() {
        morphBindings.removeAll()
        morphSearchField = nil

        for view in morphTargetsList.arrangedSubviews {
            morphTargetsList.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let targets = scene.model.morphTargets
        if targets.isEmpty {
            morphTargetsHeader.stringValue = "MORPH TARGETS"
            let emptyLabel = NSTextField(labelWithString: "No morph targets in current model")
            emptyLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
            emptyLabel.textColor = .secondaryLabelColor
            morphTargetsList.addArrangedSubview(emptyLabel)
            return
        }

        morphTargetsHeader.stringValue = "MORPH TARGETS (\(targets.count))"

        let actionBar = NSStackView()
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        actionBar.orientation = .horizontal
        actionBar.alignment = .centerY
        actionBar.spacing = 8.0

        let resetButton = makeButton("Reset All", action: #selector(resetAllMorphTargetsClicked))
        actionBar.addArrangedSubview(resetButton)

        if targets.count > 4 {
            let search = NSSearchField()
            search.translatesAutoresizingMaskIntoConstraints = false
            search.placeholderString = "Filter morph targets…"
            search.controlSize = .small
            search.target = self
            search.action = #selector(onMorphSearchChanged(_:))
            search.setContentHuggingPriority(.defaultLow, for: .horizontal)
            actionBar.addArrangedSubview(search)
            morphSearchField = search
        }

        morphTargetsList.addArrangedSubview(actionBar)
        NSLayoutConstraint.activate([
            actionBar.widthAnchor.constraint(equalTo: morphTargetsList.widthAnchor)
        ])

        for target in targets {
            let rowContainer = NSStackView()
            rowContainer.translatesAutoresizingMaskIntoConstraints = false
            rowContainer.orientation = .vertical
            rowContainer.alignment = .leading
            rowContainer.spacing = 2.0

            let headerRow = NSStackView()
            headerRow.translatesAutoresizingMaskIntoConstraints = false
            headerRow.orientation = .horizontal
            headerRow.distribution = .fill

            let nameLabel = NSTextField(labelWithString: target.name)
            nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            let valueLabel = NSTextField(labelWithString: String(format: "%.2f", target.weight))
            valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            valueLabel.textColor = .secondaryLabelColor
            valueLabel.alignment = .right
            valueLabel.setContentHuggingPriority(.required, for: .horizontal)

            headerRow.addArrangedSubview(nameLabel)
            headerRow.addArrangedSubview(valueLabel)

            let slider = NSSlider(
                value: Double(target.weight),
                minValue: 0.0,
                maxValue: 1.0,
                target: self,
                action: #selector(morphSliderChanged(_:))
            )
            slider.translatesAutoresizingMaskIntoConstraints = false
            slider.controlSize = .small
            slider.isContinuous = true
            slider.tag = target.id

            rowContainer.addArrangedSubview(headerRow)
            rowContainer.addArrangedSubview(slider)

            morphTargetsList.addArrangedSubview(rowContainer)

            NSLayoutConstraint.activate([
                rowContainer.widthAnchor.constraint(equalTo: morphTargetsList.widthAnchor),
                headerRow.widthAnchor.constraint(equalTo: rowContainer.widthAnchor),
                slider.widthAnchor.constraint(equalTo: rowContainer.widthAnchor),
            ])

            morphBindings.append(MorphBinding(
                id: target.id,
                name: target.name,
                rowView: rowContainer,
                slider: slider,
                valueLabel: valueLabel
            ))
        }
    }

    func updateStatusBadge(fps: Double, isOrbiting: Bool) {
        statusBadge.stringValue = String(
            format: "● %.0f FPS | Auto-Orbit: %@",
            min(fps, 999),
            isOrbiting ? "ON" : "OFF"
        )
        statusBadge.textColor = .systemGreen
    }

    func syncControlsFromSettings() {
        let s = scene.pbr.settings

        func sliderValue(_ key: String) -> Double? {
            switch key {
            case "Key light": return Double(s.keyLightIntensity)
            case "Fill light": return Double(s.fillLightIntensity)
            case "Ambient": return Double(s.ambientIntensity)
            case "Exposure": return Double(s.exposure)
            case "Contrast": return Double(s.contrast)
            case "Saturation": return Double(s.saturation)
            case "Vibrance": return Double(s.vibrance)
            case "White balance": return Double(s.whiteBalance)
            case "Bloom strength": return Double(s.bloomStrength)
            case "Vignette strength": return Double(s.vignetteStrength)
            case "Occlusion radius": return Double(s.occlusionRadius)
            case "Reflection distance": return Double(s.reflectionMaxDistance)
            default: return nil
            }
        }

        func toggleValue(_ key: String) -> Bool? {
            switch key {
            case "Shadows": return s.shadowsEnabled
            case "Dithering": return s.dithering
            case "Bloom": return s.bloomEnabled
            case "Vignette": return s.vignetteEnabled
            case "Ambient occlusion": return s.occlusionEnabled
            case "Reflections (SSR)": return s.reflectionsEnabled
            case "Depth of field": return s.depthOfFieldEnabled
            default: return nil
            }
        }

        for binding in sliderBindings {
            guard let value = sliderValue(binding.key) else { continue }
            binding.slider.doubleValue = min(max(value, binding.range.lowerBound), binding.range.upperBound)
            binding.valueLabel.stringValue = binding.format(value)
        }
        for binding in toggleBindings {
            guard let on = toggleValue(binding.key) else { continue }
            binding.button.state = on ? .on : .off
        }

        let popupIndices: [(String, Int)] = [
            ("Operator", FilamentToneMapping.allCases.firstIndex(of: s.toneMapping) ?? 0),
            ("Post AA", FilamentAntiAliasing.allCases.firstIndex(of: s.antiAliasing) ?? 0),
            ("MSAA", [1, 2, 4, 8].firstIndex(of: s.multiSampleCount) ?? 0),
            ("HDR buffer", FilamentHDRQuality.allCases.firstIndex(of: s.hdrQuality) ?? 0),
            ("Occlusion type", FilamentOcclusionMode.allCases.firstIndex(of: s.occlusionMode) ?? 0),
        ]
        for (key, index) in popupIndices {
            for binding in popupBindings where binding.key == key {
                binding.popup.selectItem(at: min(index, max(0, binding.popup.numberOfItems - 1)))
            }
        }
    }

    // MARK: - Actions

    @objc private func sliderChanged(_ sender: NSSlider) {
        guard let binding = sliderBindings.first(where: { $0.slider === sender }) else { return }
        binding.valueLabel.stringValue = binding.format(sender.doubleValue)
        binding.apply(sender.doubleValue)
    }

    @objc private func toggleChanged(_ sender: NSButton) {
        guard let binding = toggleBindings.first(where: { $0.button === sender }) else { return }
        binding.apply(sender.state == .on)
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        guard let binding = popupBindings.first(where: { $0.popup === sender }) else { return }
        binding.apply(sender.indexOfSelectedItem)
    }

    @objc func resetPBRClicked() {
        scene.pbr.reset()
        syncControlsFromSettings()
    }

    @objc private func openModelClicked() {
        onOpenModelRequested()
    }

    @objc private func onAnimationPopupChanged(_ sender: NSPopUpButton) {
        scene.selectAnimation(at: sender.indexOfSelectedItem)
        playPauseAnimButton.title = scene.isAnimationPlaying ? "⏸" : "▶"
    }

    @objc private func toggleAnimationPlayClicked() {
        let playing = scene.toggleAnimationPlayback()
        playPauseAnimButton.title = playing ? "⏸" : "▶"
    }

    @objc func toggleOrbitClicked() {
        _ = scene.toggleAutoOrbit()
    }

    @objc private func toggleTransparencyClicked() {
        let enabled = onToggleTransparencyRequested()
        transparencyLabel.stringValue = enabled
            ? "Alpha Transparency: Enabled"
            : "Alpha Transparency: Disabled"
        transparencyLabel.textColor = enabled ? .systemGreen : .systemBlue
    }

    @objc private func resetCameraClicked() {
        scene.resetCamera()
    }

    @objc private func onModelPopupChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < discoveredModels.count else { return }
        scene.loadModel(from: discoveredModels[idx].url)
    }

    @objc private func morphSliderChanged(_ sender: NSSlider) {
        guard let binding = morphBindings.first(where: { $0.slider === sender }) else { return }
        let weight = Float(sender.doubleValue)
        binding.valueLabel.stringValue = String(format: "%.2f", weight)
        scene.setMorphWeight(at: binding.id, weight: weight)

        let isNamed = !binding.name.hasPrefix("MorphTarget ")
        if isNamed {
            for other in morphBindings where other.name == binding.name && other.slider !== sender {
                other.slider.doubleValue = Double(weight)
                other.valueLabel.stringValue = String(format: "%.2f", weight)
            }
        }
    }

    @objc func resetAllMorphTargetsClicked() {
        scene.resetMorphWeights()
        for binding in morphBindings {
            binding.slider.doubleValue = 0.0
            binding.valueLabel.stringValue = "0.00"
        }
    }

    @objc private func onMorphSearchChanged(_ sender: NSSearchField) {
        let query = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for binding in morphBindings {
            if query.isEmpty {
                binding.rowView.isHidden = false
            } else {
                binding.rowView.isHidden = !binding.name.lowercased().contains(query)
            }
        }
    }
}
