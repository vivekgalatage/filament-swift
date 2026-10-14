import Foundation
import Filament

/// Identifies a single widget of the GTK 4 PBR control panel.
enum PanelControl: Sendable {
    // Stylized Shading & Ink
    case shadingMode
    // Outline controls
    case outlineThickness, outlineGradientMode, outlineFlowSpeed, outlineGradientScale, outlineNoiseScale
    // Halftone & Screentone
    case halftonePreset, halftoneMode, halftoneTarget, halftoneScale, halftoneAngle, halftoneDotSize, halftoneHardness, halftoneBlend
    // Lighting
    case keyIntensity, fillIntensity, ambient, shadows
    // Tone mapping
    case toneMapping, exposure, contrast, saturation, vibrance, whiteBalance
    // Anti-aliasing
    case antiAliasing, msaa, dithering, hdrQuality
    // Effects
    case bloom, bloomStrength, vignette, vignetteStrength
    case occlusion, occlusionMode, occlusionIntensity, occlusionRadius
    case reflections, reflectionDistance
    case depthOfField, depthOfFieldStrength
}

/// Builds and synchronizes the GTK 4 side panel driving `FilamentPBRController` and stylized rendering.
@MainActor
final class GTKControlPanel {
    private static let msaaOptions: [String] = ["1", "2", "4", "8"]

    private let scene: GTKSceneController?
    private let controller: FilamentPBRController
    private var panelWidgets: [PanelControl: OpaquePointer] = [:]

    init(scene: GTKSceneController, in box: OpaquePointer) {
        self.scene = scene
        self.controller = scene.controller
        build(in: box)
    }

    convenience init(controller: FilamentPBRController, in box: OpaquePointer) {
        self.init(scene: nil, controller: controller, in: box)
    }

    init(scene: GTKSceneController?, controller: FilamentPBRController, in box: OpaquePointer) {
        self.scene = scene
        self.controller = controller
        build(in: box)
    }

    private func build(in box: OpaquePointer) {
        // Stylized Shading & Inked Outlines
        addSectionHeader("Stylized Shading & Ink", to: box)
        addDropdown(.shadingMode, label: "Style", items: GTKSceneController.ShadingMode.allCases.map(\.title), to: box)
        addSeparator(to: box)

        // Outline Controls
        addSectionHeader("Inked Outline", to: box)
        addSlider(.outlineThickness, label: "Outline thickness", range: 0.5...8.0, step: 0.1, to: box)
        addDropdown(.outlineGradientMode, label: "Color mode", items: FilamentToonOutlineMaterial.GradientMode.allCases.map(\.title), to: box)
        addSlider(.outlineFlowSpeed, label: "Flow animation speed", range: 0...5.0, step: 0.1, to: box)
        addSlider(.outlineGradientScale, label: "Gradient frequency", range: 0.1...10.0, step: 0.1, to: box)
        addSlider(.outlineNoiseScale, label: "Noise distortion", range: 0.1...20.0, step: 0.5, to: box)

        let randBtn = gtk_button_new_with_label("Randomize Outline Colors")
        gtk_widget_set_hexpand(randBtn, 1)
        gtk_box_append(box, randBtn)
        let randCallback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let panel = Unmanaged<GTKControlPanel>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { panel.scene?.randomizeOutlineColors() }
        }
        g_signal_connect_data(
            randBtn,
            "clicked",
            unsafeBitCast(randCallback, to: (@convention(c) () -> Void).self),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            0
        )
        addSeparator(to: box)

        // Comic Halftone & Screentone
        addSectionHeader("Halftone & Screentone", to: box)
        let halftonePresets = ["Custom", "Spider-Verse Pop-Art", "Manga Screentone", "Vintage CMYK Newspaper", "Woodcut / Pen Hatching"]
        addDropdown(.halftonePreset, label: "Preset", items: halftonePresets, to: box)
        addDropdown(.halftoneMode, label: "Pattern", items: FilamentToonMaterial.HalftoneMode.allCases.map(\.title), to: box)
        addDropdown(.halftoneTarget, label: "Target zone", items: FilamentToonMaterial.HalftoneTarget.allCases.map(\.title), to: box)
        addSlider(.halftoneScale, label: "Dot frequency scale", range: 2.0...120.0, step: 1.0, to: box)
        addSlider(.halftoneAngle, label: "Screen angle (°)", range: 0...180.0, step: 1.0, to: box)
        addSlider(.halftoneDotSize, label: "Dot radius", range: 0.1...2.0, step: 0.05, to: box)
        addSlider(.halftoneHardness, label: "Edge hardness", range: 0...1.0, step: 0.01, to: box)
        addSlider(.halftoneBlend, label: "Effect blend", range: 0...1.0, step: 0.01, to: box)
        addSeparator(to: box)

        // Lighting
        addSectionHeader("Lighting", to: box)
        addSlider(.keyIntensity, label: "Key light", range: 0...200_000, step: 500, to: box)
        addSlider(.fillIntensity, label: "Fill light", range: 0...200_000, step: 500, to: box)
        addSlider(.ambient, label: "Ambient", range: 0...100_000, step: 500, to: box)
        addCheck(.shadows, label: "Shadows", to: box)
        addSeparator(to: box)

        // Tone mapping
        addSectionHeader("Tone Mapping", to: box)
        addDropdown(.toneMapping, label: "Operator", items: FilamentToneMapping.allCases.map(\.displayName), to: box)
        addSlider(.exposure, label: "Exposure", range: 0.1...4.0, step: 0.01, to: box)
        addSlider(.contrast, label: "Contrast", range: 0...2, step: 0.01, to: box)
        addSlider(.saturation, label: "Saturation", range: 0...2, step: 0.01, to: box)
        addSlider(.vibrance, label: "Vibrance", range: 0...2, step: 0.01, to: box)
        addSlider(.whiteBalance, label: "White balance", range: -1.0...1.0, step: 0.01, to: box)
        addSeparator(to: box)

        // Anti-aliasing
        addSectionHeader("Anti-Aliasing", to: box)
        addDropdown(.antiAliasing, label: "Method", items: FilamentAntiAliasing.allCases.map(\.displayName), to: box)
        addDropdown(.msaa, label: "MSAA", items: Self.msaaOptions, to: box)
        addCheck(.dithering, label: "Dithering", to: box)
        addDropdown(.hdrQuality, label: "HDR quality", items: FilamentHDRQuality.allCases.map(\.displayName), to: box)
        addSeparator(to: box)

        // Effects
        addSectionHeader("Effects", to: box)
        addCheck(.bloom, label: "Bloom", to: box)
        addSlider(.bloomStrength, label: "Bloom strength", range: 0...1, step: 0.01, to: box)
        addCheck(.vignette, label: "Vignette", to: box)
        addSlider(.vignetteStrength, label: "Vignette strength", range: 0...1, step: 0.01, to: box)
        addCheck(.occlusion, label: "Ambient occlusion", to: box)
        addDropdown(.occlusionMode, label: "Occlusion mode", items: FilamentOcclusionMode.allCases.map(\.displayName), to: box)
        addSlider(.occlusionIntensity, label: "Occlusion intensity", range: 0...2, step: 0.01, to: box)
        addSlider(.occlusionRadius, label: "Occlusion radius", range: 0...3, step: 0.01, to: box)
        addCheck(.reflections, label: "Screen-space reflections", to: box)
        addSlider(.reflectionDistance, label: "Reflection distance", range: 0...10, step: 0.05, to: box)
        addCheck(.depthOfField, label: "Depth of field", to: box)
        addSlider(.depthOfFieldStrength, label: "DOF strength", range: 0...5, step: 0.05, to: box)
        addSeparator(to: box)

        let resetBtn = gtk_button_new_with_label("Reset to Neutral")
        gtk_widget_set_hexpand(resetBtn, 1)
        gtk_box_append(box, resetBtn)

        let resetCallback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let panel = Unmanaged<GTKControlPanel>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { panel.resetPBRControls() }
        }
        g_signal_connect_data(
            resetBtn,
            "clicked",
            unsafeBitCast(resetCallback, to: (@convention(c) () -> Void).self),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            0
        )

        syncWidgetsToSettings()
    }

    private func addSectionHeader(_ title: String, to box: OpaquePointer) {
        guard let label = gtk_label_new(title) else { return }
        gtk_box_append(box, label)
    }

    private func addSeparator(to box: OpaquePointer) {
        guard let separator = gtk_separator_new(GTK_ORIENTATION_HORIZONTAL) else { return }
        gtk_box_append(box, separator)
    }

    @discardableResult
    private func addSlider(
        _ control: PanelControl,
        label: String,
        range: ClosedRange<Double>,
        step: Double,
        to box: OpaquePointer
    ) -> OpaquePointer? {
        if let caption = gtk_label_new(label) {
            gtk_box_append(box, caption)
        }
        guard let scale = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, range.lowerBound, range.upperBound, step) else {
            return nil
        }
        gtk_widget_set_hexpand(scale, 1)
        gtk_scale_set_draw_value(scale, 1)
        gtk_box_append(box, scale)
        panelWidgets[control] = scale

        let callback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { widget, userData in
            let value = gtk_range_get_value(widget)
            let widgetKey = UInt(bitPattern: widget)
            guard let userData else { return }
            let panel = Unmanaged<GTKControlPanel>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { panel.applySlider(widgetKey, value) }
        }
        g_signal_connect_data(
            scale,
            "value-changed",
            unsafeBitCast(callback, to: (@convention(c) () -> Void).self),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            0
        )
        return scale
    }

    @discardableResult
    private func addCheck(_ control: PanelControl, label: String, to box: OpaquePointer) -> OpaquePointer? {
        guard let check = gtk_check_button_new_with_label(label) else { return nil }
        gtk_box_append(box, check)
        panelWidgets[control] = check

        let callback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { widget, userData in
            let active = gtk_check_button_get_active(widget) != 0
            let widgetKey = UInt(bitPattern: widget)
            guard let userData else { return }
            let panel = Unmanaged<GTKControlPanel>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { panel.applyToggle(widgetKey, active) }
        }
        g_signal_connect_data(
            check,
            "toggled",
            unsafeBitCast(callback, to: (@convention(c) () -> Void).self),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            0
        )
        return check
    }

    @discardableResult
    private func addDropdown(_ control: PanelControl, label: String, items: [String], to box: OpaquePointer) -> OpaquePointer? {
        if let caption = gtk_label_new(label) {
            gtk_box_append(box, caption)
        }
        guard !items.isEmpty else { return nil }

        let copies: [UnsafeMutablePointer<CChar>?] = items.map { strdup($0) }
        defer { copies.forEach { free($0) } }
        var borrowed: [UnsafePointer<CChar>?] = copies.map { UnsafePointer($0) }
        borrowed.append(nil)

        let dropdown = borrowed.withUnsafeBufferPointer { buffer in
            gtk_drop_down_new_from_strings(buffer.baseAddress)
        }
        guard let dropdown else { return nil }

        gtk_widget_set_hexpand(dropdown, 1)
        gtk_box_append(box, dropdown)
        panelWidgets[control] = dropdown

        let callback: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { widget, _, userData in
            let index = gtk_drop_down_get_selected(widget)
            let widgetKey = UInt(bitPattern: widget)
            guard let userData else { return }
            let panel = Unmanaged<GTKControlPanel>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { panel.applyDropdown(widgetKey, index) }
        }
        g_signal_connect_data(
            dropdown,
            "notify::selected",
            unsafeBitCast(callback, to: (@convention(c) () -> Void).self),
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            0
        )
        return dropdown
    }

    private func control(forWidgetKey key: UInt) -> PanelControl? {
        panelWidgets.first(where: { UInt(bitPattern: $0.value) == key })?.key
    }

    private func applySlider(_ widgetKey: UInt, _ value: Double) {
        guard let control = control(forWidgetKey: widgetKey) else { return }
        let f = Float(value)
        switch control {
        case .outlineThickness: scene?.setOutlineThickness(f)
        case .outlineFlowSpeed: scene?.setOutlineFlowSpeed(f)
        case .outlineGradientScale: scene?.setOutlineGradientScale(f)
        case .outlineNoiseScale: scene?.setOutlineNoiseScale(f)
        case .halftoneScale: scene?.setHalftoneScale(f)
        case .halftoneAngle: scene?.setHalftoneAngle(f)
        case .halftoneDotSize: scene?.setHalftoneDotSize(f)
        case .halftoneHardness: scene?.setHalftoneHardness(f)
        case .halftoneBlend: scene?.setHalftoneBlend(f)
        case .keyIntensity: controller.mutate { $0.keyLightIntensity = f }
        case .fillIntensity: controller.mutate { $0.fillLightIntensity = f }
        case .ambient: controller.mutate { $0.ambientIntensity = f }
        case .exposure: controller.mutate { $0.exposure = f }
        case .contrast: controller.mutate { $0.contrast = f }
        case .saturation: controller.mutate { $0.saturation = f }
        case .vibrance: controller.mutate { $0.vibrance = f }
        case .whiteBalance: controller.mutate { $0.whiteBalance = f }
        case .bloomStrength: controller.mutate { $0.bloomStrength = f }
        case .vignetteStrength: controller.mutate { $0.vignetteStrength = f }
        case .occlusionIntensity: controller.mutate { $0.occlusionIntensity = f }
        case .occlusionRadius: controller.mutate { $0.occlusionRadius = f }
        case .reflectionDistance: controller.mutate { $0.reflectionMaxDistance = f }
        case .depthOfFieldStrength: controller.mutate { $0.depthOfFieldStrength = f }
        default: break
        }
    }

    private func applyToggle(_ widgetKey: UInt, _ active: Bool) {
        guard let control = control(forWidgetKey: widgetKey) else { return }
        switch control {
        case .shadows: controller.mutate { $0.shadowsEnabled = active }
        case .dithering: controller.mutate { $0.dithering = active }
        case .bloom: controller.mutate { $0.bloomEnabled = active }
        case .vignette: controller.mutate { $0.vignetteEnabled = active }
        case .occlusion: controller.mutate { $0.occlusionEnabled = active }
        case .reflections: controller.mutate { $0.reflectionsEnabled = active }
        case .depthOfField: controller.mutate { $0.depthOfFieldEnabled = active }
        default: break
        }
    }

    private func applyDropdown(_ widgetKey: UInt, _ index: UInt32) {
        guard let control = control(forWidgetKey: widgetKey) else { return }
        let i = Int(index)
        switch control {
        case .shadingMode:
            let all = GTKSceneController.ShadingMode.allCases
            guard i >= 0, i < all.count else { return }
            scene?.setShadingMode(all[i])
        case .outlineGradientMode:
            let all = FilamentToonOutlineMaterial.GradientMode.allCases
            guard i >= 0, i < all.count else { return }
            scene?.setOutlineGradientMode(all[i])
        case .halftonePreset:
            switch i {
            case 1: scene?.applyHalftonePreset(FilamentToonMaterial.spiderVersePreset)
            case 2: scene?.applyHalftonePreset(FilamentToonMaterial.mangaScreentonePreset)
            case 3: scene?.applyHalftonePreset(FilamentToonMaterial.cmykNewspaperPreset)
            case 4: scene?.applyHalftonePreset(FilamentToonMaterial.comicHatchingPreset)
            default: break
            }
            syncStylizedWidgets()
        case .halftoneMode:
            let all = FilamentToonMaterial.HalftoneMode.allCases
            guard i >= 0, i < all.count else { return }
            scene?.setHalftoneMode(all[i])
        case .halftoneTarget:
            let all = FilamentToonMaterial.HalftoneTarget.allCases
            guard i >= 0, i < all.count else { return }
            scene?.setHalftoneTarget(all[i])
        case .toneMapping:
            let all = FilamentToneMapping.allCases
            guard i >= 0, i < all.count else { return }
            controller.mutate { $0.toneMapping = all[i] }
        case .antiAliasing:
            let all = FilamentAntiAliasing.allCases
            guard i >= 0, i < all.count else { return }
            controller.mutate { $0.antiAliasing = all[i] }
        case .hdrQuality:
            let all = FilamentHDRQuality.allCases
            guard i >= 0, i < all.count else { return }
            controller.mutate { $0.hdrQuality = all[i] }
        case .occlusionMode:
            let all = FilamentOcclusionMode.allCases
            guard i >= 0, i < all.count else { return }
            controller.mutate { $0.occlusionMode = all[i] }
        case .msaa:
            guard i >= 0, i < Self.msaaOptions.count else { return }
            let count = Int(Self.msaaOptions[i]) ?? 1
            controller.mutate { $0.multiSampleCount = count }
        default: break
        }
    }

    private func resetPBRControls() {
        controller.reset()
        syncWidgetsToSettings()
        print("[GTK4Demo] PBR settings reset to neutral.")
    }

    func syncWidgetsToSettings() {
        let settings = controller.settings

        let sliders: [(PanelControl, Double)] = [
            (.keyIntensity, Double(settings.keyLightIntensity)),
            (.fillIntensity, Double(settings.fillLightIntensity)),
            (.ambient, Double(settings.ambientIntensity)),
            (.exposure, Double(settings.exposure)),
            (.contrast, Double(settings.contrast)),
            (.saturation, Double(settings.saturation)),
            (.vibrance, Double(settings.vibrance)),
            (.whiteBalance, Double(settings.whiteBalance)),
            (.bloomStrength, Double(settings.bloomStrength)),
            (.vignetteStrength, Double(settings.vignetteStrength)),
            (.occlusionIntensity, Double(settings.occlusionIntensity)),
            (.occlusionRadius, Double(settings.occlusionRadius)),
            (.reflectionDistance, Double(settings.reflectionMaxDistance)),
            (.depthOfFieldStrength, Double(settings.depthOfFieldStrength))
        ]
        for (control, value) in sliders {
            guard let scale = panelWidgets[control] else { continue }
            gtk_range_set_value(scale, value)
        }

        let toggles: [(PanelControl, Bool)] = [
            (.shadows, settings.shadowsEnabled),
            (.dithering, settings.dithering),
            (.bloom, settings.bloomEnabled),
            (.vignette, settings.vignetteEnabled),
            (.occlusion, settings.occlusionEnabled),
            (.reflections, settings.reflectionsEnabled),
            (.depthOfField, settings.depthOfFieldEnabled)
        ]
        for (control, active) in toggles {
            guard let check = panelWidgets[control] else { continue }
            gtk_check_button_set_active(check, active ? 1 : 0)
        }

        func select<T: RawRepresentable>(_ widget: OpaquePointer?, _ cases: [T], _ value: T) where T.RawValue == UInt32 {
            guard let widget else { return }
            let index = cases.firstIndex(where: { $0.rawValue == value.rawValue }) ?? 0
            gtk_drop_down_set_selected(widget, UInt32(index))
        }

        select(panelWidgets[.toneMapping], FilamentToneMapping.allCases, settings.toneMapping)
        select(panelWidgets[.antiAliasing], FilamentAntiAliasing.allCases, settings.antiAliasing)
        select(panelWidgets[.hdrQuality], FilamentHDRQuality.allCases, settings.hdrQuality)
        select(panelWidgets[.occlusionMode], FilamentOcclusionMode.allCases, settings.occlusionMode)

        if let dropdown = panelWidgets[.msaa] {
            let index = Self.msaaOptions.firstIndex(where: { (Int($0) ?? 1) == settings.multiSampleCount }) ?? 0
            gtk_drop_down_set_selected(dropdown, UInt32(index))
        }

        syncStylizedWidgets()
    }

    private func syncStylizedWidgets() {
        guard let scene else { return }
        if let dd = panelWidgets[.shadingMode] {
            gtk_drop_down_set_selected(dd, UInt32(scene.currentShadingMode.rawValue))
        }
        if let outline = scene.outlineMaterial {
            if let dd = panelWidgets[.outlineGradientMode] {
                gtk_drop_down_set_selected(dd, UInt32(outline.gradientMode.rawValue))
            }
            if let scale = panelWidgets[.outlineThickness] {
                gtk_range_set_value(scale, Double(outline.outlineThickness))
            }
            if let scale = panelWidgets[.outlineFlowSpeed] {
                gtk_range_set_value(scale, Double(outline.flowAnimationSpeed))
            }
            if let scale = panelWidgets[.outlineGradientScale] {
                gtk_range_set_value(scale, Double(outline.gradientScale))
            }
            if let scale = panelWidgets[.outlineNoiseScale] {
                gtk_range_set_value(scale, Double(outline.noiseScale))
            }
        }
        if let toon = scene.toonMaterial {
            if let dd = panelWidgets[.halftoneMode] {
                gtk_drop_down_set_selected(dd, UInt32(toon.halftoneMode.rawValue))
            }
            if let dd = panelWidgets[.halftoneTarget] {
                gtk_drop_down_set_selected(dd, UInt32(toon.halftoneTarget.rawValue))
            }
            if let scale = panelWidgets[.halftoneScale] {
                gtk_range_set_value(scale, Double(toon.halftoneScale))
            }
            if let scale = panelWidgets[.halftoneAngle] {
                gtk_range_set_value(scale, Double(toon.halftoneAngle))
            }
            if let scale = panelWidgets[.halftoneDotSize] {
                gtk_range_set_value(scale, Double(toon.halftoneDotSize))
            }
            if let scale = panelWidgets[.halftoneHardness] {
                gtk_range_set_value(scale, Double(toon.halftoneHardness))
            }
            if let scale = panelWidgets[.halftoneBlend] {
                gtk_range_set_value(scale, Double(toon.halftoneBlend))
            }
        }
    }
}
