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
    var onToggleDemoModeRequested: (() -> Void)?

    private var inspectorBackdrop: NSVisualEffectView!
    private var scrollView: NSScrollView!
    private var demoModeButton: NSButton?
    private var demoZoomLabel: NSTextField?
    private var demoZoomSlider: NSSlider?
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
    private var outlineColorWell: NSColorWell?
    private var outlineColorPopup: NSPopUpButton?
    private var overlayButton: NSButton?
    private var overlayLabel: NSTextField?
    private var overlayPassthroughCheckbox: NSButton?

    private var halftoneModePopup: NSPopUpButton?
    private var halftoneTargetPopup: NSPopUpButton?
    private var halftonePresetPopup: NSPopUpButton?
    private var halftoneDotColorPopup: NSPopUpButton?
    private var halftoneDotColorWell: NSColorWell?
    private var halftonePaperColorPopup: NSPopUpButton?
    private var halftonePaperColorWell: NSColorWell?

    private struct HalftoneColorPreset {
        let name: String
        let color: (r: Float, g: Float, b: Float, a: Float)
        var nsColor: NSColor {
            NSColor(srgbRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: CGFloat(color.a))
        }
    }

    private let halftoneInkPresets: [HalftoneColorPreset] = [
        HalftoneColorPreset(name: "Comic Ink Black", color: (0.08, 0.06, 0.05, 1.0)),
        HalftoneColorPreset(name: "Pure Black", color: (0.00, 0.00, 0.00, 1.0)),
        HalftoneColorPreset(name: "Deep Navy Ink", color: (0.05, 0.12, 0.32, 1.0)),
        HalftoneColorPreset(name: "Manga Sepia", color: (0.25, 0.15, 0.10, 1.0)),
        HalftoneColorPreset(name: "Crimson Ink", color: (0.65, 0.08, 0.12, 1.0)),
        HalftoneColorPreset(name: "Neon Cyan", color: (0.00, 0.80, 0.95, 1.0)),
    ]

    private let halftonePaperPresets: [HalftoneColorPreset] = [
        HalftoneColorPreset(name: "Newsprint White", color: (0.98, 0.97, 0.94, 1.0)),
        HalftoneColorPreset(name: "Pure White", color: (1.00, 1.00, 1.00, 1.0)),
        HalftoneColorPreset(name: "Vintage Parchment", color: (0.94, 0.88, 0.78, 1.0)),
        HalftoneColorPreset(name: "Blueprint Tint", color: (0.85, 0.92, 0.98, 1.0)),
        HalftoneColorPreset(name: "Dark Comic Ink", color: (0.15, 0.16, 0.20, 1.0)),
    ]

    private var sketchPresetPopup: NSPopUpButton?
    private var sketchLayersPopup: NSPopUpButton?
    private var sketchInkColorPopup: NSPopUpButton?
    private var sketchInkColorWell: NSColorWell?
    private var sketchPaperColorPopup: NSPopUpButton?
    private var sketchPaperColorWell: NSColorWell?
    private var sketchOutlineStylePopup: NSPopUpButton?

    private let sketchInkPresets: [HalftoneColorPreset] = [
        HalftoneColorPreset(name: "Drafting Graphite", color: (0.12, 0.12, 0.14, 1.0)),
        HalftoneColorPreset(name: "Blueprint Cyan Ink", color: (0.35, 0.82, 1.00, 1.0)),
        HalftoneColorPreset(name: "Soft 2B Pencil", color: (0.16, 0.15, 0.14, 1.0)),
        HalftoneColorPreset(name: "Micron Jet Black", color: (0.02, 0.02, 0.03, 1.0)),
        HalftoneColorPreset(name: "Architectural Sepia", color: (0.30, 0.20, 0.14, 1.0)),
        HalftoneColorPreset(name: "White Chalk", color: (0.95, 0.95, 0.96, 1.0)),
    ]

    private let sketchPaperPresets: [HalftoneColorPreset] = [
        HalftoneColorPreset(name: "Architectural White", color: (1.00, 1.00, 1.00, 1.0)),
        HalftoneColorPreset(name: "Technical Blueprint Navy", color: (0.06, 0.15, 0.28, 1.0)),
        HalftoneColorPreset(name: "Drafting Cream Vellum", color: (0.98, 0.96, 0.92, 1.0)),
        HalftoneColorPreset(name: "Slate Charcoal Board", color: (0.10, 0.11, 0.13, 1.0)),
        HalftoneColorPreset(name: "Transparent Mylar (Zero-Alpha)", color: (1.00, 1.00, 1.00, 0.0)),
    ]

    private var solidColorRow: NSView!
    private var gradientControlsContainer: NSStackView!
    private var gradientStopsList: NSStackView!
    private var addStopButton: NSButton!
    private var gradientPresetPopup: NSPopUpButton!
    private var outlineStylePopup: NSPopUpButton!
    private var currentOutlineGradientMode: FilamentToonOutlineMaterial.GradientMode = .solid
    private var currentGradientStops: [FilamentToonOutlineMaterial.GradientStop] = FilamentToonOutlineMaterial.vibgyorStops

    private struct OutlineColorPreset {
        let name: String
        let color: (r: Float, g: Float, b: Float)
        var nsColor: NSColor {
            NSColor(srgbRed: CGFloat(color.r), green: CGFloat(color.g), blue: CGFloat(color.b), alpha: 1.0)
        }
    }

    private let outlineColorPresets: [OutlineColorPreset] = [
        OutlineColorPreset(name: "Charcoal Ink (Classic)", color: (0.10, 0.08, 0.06)),
        OutlineColorPreset(name: "Pure Black (#000000)", color: (0.00, 0.00, 0.00)),
        OutlineColorPreset(name: "Drafting Sepia", color: (0.28, 0.18, 0.12)),
        OutlineColorPreset(name: "Navy Blueprint", color: (0.08, 0.18, 0.42)),
        OutlineColorPreset(name: "Anime Brown", color: (0.35, 0.20, 0.15)),
        OutlineColorPreset(name: "Crimson Inked", color: (0.70, 0.12, 0.16)),
        OutlineColorPreset(name: "Chalk White", color: (0.95, 0.95, 0.95)),
        OutlineColorPreset(name: "Neon Cyan", color: (0.00, 0.85, 0.95)),
    ]

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

        scrollView = NSScrollView()
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
        addHalftoneSection(to: content)
        addHanddrawnSketchSection(to: content)
        addMorphTargetsSection(to: content)
        addLightingSection(to: content)
        addToneMappingSection(to: content)
        addAntiAliasingSection(to: content)
        addEffectsSection(to: content)
        addSceneSection(to: content)

        syncControlsFromSettings()
    }

    var isHidden: Bool {
        get { inspectorBackdrop.isHidden }
        set {
            inspectorBackdrop.isHidden = newValue
            scrollView.isHidden = newValue
        }
    }

    func setHidden(_ hidden: Bool) {
        self.isHidden = hidden
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

        let demoBtn = NSButton(title: "🎬 Start Demo Reel (Auto-Cycle)", target: self, action: #selector(toggleDemoModeClicked))
        demoBtn.translatesAutoresizingMaskIntoConstraints = false
        demoBtn.bezelStyle = .rounded
        demoBtn.controlSize = .regular
        demoBtn.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        demoBtn.contentTintColor = .systemPurple
        demoModeButton = demoBtn
        stack.addArrangedSubview(demoBtn)
        demoBtn.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        // Demo Framing & Zoom Scale
        let zoomHeaderRow = NSStackView()
        zoomHeaderRow.translatesAutoresizingMaskIntoConstraints = false
        zoomHeaderRow.orientation = .horizontal
        zoomHeaderRow.alignment = .centerY
        zoomHeaderRow.spacing = 6.0

        let zLabel = NSTextField(labelWithString: String(format: "Demo Zoom Scale: %.2fx", scene.demoZoomScale))
        zLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        zLabel.textColor = .secondaryLabelColor
        demoZoomLabel = zLabel
        zoomHeaderRow.addArrangedSubview(zLabel)

        let zoomSpacer = NSView()
        zoomSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        zoomHeaderRow.addArrangedSubview(zoomSpacer)

        let matchBtn = NSButton(title: "🎯 Match Viewport", target: self, action: #selector(onMatchViewportClicked))
        matchBtn.bezelStyle = .inline
        matchBtn.controlSize = .mini
        matchBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        matchBtn.toolTip = "Calibrate demo zoom to frame the model at the current viewport distance"
        zoomHeaderRow.addArrangedSubview(matchBtn)

        let resetZoomBtn = NSButton(title: "1.0x", target: self, action: #selector(onDemoZoomResetClicked))
        resetZoomBtn.bezelStyle = .inline
        resetZoomBtn.controlSize = .mini
        resetZoomBtn.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        resetZoomBtn.toolTip = "Reset demo zoom to 1.0x"
        zoomHeaderRow.addArrangedSubview(resetZoomBtn)

        stack.addArrangedSubview(zoomHeaderRow)
        zoomHeaderRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let zoomControlRow = NSStackView()
        zoomControlRow.translatesAutoresizingMaskIntoConstraints = false
        zoomControlRow.orientation = .horizontal
        zoomControlRow.alignment = .centerY
        zoomControlRow.spacing = 6.0

        let minusBtn = NSButton(title: "−", target: self, action: #selector(onDemoZoomMinusClicked))
        minusBtn.bezelStyle = .roundRect
        minusBtn.controlSize = .small
        minusBtn.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        minusBtn.toolTip = "Zoom Out (- or scroll down)"
        zoomControlRow.addArrangedSubview(minusBtn)

        let slider = NSSlider(value: scene.demoZoomScale, minValue: 0.1, maxValue: 8.0, target: self, action: #selector(onDemoZoomSliderChanged(_:)))
        slider.controlSize = .small
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        demoZoomSlider = slider
        zoomControlRow.addArrangedSubview(slider)

        let plusBtn = NSButton(title: "+", target: self, action: #selector(onDemoZoomPlusClicked))
        plusBtn.bezelStyle = .roundRect
        plusBtn.controlSize = .small
        plusBtn.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        plusBtn.toolTip = "Zoom In (+ or scroll up)"
        zoomControlRow.addArrangedSubview(plusBtn)

        stack.addArrangedSubview(zoomControlRow)
        zoomControlRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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

        addOutlineStyleAndColorSection(to: stack)

        addPopup(to: stack, title: "Canvas",
                 items: DemoSceneController.CanvasBackground.allCases.map(\.title),
                 selected: scene.currentCanvasBackground.rawValue) { [weak self] index in
            guard let bg = DemoSceneController.CanvasBackground(rawValue: index) else { return }
            self?.scene.setCanvasBackground(bg)
        }
    }

    private func addOutlineStyleAndColorSection(to stack: NSStackView) {
        // 1. Outline Style / Pattern Dropdown
        let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in FilamentToonOutlineMaterial.GradientMode.allCases {
            stylePopup.addItem(withTitle: mode.title)
        }
        stylePopup.selectItem(at: 0)
        stylePopup.controlSize = .small
        stylePopup.target = self
        stylePopup.action = #selector(onOutlineStyleChanged(_:))
        stylePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let styleRow = NSStackView(views: [
            NSTextField(labelWithString: "Outline style"),
            stylePopup
        ])
        styleRow.orientation = .horizontal
        styleRow.distribution = .fill
        stack.addArrangedSubview(styleRow)
        self.outlineStylePopup = stylePopup

        // 2. Solid Color Row (Visible when mode == .solid)
        let solidRow = NSStackView()
        solidRow.translatesAutoresizingMaskIntoConstraints = false
        solidRow.orientation = .horizontal
        solidRow.alignment = .centerY
        solidRow.distribution = .fill
        solidRow.spacing = 6.0

        let label = NSTextField(labelWithString: "Outline color")
        label.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        label.setContentHuggingPriority(.required, for: .horizontal)
        solidRow.addArrangedSubview(label)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in outlineColorPresets {
            popup.addItem(withTitle: preset.name)
        }
        popup.addItem(withTitle: "Custom…")
        popup.selectItem(at: 0)
        popup.controlSize = .small
        popup.target = self
        popup.action = #selector(onOutlineColorPopupChanged(_:))
        popup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        solidRow.addArrangedSubview(popup)
        outlineColorPopup = popup

        let well = NSColorWell()
        well.translatesAutoresizingMaskIntoConstraints = false
        well.color = outlineColorPresets[0].nsColor
        well.target = self
        well.action = #selector(onOutlineColorWellChanged(_:))
        well.controlSize = .small
        well.toolTip = "Pick Custom Outline Color"
        NSLayoutConstraint.activate([
            well.widthAnchor.constraint(equalToConstant: 28),
            well.heightAnchor.constraint(equalToConstant: 20),
        ])
        solidRow.addArrangedSubview(well)
        outlineColorWell = well

        stack.addArrangedSubview(solidRow)
        NSLayoutConstraint.activate([
            solidRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        self.solidColorRow = solidRow

        // 3. Gradient & Multi-Color Controls Container (Visible when mode != .solid)
        let gradContainer = NSStackView()
        gradContainer.translatesAutoresizingMaskIntoConstraints = false
        gradContainer.orientation = .vertical
        gradContainer.alignment = .leading
        gradContainer.spacing = 6.0
        gradContainer.isHidden = true

        // Preset row
        let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopup.addItems(withTitles: [
            "VIBGYOR Rainbow (7 stops)",
            "Cyberpunk Synthwave",
            "Sunset Flare",
            "Aurora Borealis",
            "Random 4-Stop"
        ])
        presetPopup.selectItem(at: 0)
        presetPopup.controlSize = .small
        presetPopup.target = self
        presetPopup.action = #selector(onGradientPresetChanged(_:))
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let presetRow = NSStackView(views: [
            NSTextField(labelWithString: "Palette preset"),
            presetPopup
        ])
        presetRow.orientation = .horizontal
        presetRow.distribution = .fill
        gradContainer.addArrangedSubview(presetRow)
        self.gradientPresetPopup = presetPopup

        // Action Buttons: + Add Stop & Randomize Colors
        let actionRow = NSStackView()
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.distribution = .fillEqually
        actionRow.spacing = 8.0

        let addBtn = NSButton(title: "+ Add Stop", target: self, action: #selector(onAddGradientStopClicked))
        addBtn.bezelStyle = .rounded
        addBtn.controlSize = .small
        actionRow.addArrangedSubview(addBtn)
        self.addStopButton = addBtn

        let randBtn = NSButton(title: "🎲 Randomize", target: self, action: #selector(onRandomizeColorsClicked))
        randBtn.bezelStyle = .rounded
        randBtn.controlSize = .small
        actionRow.addArrangedSubview(randBtn)

        gradContainer.addArrangedSubview(actionRow)

        // Stops list container
        let stopsList = NSStackView()
        stopsList.translatesAutoresizingMaskIntoConstraints = false
        stopsList.orientation = .vertical
        stopsList.alignment = .leading
        stopsList.spacing = 4.0
        gradContainer.addArrangedSubview(stopsList)
        self.gradientStopsList = stopsList

        // Cycles / Frequency slider
        addSlider(to: gradContainer, title: "Cycles / Scale", range: 0.2...5.0, value: 1.0,
                  format: { String(format: "%.1fx", $0) }) { [weak self] val in
            self?.scene.setOutlineGradientScale(Float(val))
        }

        // Flow Animation Speed slider
        addSlider(to: gradContainer, title: "Flow speed", range: 0.0...2.0, value: 0.0,
                  format: { $0 == 0 ? "Static" : String(format: "%.2fx", $0) }) { [weak self] val in
            self?.scene.setOutlineFlowSpeed(Float(val))
        }

        stack.addArrangedSubview(gradContainer)
        NSLayoutConstraint.activate([
            gradContainer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            presetRow.widthAnchor.constraint(equalTo: gradContainer.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: gradContainer.widthAnchor),
            stopsList.widthAnchor.constraint(equalTo: gradContainer.widthAnchor),
        ])
        self.gradientControlsContainer = gradContainer

        rebuildGradientStopsUI()
    }

    private func rebuildGradientStopsUI() {
        guard let list = gradientStopsList else { return }
        for view in list.arrangedSubviews {
            list.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        addStopButton?.isEnabled = currentGradientStops.count < 8

        for (index, stop) in currentGradientStops.enumerated() {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fill
            row.spacing = 5.0

            let numLabel = NSTextField(labelWithString: "#\(index + 1)")
            numLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold)
            numLabel.textColor = .secondaryLabelColor
            numLabel.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(numLabel)

            let well = NSColorWell()
            well.translatesAutoresizingMaskIntoConstraints = false
            well.color = NSColor(srgbRed: CGFloat(stop.color.r), green: CGFloat(stop.color.g), blue: CGFloat(stop.color.b), alpha: 1.0)
            well.tag = index
            well.target = self
            well.action = #selector(onGradientStopColorWellChanged(_:))
            well.controlSize = .small
            NSLayoutConstraint.activate([
                well.widthAnchor.constraint(equalToConstant: 24),
                well.heightAnchor.constraint(equalToConstant: 18),
            ])
            row.addArrangedSubview(well)

            let slider = NSSlider(value: Double(stop.position), minValue: 0.0, maxValue: 1.0, target: self, action: #selector(onGradientStopSliderChanged(_:)))
            slider.tag = index
            slider.controlSize = .mini
            slider.isContinuous = true
            slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(slider)

            let valLabel = NSTextField(labelWithString: String(format: "%.2f", stop.position))
            valLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
            valLabel.textColor = .secondaryLabelColor
            valLabel.alignment = .right
            valLabel.setContentHuggingPriority(.required, for: .horizontal)
            row.addArrangedSubview(valLabel)

            let deleteBtn = NSButton(title: "✕", target: self, action: #selector(onDeleteGradientStopClicked(_:)))
            deleteBtn.tag = index
            deleteBtn.bezelStyle = .circular
            deleteBtn.controlSize = .mini
            deleteBtn.isBordered = false
            deleteBtn.font = NSFont.systemFont(ofSize: 9, weight: .bold)
            deleteBtn.toolTip = "Delete Stop"
            deleteBtn.isEnabled = currentGradientStops.count > 2
            row.addArrangedSubview(deleteBtn)

            list.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.widthAnchor.constraint(equalTo: list.widthAnchor),
            ])
        }
    }

    private func addHalftoneSection(to stack: NSStackView) {
        stack.addArrangedSubview(makeSectionHeader("Halftone & Screentone"))

        // Preset row
        let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopup.addItems(withTitles: [
            "Presets…",
            "🦸 Spider-Verse Pop-Art",
            "🎌 Manga Screentone",
            "📰 Vintage CMYK Newspaper",
            "✒️ Woodcut / Pen Hatching",
            "🚫 Disabled (Clean Cel)"
        ])
        presetPopup.selectItem(at: 0)
        presetPopup.controlSize = .small
        presetPopup.target = self
        presetPopup.action = #selector(onHalftonePresetChanged(_:))
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let presetRow = NSStackView(views: [
            NSTextField(labelWithString: "Preset"),
            presetPopup
        ])
        presetRow.orientation = .horizontal
        presetRow.distribution = .fill
        stack.addArrangedSubview(presetRow)
        self.halftonePresetPopup = presetPopup

        // Pattern / Mode
        let modePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for mode in FilamentToonMaterial.HalftoneMode.allCases {
            modePopup.addItem(withTitle: mode.title)
        }
        modePopup.selectItem(at: scene.toonMaterial?.halftoneMode.rawValue ?? 0)
        modePopup.controlSize = .small
        modePopup.target = self
        modePopup.action = #selector(onHalftoneModeChanged(_:))
        modePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let modeRow = NSStackView(views: [
            NSTextField(labelWithString: "Pattern"),
            modePopup
        ])
        modeRow.orientation = .horizontal
        modeRow.distribution = .fill
        stack.addArrangedSubview(modeRow)
        self.halftoneModePopup = modePopup

        // Target Area
        let targetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for target in FilamentToonMaterial.HalftoneTarget.allCases {
            targetPopup.addItem(withTitle: target.title)
        }
        targetPopup.selectItem(at: scene.toonMaterial?.halftoneTarget.rawValue ?? 0)
        targetPopup.controlSize = .small
        targetPopup.target = self
        targetPopup.action = #selector(onHalftoneTargetChanged(_:))
        targetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let targetRow = NSStackView(views: [
            NSTextField(labelWithString: "Target area"),
            targetPopup
        ])
        targetRow.orientation = .horizontal
        targetRow.distribution = .fill
        stack.addArrangedSubview(targetRow)
        self.halftoneTargetPopup = targetPopup

        // Sliders
        addSlider(to: stack, title: "Dot scale", range: 4.0...80.0,
                  value: Double(scene.toonMaterial?.halftoneScale ?? 24.0),
                  format: { String(format: "%.0f px", $0) }) { [weak self] val in
            self?.scene.setHalftoneScale(Float(val))
        }

        addSlider(to: stack, title: "Screen angle", range: 0.0...90.0,
                  value: Double(scene.toonMaterial?.halftoneAngle ?? 45.0),
                  format: { String(format: "%.0f°", $0) }) { [weak self] val in
            self?.scene.setHalftoneAngle(Float(val))
        }

        addSlider(to: stack, title: "Dot radius", range: 0.2...2.0,
                  value: Double(scene.toonMaterial?.halftoneDotSize ?? 1.0),
                  format: { String(format: "%.2f×", $0) }) { [weak self] val in
            self?.scene.setHalftoneDotSize(Float(val))
        }

        addSlider(to: stack, title: "Dot hardness", range: 0.0...1.0,
                  value: Double(scene.toonMaterial?.halftoneHardness ?? 0.85),
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setHalftoneHardness(Float(val))
        }

        addSlider(to: stack, title: "Halftone blend", range: 0.0...1.0,
                  value: Double(scene.toonMaterial?.halftoneBlend ?? 1.0),
                  format: { String(format: "%.0f%%", $0 * 100.0) }) { [weak self] val in
            self?.scene.setHalftoneBlend(Float(val))
        }

        // Ink Color Row
        let inkRow = NSStackView()
        inkRow.translatesAutoresizingMaskIntoConstraints = false
        inkRow.orientation = .horizontal
        inkRow.alignment = .centerY
        inkRow.distribution = .fill
        inkRow.spacing = 6.0

        let inkLabel = NSTextField(labelWithString: "Ink color")
        inkLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        inkLabel.setContentHuggingPriority(.required, for: .horizontal)
        inkRow.addArrangedSubview(inkLabel)

        let inkPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in halftoneInkPresets {
            inkPopup.addItem(withTitle: preset.name)
        }
        inkPopup.addItem(withTitle: "Custom…")
        inkPopup.selectItem(at: 0)
        inkPopup.controlSize = .small
        inkPopup.target = self
        inkPopup.action = #selector(onHalftoneInkPopupChanged(_:))
        inkPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inkRow.addArrangedSubview(inkPopup)
        self.halftoneDotColorPopup = inkPopup

        let inkWell = NSColorWell()
        inkWell.translatesAutoresizingMaskIntoConstraints = false
        inkWell.color = halftoneInkPresets[0].nsColor
        inkWell.target = self
        inkWell.action = #selector(onHalftoneInkWellChanged(_:))
        inkWell.controlSize = .small
        inkWell.toolTip = "Pick Custom Ink Color"
        NSLayoutConstraint.activate([
            inkWell.widthAnchor.constraint(equalToConstant: 28),
            inkWell.heightAnchor.constraint(equalToConstant: 20),
        ])
        inkRow.addArrangedSubview(inkWell)
        self.halftoneDotColorWell = inkWell

        stack.addArrangedSubview(inkRow)
        NSLayoutConstraint.activate([
            inkRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        // Paper Tint Row
        let paperRow = NSStackView()
        paperRow.translatesAutoresizingMaskIntoConstraints = false
        paperRow.orientation = .horizontal
        paperRow.alignment = .centerY
        paperRow.distribution = .fill
        paperRow.spacing = 6.0

        let paperLabel = NSTextField(labelWithString: "Paper tint")
        paperLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        paperLabel.setContentHuggingPriority(.required, for: .horizontal)
        paperRow.addArrangedSubview(paperLabel)

        let paperPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in halftonePaperPresets {
            paperPopup.addItem(withTitle: preset.name)
        }
        paperPopup.addItem(withTitle: "Custom…")
        paperPopup.selectItem(at: 0)
        paperPopup.controlSize = .small
        paperPopup.target = self
        paperPopup.action = #selector(onHalftonePaperPopupChanged(_:))
        paperPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paperRow.addArrangedSubview(paperPopup)
        self.halftonePaperColorPopup = paperPopup

        let paperWell = NSColorWell()
        paperWell.translatesAutoresizingMaskIntoConstraints = false
        paperWell.color = halftonePaperPresets[0].nsColor
        paperWell.target = self
        paperWell.action = #selector(onHalftonePaperWellChanged(_:))
        paperWell.controlSize = .small
        paperWell.toolTip = "Pick Custom Paper Color"
        NSLayoutConstraint.activate([
            paperWell.widthAnchor.constraint(equalToConstant: 28),
            paperWell.heightAnchor.constraint(equalToConstant: 20),
        ])
        paperRow.addArrangedSubview(paperWell)
        self.halftonePaperColorWell = paperWell

        stack.addArrangedSubview(paperRow)
        NSLayoutConstraint.activate([
            paperRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func addHanddrawnSketchSection(to stack: NSStackView) {
        stack.addArrangedSubview(makeSectionHeader("Handdrawn Technical Sketch & CAD"))

        // Mode switch button
        let modeButton = NSButton(title: "✏️ Switch to Technical Sketch Mode", target: self, action: #selector(onActivateSketchModeClicked))
        modeButton.bezelStyle = .rounded
        modeButton.controlSize = .small
        modeButton.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        stack.addArrangedSubview(modeButton)

        // Presets dropdown
        let presetPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        presetPopup.addItems(withTitles: [
            "Sketch Presets…",
            "📐 Architectural Drafting (White + Graphite)",
            "📘 Technical Blueprint (Cyan + Navy)",
            "✏️ Handdrawn 2B Pencil (Wobble on Vellum)",
            "✒️ CAD Vector Wireframe (Crisp Ink)",
            "📄 Transparent Mylar (Figma Export)"
        ])
        presetPopup.selectItem(at: 0)
        presetPopup.controlSize = .small
        presetPopup.target = self
        presetPopup.action = #selector(onSketchPresetChanged(_:))
        presetPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let presetRow = NSStackView(views: [
            NSTextField(labelWithString: "Preset"),
            presetPopup
        ])
        presetRow.orientation = .horizontal
        presetRow.distribution = .fill
        stack.addArrangedSubview(presetRow)
        self.sketchPresetPopup = presetPopup

        // Outline Stroke Style / Texture
        let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        stylePopup.addItems(withTitles: [
            "Graphite Pencil Lead (Micro-Grain)",
            "Solid Technical Ink Line"
        ])
        stylePopup.selectItem(at: 0)
        stylePopup.controlSize = .small
        stylePopup.target = self
        stylePopup.action = #selector(onSketchOutlineStyleChanged(_:))
        stylePopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let styleRow = NSStackView(views: [
            NSTextField(labelWithString: "Stroke style"),
            stylePopup
        ])
        styleRow.orientation = .horizontal
        styleRow.distribution = .fill
        stack.addArrangedSubview(styleRow)
        self.sketchOutlineStylePopup = stylePopup

        // Sliders for Pencil Stroke
        addSlider(to: stack, title: "Pencil weight", range: 0.5...8.0,
                  value: 2.2,
                  format: { String(format: "%.1f px", $0) }) { [weak self] val in
            self?.scene.setOutlineThickness(Float(val))
        }

        addSlider(to: stack, title: "Stroke wobble", range: 0.0...1.0,
                  value: 0.25,
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setOutlineJitter(Float(val))
        }

        addSlider(to: stack, title: "Wobble freq", range: 0.5...20.0,
                  value: 4.0,
                  format: { String(format: "%.1f", $0) }) { [weak self] val in
            self?.scene.setOutlineJitterFreq(Float(val))
        }

        // Sliders for Hatching Shades
        addSlider(to: stack, title: "Hatch spacing", range: 4.0...60.0,
                  value: 16.0,
                  format: { String(format: "%.0f px", $0) }) { [weak self] val in
            self?.scene.setHalftoneScale(Float(val))
        }

        addSlider(to: stack, title: "Hatch angle", range: 0.0...180.0,
                  value: 45.0,
                  format: { String(format: "%.0f°", $0) }) { [weak self] val in
            self?.scene.setHalftoneAngle(Float(val))
        }

        addSlider(to: stack, title: "Hatch wobble", range: 0.0...1.0,
                  value: 0.20,
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setHatchJitter(Float(val))
        }

        // Cross-Hatch Depth / Layers
        let layersPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        layersPopup.addItems(withTitles: [
            "1 Tier: Single Directional (45°)",
            "2 Tiers: Cross-Hatch (+60°)",
            "3 Tiers: Dense Shadows (-45°)",
            "4 Tiers: Core Crevice Stippling (+90°)"
        ])
        layersPopup.selectItem(at: 2) // default 3 tiers
        layersPopup.controlSize = .small
        layersPopup.target = self
        layersPopup.action = #selector(onSketchLayersChanged(_:))
        layersPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let layersRow = NSStackView(views: [
            NSTextField(labelWithString: "Cross-hatch"),
            layersPopup
        ])
        layersRow.orientation = .horizontal
        layersRow.distribution = .fill
        stack.addArrangedSubview(layersRow)
        self.sketchLayersPopup = layersPopup

        addSlider(to: stack, title: "Lead hardness", range: 0.1...1.0,
                  value: 0.88,
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setHalftoneHardness(Float(val))
        }

        addSlider(to: stack, title: "Hatch coverage", range: -0.5...0.8,
                  value: 0.05,
                  format: { String(format: "%.2f", $0) }) { [weak self] val in
            self?.scene.setToonShadowThreshold(Float(val))
        }

        // Ink / Graphite Color Row
        let inkRow = NSStackView()
        inkRow.translatesAutoresizingMaskIntoConstraints = false
        inkRow.orientation = .horizontal
        inkRow.alignment = .centerY
        inkRow.distribution = .fill
        inkRow.spacing = 6.0

        let inkLabel = NSTextField(labelWithString: "Lead / ink")
        inkLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        inkLabel.setContentHuggingPriority(.required, for: .horizontal)
        inkRow.addArrangedSubview(inkLabel)

        let inkPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in sketchInkPresets {
            inkPopup.addItem(withTitle: preset.name)
        }
        inkPopup.addItem(withTitle: "Custom…")
        inkPopup.selectItem(at: 0)
        inkPopup.controlSize = .small
        inkPopup.target = self
        inkPopup.action = #selector(onSketchInkPopupChanged(_:))
        inkPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inkRow.addArrangedSubview(inkPopup)
        self.sketchInkColorPopup = inkPopup

        let inkWell = NSColorWell()
        inkWell.translatesAutoresizingMaskIntoConstraints = false
        inkWell.color = sketchInkPresets[0].nsColor
        inkWell.target = self
        inkWell.action = #selector(onSketchInkWellChanged(_:))
        inkWell.controlSize = .small
        inkWell.toolTip = "Pick Custom Lead/Ink Color"
        NSLayoutConstraint.activate([
            inkWell.widthAnchor.constraint(equalToConstant: 28),
            inkWell.heightAnchor.constraint(equalToConstant: 20),
        ])
        inkRow.addArrangedSubview(inkWell)
        self.sketchInkColorWell = inkWell

        stack.addArrangedSubview(inkRow)
        NSLayoutConstraint.activate([
            inkRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        // Paper Tone Row
        let paperRow = NSStackView()
        paperRow.translatesAutoresizingMaskIntoConstraints = false
        paperRow.orientation = .horizontal
        paperRow.alignment = .centerY
        paperRow.distribution = .fill
        paperRow.spacing = 6.0

        let paperLabel = NSTextField(labelWithString: "Paper tone")
        paperLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        paperLabel.setContentHuggingPriority(.required, for: .horizontal)
        paperRow.addArrangedSubview(paperLabel)

        let paperPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for preset in sketchPaperPresets {
            paperPopup.addItem(withTitle: preset.name)
        }
        paperPopup.addItem(withTitle: "Custom…")
        paperPopup.selectItem(at: 0)
        paperPopup.controlSize = .small
        paperPopup.target = self
        paperPopup.action = #selector(onSketchPaperPopupChanged(_:))
        paperPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)
        paperRow.addArrangedSubview(paperPopup)
        self.sketchPaperColorPopup = paperPopup

        let paperWell = NSColorWell()
        paperWell.translatesAutoresizingMaskIntoConstraints = false
        paperWell.color = sketchPaperPresets[0].nsColor
        paperWell.target = self
        paperWell.action = #selector(onSketchPaperWellChanged(_:))
        paperWell.controlSize = .small
        paperWell.toolTip = "Pick Custom Paper Tone"
        NSLayoutConstraint.activate([
            paperWell.widthAnchor.constraint(equalToConstant: 28),
            paperWell.heightAnchor.constraint(equalToConstant: 20),
        ])
        paperRow.addArrangedSubview(paperWell)
        self.sketchPaperColorWell = paperWell

        stack.addArrangedSubview(paperRow)
        NSLayoutConstraint.activate([
            paperRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
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

        let overlayBtn = makeButton("Floating Companion Window", action: #selector(toggleOverlayClicked))
        stack.addArrangedSubview(overlayBtn)
        self.overlayButton = overlayBtn

        let ovLabel = NSTextField(labelWithString: "Floating Window: Closed")
        ovLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        ovLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(ovLabel)
        self.overlayLabel = ovLabel

        let passthroughBox = NSButton(
            checkboxWithTitle: "Event Passthrough (Click-Through)",
            target: self,
            action: #selector(toggleEventPassthroughClicked(_:))
        )
        passthroughBox.state = scene.isOverlayEventPassthrough ? .on : .off
        passthroughBox.toolTip = "When enabled, mouse clicks and scrolls pass through the floating companion to desktop apps beneath it."
        stack.addArrangedSubview(passthroughBox)
        self.overlayPassthroughCheckbox = passthroughBox

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
        if let toon = scene.toonMaterial {
            halftoneModePopup?.selectItem(at: toon.halftoneMode.rawValue)
            halftoneTargetPopup?.selectItem(at: toon.halftoneTarget.rawValue)
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

    // MARK: - Overlay Window Actions

    func syncOverlayUI(active: Bool) {
        let passthrough = scene.isOverlayEventPassthrough
        let statusText = active
            ? "Floating Window: Active (Metal Overlay)\(passthrough ? " · Click-Through ON" : "")"
            : "Floating Window: Closed"
        overlayLabel?.stringValue = statusText
        overlayLabel?.textColor = active ? .systemGreen : .secondaryLabelColor
        overlayButton?.title = active ? "Close Companion Window" : "Floating Companion Window"
        overlayPassthroughCheckbox?.state = passthrough ? .on : .off
    }

    @objc func toggleOverlayClicked() {
        let active = scene.toggleOverlayWindow()
        syncOverlayUI(active: active)
    }

    @objc private func toggleEventPassthroughClicked(_ sender: NSButton) {
        let enabled = sender.state == .on
        setEventPassthrough(enabled)
    }

    func setEventPassthrough(_ enabled: Bool) {
        scene.setOverlayEventPassthrough(enabled)
        syncOverlayUI(active: scene.overlayWindow != nil)
    }

    func toggleEventPassthrough() {
        let newActive = scene.toggleOverlayEventPassthrough()
        overlayPassthroughCheckbox?.state = newActive ? .on : .off
        syncOverlayUI(active: scene.overlayWindow != nil)
    }

    // MARK: - Outline Color Actions

    func setOutlineColorPreset(index: Int) {
        guard index >= 0 && index < outlineColorPresets.count else { return }
        let preset = outlineColorPresets[index]
        setOutlineColor(r: preset.color.r, g: preset.color.g, b: preset.color.b)
    }

    func setOutlineColor(r: Float, g: Float, b: Float) {
        scene.setOutlineColor(r: r, g: g, b: b)
        let nsColor = NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1.0)
        outlineColorWell?.color = nsColor
        if let idx = outlineColorPresets.firstIndex(where: {
            abs($0.color.r - r) < 0.02 && abs($0.color.g - g) < 0.02 && abs($0.color.b - b) < 0.02
        }) {
            outlineColorPopup?.selectItem(at: idx)
        } else {
            outlineColorPopup?.selectItem(withTitle: "Custom…")
        }
    }

    @objc private func onOutlineColorPopupChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx >= 0 && idx < outlineColorPresets.count {
            let preset = outlineColorPresets[idx]
            outlineColorWell?.color = preset.nsColor
            scene.setOutlineColor(r: preset.color.r, g: preset.color.g, b: preset.color.b)
        }
    }

    @objc private func onOutlineColorWellChanged(_ sender: NSColorWell) {
        let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let r = Float(color.redComponent)
        let g = Float(color.greenComponent)
        let b = Float(color.blueComponent)
        scene.setOutlineColor(r: r, g: g, b: b)

        if let idx = outlineColorPresets.firstIndex(where: {
            abs($0.color.r - r) < 0.02 && abs($0.color.g - g) < 0.02 && abs($0.color.b - b) < 0.02
        }) {
            outlineColorPopup?.selectItem(at: idx)
        } else {
            outlineColorPopup?.selectItem(withTitle: "Custom…")
        }
    }

    // MARK: - Gradient & Multi-Color Actions

    @objc private func onOutlineStyleChanged(_ sender: NSPopUpButton) {
        guard let mode = FilamentToonOutlineMaterial.GradientMode(rawValue: Int32(sender.indexOfSelectedItem)) else { return }
        setOutlineGradientMode(mode)
    }

    func setOutlineGradientMode(_ mode: FilamentToonOutlineMaterial.GradientMode) {
        currentOutlineGradientMode = mode
        scene.setOutlineGradientMode(mode)
        outlineStylePopup?.selectItem(at: Int(mode.rawValue))
        solidColorRow?.isHidden = (mode != .solid)
        gradientControlsContainer?.isHidden = (mode == .solid)
    }

    func applyVibgyorPalette() {
        setOutlineGradientMode(.vertical)
        currentGradientStops = FilamentToonOutlineMaterial.vibgyorStops
        scene.setOutlineStops(currentGradientStops)
        rebuildGradientStopsUI()
    }

    @objc private func onGradientPresetChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 0:
            currentGradientStops = FilamentToonOutlineMaterial.vibgyorStops
        case 1:
            currentGradientStops = FilamentToonOutlineMaterial.synthwaveStops
        case 2:
            currentGradientStops = FilamentToonOutlineMaterial.sunsetStops
        case 3:
            currentGradientStops = FilamentToonOutlineMaterial.auroraStops
        case 4:
            currentGradientStops = FilamentToonOutlineMaterial.generateRandomStops(count: 4)
        default: break
        }
        scene.setOutlineStops(currentGradientStops)
        rebuildGradientStopsUI()
    }

    @objc func onAddGradientStopClicked() {
        guard currentGradientStops.count < 8 else { return }
        let randomColor: (Float, Float, Float, Float) = (Float.random(in: 0.2...1.0), Float.random(in: 0.2...1.0), Float.random(in: 0.2...1.0), 1.0)
        let lastPos = currentGradientStops.last?.position ?? 0.8
        let newPos: Float = min(1.0, lastPos + 0.1)
        currentGradientStops.append(FilamentToonOutlineMaterial.GradientStop(position: newPos, color: randomColor))
        currentGradientStops.sort { $0.position < $1.position }
        scene.setOutlineStops(currentGradientStops)
        rebuildGradientStopsUI()
    }

    @objc func onRandomizeColorsClicked() {
        for i in 0..<currentGradientStops.count {
            let r = Float.random(in: 0.15...1.0)
            let g = Float.random(in: 0.15...1.0)
            let b = Float.random(in: 0.15...1.0)
            currentGradientStops[i].color = (r, g, b, 1.0)
        }
        scene.setOutlineStops(currentGradientStops)
        rebuildGradientStopsUI()
    }

    @objc private func onGradientStopColorWellChanged(_ sender: NSColorWell) {
        let index = sender.tag
        guard index >= 0 && index < currentGradientStops.count else { return }
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let r = Float(c.redComponent)
        let g = Float(c.greenComponent)
        let b = Float(c.blueComponent)
        currentGradientStops[index].color = (r, g, b, 1.0)
        scene.updateOutlineStop(at: index, r: r, g: g, b: b)
    }

    @objc private func onGradientStopSliderChanged(_ sender: NSSlider) {
        let index = sender.tag
        guard index >= 0 && index < currentGradientStops.count else { return }
        let pos = Float(sender.doubleValue)
        currentGradientStops[index].position = pos
        scene.updateOutlineStopPosition(at: index, position: pos)

        if let row = sender.superview as? NSStackView,
           row.arrangedSubviews.count >= 4,
           let valLabel = row.arrangedSubviews[3] as? NSTextField {
            valLabel.stringValue = String(format: "%.2f", pos)
        }
    }

    @objc private func onDeleteGradientStopClicked(_ sender: NSButton) {
        let index = sender.tag
        guard currentGradientStops.count > 2, index >= 0 && index < currentGradientStops.count else { return }
        currentGradientStops.remove(at: index)
        scene.removeOutlineStop(at: index)
        rebuildGradientStopsUI()
    }

    // MARK: - Halftone Action Handlers

    @objc private func onHalftoneModeChanged(_ sender: NSPopUpButton) {
        guard let mode = FilamentToonMaterial.HalftoneMode(rawValue: sender.indexOfSelectedItem) else { return }
        scene.setHalftoneMode(mode)
    }

    @objc private func onHalftoneTargetChanged(_ sender: NSPopUpButton) {
        guard let target = FilamentToonMaterial.HalftoneTarget(rawValue: sender.indexOfSelectedItem) else { return }
        scene.setHalftoneTarget(target)
    }

    @objc private func onHalftonePresetChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: // Spider-Verse
            applyHalftonePreset(FilamentToonMaterial.spiderVersePreset)
        case 2: // Manga Screentone
            applyHalftonePreset(FilamentToonMaterial.mangaScreentonePreset)
        case 3: // CMYK Newspaper
            applyHalftonePreset(FilamentToonMaterial.cmykNewspaperPreset)
        case 4: // Woodcut / Pen Hatching
            applyHalftonePreset(FilamentToonMaterial.comicHatchingPreset)
        case 5: // Disabled
            scene.setHalftoneMode(.disabled)
            halftoneModePopup?.selectItem(at: 0)
        default: break
        }
    }

    func applyHalftonePreset(_ preset: FilamentToonMaterial.HalftonePreset) {
        scene.applyHalftonePreset(preset)
        halftoneModePopup?.selectItem(at: preset.mode.rawValue)
        halftoneTargetPopup?.selectItem(at: preset.target.rawValue)
        updateSlider(titled: "Dot scale", to: Double(preset.scale))
        updateSlider(titled: "Screen angle", to: Double(preset.angle))
        updateSlider(titled: "Dot radius", to: Double(preset.dotSize))
        updateSlider(titled: "Dot hardness", to: Double(preset.hardness))
        updateSlider(titled: "Halftone blend", to: 1.0)
        let dotNS = NSColor(srgbRed: CGFloat(preset.dotColor.r), green: CGFloat(preset.dotColor.g), blue: CGFloat(preset.dotColor.b), alpha: CGFloat(preset.dotColor.a))
        halftoneDotColorWell?.color = dotNS
        let paperNS = NSColor(srgbRed: CGFloat(preset.paperColor.r), green: CGFloat(preset.paperColor.g), blue: CGFloat(preset.paperColor.b), alpha: CGFloat(preset.paperColor.a))
        halftonePaperColorWell?.color = paperNS
    }

    private func updateSlider(titled title: String, to value: Double) {
        if let binding = sliderBindings.first(where: { $0.key == title }) {
            binding.slider.doubleValue = min(max(value, binding.range.lowerBound), binding.range.upperBound)
            binding.valueLabel.stringValue = binding.format(binding.slider.doubleValue)
        }
    }

    @objc private func onHalftoneInkPopupChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < halftoneInkPresets.count else { return }
        let preset = halftoneInkPresets[index]
        scene.setHalftoneDotColor(r: preset.color.r, g: preset.color.g, b: preset.color.b, a: preset.color.a)
        halftoneDotColorWell?.color = preset.nsColor
    }

    @objc private func onHalftoneInkWellChanged(_ sender: NSColorWell) {
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let r = Float(c.redComponent)
        let g = Float(c.greenComponent)
        let b = Float(c.blueComponent)
        let a = Float(c.alphaComponent)
        scene.setHalftoneDotColor(r: r, g: g, b: b, a: a)
        halftoneDotColorPopup?.selectItem(withTitle: "Custom…")
    }

    @objc private func onHalftonePaperPopupChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard index >= 0 && index < halftonePaperPresets.count else { return }
        let preset = halftonePaperPresets[index]
        scene.setHalftonePaperColor(r: preset.color.r, g: preset.color.g, b: preset.color.b, a: preset.color.a)
        halftonePaperColorWell?.color = preset.nsColor
    }

    @objc private func onHalftonePaperWellChanged(_ sender: NSColorWell) {
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let r = Float(c.redComponent)
        let g = Float(c.greenComponent)
        let b = Float(c.blueComponent)
        let a = Float(c.alphaComponent)
        scene.setHalftonePaperColor(r: r, g: g, b: b, a: a)
        halftonePaperColorPopup?.selectItem(withTitle: "Custom…")
    }

    // MARK: - Handdrawn Technical Sketch Actions

    @objc private func onActivateSketchModeClicked() {
        scene.setShadingMode(.handdrawnSketch)
        syncShadingMode()
    }

    @objc private func onSketchPresetChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1:
            scene.setShadingMode(.handdrawnSketch)
            applySketchPreset(FilamentToonMaterial.technicalArchitecturalPreset)
        case 2:
            scene.setShadingMode(.handdrawnSketch)
            applySketchPreset(FilamentToonMaterial.blueprintPatentPreset)
        case 3:
            scene.setShadingMode(.handdrawnSketch)
            applySketchPreset(FilamentToonMaterial.handdrawnPencil2BPreset)
        case 4:
            scene.setShadingMode(.handdrawnSketch)
            applySketchPreset(FilamentToonMaterial.cadVectorWireframePreset)
        case 5:
            scene.setShadingMode(.handdrawnSketch)
            applySketchPreset(FilamentToonMaterial.transparentMylarPreset)
        default: break
        }
        syncShadingMode()
    }

    @objc private func onSketchOutlineStyleChanged(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem == 0 {
            scene.setOutlineGradientMode(.graphitePencil)
        } else {
            scene.setOutlineGradientMode(.solid)
        }
    }

    @objc private func onSketchLayersChanged(_ sender: NSPopUpButton) {
        let layers = Int32(sender.indexOfSelectedItem + 1)
        scene.setHatchLayers(layers)
    }

    @objc private func onSketchInkPopupChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < sketchInkPresets.count else { return }
        let preset = sketchInkPresets[idx]
        scene.setHalftoneDotColor(r: preset.color.r, g: preset.color.g, b: preset.color.b, a: preset.color.a)
        scene.setOutlineColor(r: preset.color.r, g: preset.color.g, b: preset.color.b)
        sketchInkColorWell?.color = preset.nsColor
    }

    @objc private func onSketchInkWellChanged(_ sender: NSColorWell) {
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let r = Float(c.redComponent)
        let g = Float(c.greenComponent)
        let b = Float(c.blueComponent)
        let a = Float(c.alphaComponent)
        scene.setHalftoneDotColor(r: r, g: g, b: b, a: a)
        scene.setOutlineColor(r: r, g: g, b: b)
        sketchInkColorPopup?.selectItem(withTitle: "Custom…")
    }

    @objc private func onSketchPaperPopupChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < sketchPaperPresets.count else { return }
        let preset = sketchPaperPresets[idx]
        scene.setHalftonePaperColor(r: preset.color.r, g: preset.color.g, b: preset.color.b, a: preset.color.a)
        sketchPaperColorWell?.color = preset.nsColor

        if preset.color.a < 0.01 {
            // Transparent
        } else if preset.color.r < 0.15 && preset.color.b > 0.20 {
            scene.setCanvasBackground(.blueprint)
        } else if preset.color.r > 0.95 && preset.color.g > 0.95 && preset.color.b > 0.95 {
            scene.setCanvasBackground(.paperWhite)
        } else if preset.color.r > 0.90 && preset.color.b < 0.95 {
            scene.setCanvasBackground(.creamVellum)
        } else {
            scene.setCanvasBackground(.slateCharcoal)
        }
    }

    @objc private func onSketchPaperWellChanged(_ sender: NSColorWell) {
        let c = sender.color.usingColorSpace(.sRGB) ?? sender.color
        let r = Float(c.redComponent)
        let g = Float(c.greenComponent)
        let b = Float(c.blueComponent)
        let a = Float(c.alphaComponent)
        scene.setHalftonePaperColor(r: r, g: g, b: b, a: a)
        sketchPaperColorPopup?.selectItem(withTitle: "Custom…")
    }

    func applySketchPreset(_ preset: FilamentToonMaterial.HalftonePreset) {
        scene.applySketchPreset(preset)
        updateSlider(titled: "Pencil weight", to: Double(preset.dotSize * 2.2))
        updateSlider(titled: "Stroke wobble", to: Double(preset.hatchJitter * 0.85))
        updateSlider(titled: "Hatch spacing", to: Double(preset.scale))
        updateSlider(titled: "Hatch angle", to: Double(preset.angle))
        updateSlider(titled: "Hatch wobble", to: Double(preset.hatchJitter))
        updateSlider(titled: "Lead hardness", to: Double(preset.hardness))
        sketchLayersPopup?.selectItem(at: max(0, min(3, Int(preset.hatchLayers - 1))))
        let dotNS = NSColor(srgbRed: CGFloat(preset.dotColor.r), green: CGFloat(preset.dotColor.g), blue: CGFloat(preset.dotColor.b), alpha: CGFloat(preset.dotColor.a))
        sketchInkColorWell?.color = dotNS
        let paperNS = NSColor(srgbRed: CGFloat(preset.paperColor.r), green: CGFloat(preset.paperColor.g), blue: CGFloat(preset.paperColor.b), alpha: CGFloat(preset.paperColor.a))
        sketchPaperColorWell?.color = paperNS
    }

    // MARK: - Demo Mode Actions

    @objc func toggleDemoModeClicked() {
        onToggleDemoModeRequested?()
    }

    @objc private func onDemoZoomSliderChanged(_ sender: NSSlider) {
        scene.setDemoZoomScale(sender.doubleValue)
    }

    @objc private func onDemoZoomMinusClicked() {
        scene.adjustDemoZoomScale(byDelta: -1.5)
    }

    @objc private func onDemoZoomPlusClicked() {
        scene.adjustDemoZoomScale(byDelta: 1.5)
    }

    @objc private func onDemoZoomResetClicked() {
        scene.setDemoZoomScale(1.0)
    }

    @objc private func onMatchViewportClicked() {
        scene.matchDemoZoomScaleToViewport()
    }

    func setDemoZoomScale(_ scale: Double) {
        demoZoomLabel?.stringValue = String(format: "Demo Zoom Scale: %.2fx", scale)
        if let slider = demoZoomSlider {
            slider.doubleValue = min(max(scale, slider.minValue), slider.maxValue)
        }
    }

    func syncDemoModeUI(active: Bool) {
        if active {
            demoModeButton?.title = "⏹ Stop Demo Reel"
            demoModeButton?.contentTintColor = .systemRed
        } else {
            demoModeButton?.title = "🎬 Start Demo Reel (Auto-Cycle)"
            demoModeButton?.contentTintColor = .systemPurple
        }
    }
}
