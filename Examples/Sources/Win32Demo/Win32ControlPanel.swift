import Foundation
import WinSDK
import Filament

/// Control identifiers stored in each Win32 control's `GWLP_ID`.
enum ControlID {
    // Trackbars
    static let keyLight = 1101
    static let fillLight = 1102
    static let ambient = 1103
    static let exposure = 1104
    static let contrast = 1105
    static let saturation = 1106
    static let whiteBalance = 1107
    static let bloomStrength = 1108

    // Checkboxes
    static let shadows = 1201
    static let bloom = 1202
    static let vignette = 1203
    static let occlusion = 1204
    static let reflections = 1205
    static let depthOfField = 1206
    static let dithering = 1207

    // Combo boxes
    static let toneMapping = 1301
    static let antiAliasing = 1302
    static let multiSampleCount = 1303
    static let hdrQuality = 1304
    static let occlusionMode = 1305

    // Buttons
    static let resetPBR = 1401
    static let openModel = 1402
    static let resetView = 1403
}

private let msaaSampleCounts: [Int] = [1, 2, 4, 8]

private struct SliderSpec {
    let id: Int
    let title: String
    let min: Int
    let max: Int
    let initial: Int
}

private enum PanelColumn {
    case full
    case trailing
}

private struct PanelItem {
    let hwnd: HWND
    let y: Int32
    let height: Int32
    let column: PanelColumn
}

private struct PanelSlider {
    let spec: SliderSpec
    let label: HWND
    let value: HWND
    let track: HWND
    let y: Int32
    let height: Int32
}

/// Manages the stock Win32 side control panel (`STATIC`, `BUTTON`, `COMBOBOX`, `msctls_trackbar32`).
@MainActor
final class Win32ControlPanel {
    static let panelWidth: Int32 = 320

    private static let staticClassName = "STATIC"
    private static let buttonClassName = "BUTTON"
    private static let comboClassName = "COMBOBOX"
    private static let trackbarClassName = "msctls_trackbar32"

    private static let sliderSpecs: [SliderSpec] = {
        let neutral = FilamentPBRSettings.neutral
        return [
            SliderSpec(id: ControlID.keyLight, title: "Key light",
                       min: 0, max: 200_000, initial: Int(neutral.keyLightIntensity)),
            SliderSpec(id: ControlID.fillLight, title: "Fill light",
                       min: 0, max: 200_000, initial: Int(neutral.fillLightIntensity)),
            SliderSpec(id: ControlID.ambient, title: "Ambient",
                       min: 0, max: 100_000, initial: Int(neutral.ambientIntensity)),
            SliderSpec(id: ControlID.exposure, title: "Exposure",
                       min: 10, max: 400, initial: Int((neutral.exposure * 100).rounded())),
            SliderSpec(id: ControlID.contrast, title: "Contrast",
                       min: 0, max: 200, initial: Int((neutral.contrast * 100).rounded())),
            SliderSpec(id: ControlID.saturation, title: "Saturation",
                       min: 0, max: 200, initial: Int((neutral.saturation * 100).rounded())),
            SliderSpec(id: ControlID.whiteBalance, title: "White balance",
                       min: -100, max: 100, initial: Int((neutral.whiteBalance * 100).rounded())),
            SliderSpec(id: ControlID.bloomStrength, title: "Bloom strength",
                       min: 0, max: 100, initial: Int((neutral.bloomStrength * 100).rounded())),
        ]
    }()

    let panelHwnd: HWND
    private var panelItems: [PanelItem] = []
    private var panelSliders: [PanelSlider] = []

    init?(parent: HWND, panelClassName: String) {
        let created: HWND? = panelClassName.withCString(encodedAs: UTF16.self) { classWide in
            CreateWindowExW(
                DWORD(WS_EX_CLIENTEDGE),
                classWide,
                nil,
                DWORD(WS_CHILD | WS_VISIBLE),
                0,
                0,
                Self.panelWidth,
                1,
                parent,
                nil,
                GetModuleHandleW(nil),
                nil
            )
        }
        guard let panelHwnd = created else { return nil }
        self.panelHwnd = panelHwnd
        buildControls()
    }

    // MARK: - Construction & Layout

    private func buildControls() {
        panelItems.removeAll()
        panelSliders.removeAll()

        var y: Int32 = 10

        func advance(_ height: Int32, _ spacing: Int32 = 6) {
            y += height + spacing
        }

        func header(_ text: String) {
            guard let control = makeControl(
                className: Self.staticClassName,
                style: WS_CHILD | WS_VISIBLE | SS_CENTERIMAGE,
                text: text,
                id: 0,
                height: 24
            ) else { return }
            panelItems.append(PanelItem(hwnd: control, y: y, height: 24, column: .full))
            advance(24, 4)
        }

        func slider(_ spec: SliderSpec) {
            guard
                let label = makeControl(
                    className: Self.staticClassName,
                    style: WS_CHILD | WS_VISIBLE | SS_LEFT,
                    text: spec.title,
                    id: 0,
                    height: 20
                ),
                let value = makeControl(
                    className: Self.staticClassName,
                    style: WS_CHILD | WS_VISIBLE | SS_RIGHT | SS_CENTERIMAGE,
                    text: "",
                    id: 0,
                    height: 20
                ),
                let track = makeControl(
                    className: Self.trackbarClassName,
                    style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | TBS_HORZ | TBS_AUTOTICKS | TBS_ENDSEL,
                    text: nil,
                    id: spec.id,
                    height: 22
                )
            else { return }

            _ = sendMessage(track, TBM_SETRANGEMIN, 0, Int64(spec.min))
            _ = sendMessage(track, TBM_SETRANGEMAX, UInt64(kTrue), Int64(spec.max))
            _ = sendMessage(track, TBM_SETPOS, UInt64(kTrue), Int64(spec.initial))

            let resolved = PanelSlider(spec: spec, label: label, value: value, track: track, y: y, height: 20)
            panelSliders.append(resolved)
            setValueLabel(resolved, position: spec.initial)
            advance(22)
        }

        func checkbox(_ id: Int, _ title: String, _ checked: Bool) {
            guard let control = makeControl(
                className: Self.buttonClassName,
                style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_AUTOCHECKBOX,
                text: title,
                id: id,
                height: 20
            ) else { return }
            _ = sendMessage(control, BM_SETCHECK, UInt64(checked ? BST_CHECKED : BST_UNCHECKED), 0)
            panelItems.append(PanelItem(hwnd: control, y: y, height: 20, column: .full))
            advance(20)
        }

        func combo(_ id: Int, _ title: String, items: [String], selection: Int) {
            guard
                let label = makeControl(
                    className: Self.staticClassName,
                    style: WS_CHILD | WS_VISIBLE | SS_LEFT,
                    text: title,
                    id: 0,
                    height: 20
                ),
                let control = makeControl(
                    className: Self.comboClassName,
                    style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_VSCROLL | CBS_DROPDOWNLIST,
                    text: nil,
                    id: id,
                    height: 200
                )
            else { return }

            for item in items {
                item.withCString(encodedAs: UTF16.self) { textWide in
                    sendMessage(control, CB_ADDSTRING, textWide)
                }
            }
            _ = sendMessage(control, CB_SETCURSEL, UInt64(max(0, selection)))

            panelItems.append(PanelItem(hwnd: label, y: y + 2, height: 16, column: .full))
            panelItems.append(PanelItem(hwnd: control, y: y, height: 200, column: .trailing))
            advance(22)
        }

        let neutral = FilamentPBRSettings.neutral

        if let openButton = makeControl(
            className: Self.buttonClassName,
            style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
            text: "Open Model (.glb)…",
            id: ControlID.openModel,
            height: 26
        ) {
            panelItems.append(PanelItem(hwnd: openButton, y: y, height: 26, column: .full))
            advance(26, 4)
        }

        if let resetViewBtn = makeControl(
            className: Self.buttonClassName,
            style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
            text: "Reset View",
            id: ControlID.resetView,
            height: 24
        ) {
            panelItems.append(PanelItem(hwnd: resetViewBtn, y: y, height: 24, column: .full))
            advance(24, 6)
        }

        header("Lighting")
        for spec in Self.sliderSpecs.prefix(3) { slider(spec) }
        checkbox(ControlID.shadows, "Shadows", neutral.shadowsEnabled)

        header("Color")
        for spec in Self.sliderSpecs[3...6] { slider(spec) }
        combo(ControlID.toneMapping, "Tone mapping",
              items: FilamentToneMapping.allCases.map(\.displayName),
              selection: index(of: neutral.toneMapping, in: FilamentToneMapping.allCases))

        header("Anti-Aliasing")
        combo(ControlID.antiAliasing, "AA",
              items: FilamentAntiAliasing.allCases.map(\.displayName),
              selection: index(of: neutral.antiAliasing, in: FilamentAntiAliasing.allCases))
        combo(ControlID.multiSampleCount, "MSAA",
              items: msaaSampleCounts.map { String($0) },
              selection: msaaSampleCounts.firstIndex(of: neutral.multiSampleCount) ?? 0)
        combo(ControlID.hdrQuality, "HDR quality",
              items: FilamentHDRQuality.allCases.map(\.displayName),
              selection: index(of: neutral.hdrQuality, in: FilamentHDRQuality.allCases))
        checkbox(ControlID.dithering, "Dithering", neutral.dithering)

        header("Post-processing")
        checkbox(ControlID.bloom, "Bloom", neutral.bloomEnabled)
        if let spec = Self.sliderSpecs.first(where: { $0.id == ControlID.bloomStrength }) {
            slider(spec)
        }
        checkbox(ControlID.vignette, "Vignette", neutral.vignetteEnabled)
        checkbox(ControlID.occlusion, "Ambient occlusion", neutral.occlusionEnabled)
        combo(ControlID.occlusionMode, "Occlusion mode",
              items: FilamentOcclusionMode.allCases.map(\.displayName),
              selection: index(of: neutral.occlusionMode, in: FilamentOcclusionMode.allCases))
        checkbox(ControlID.reflections, "Reflections", neutral.reflectionsEnabled)
        checkbox(ControlID.depthOfField, "Depth of field", neutral.depthOfFieldEnabled)

        if let button = makeControl(
            className: Self.buttonClassName,
            style: WS_CHILD | WS_VISIBLE | WS_TABSTOP | BS_PUSHBUTTON,
            text: "Reset PBR",
            id: ControlID.resetPBR,
            height: 26
        ) {
            panelItems.append(PanelItem(hwnd: button, y: y + 4, height: 26, column: .full))
        }

        layoutControls()
    }

    func layoutControls() {
        var rect = RECT()
        guard win32GetClientRect(UnsafeRawPointer(panelHwnd), &rect) != 0 else { return }

        let pad: Int32 = 10
        let gap: Int32 = 4
        let labelWidth: Int32 = 76
        let valueWidth: Int32 = 66
        let contentWidth = max(1, (rect.right - rect.left) - pad * 2)
        let controlX = pad + labelWidth + gap
        let controlWidth = max(1, contentWidth - labelWidth - gap)

        for item in panelItems {
            switch item.column {
            case .full:
                _ = win32MoveWindow(UnsafeRawPointer(item.hwnd), pad, item.y, contentWidth, item.height, kTrue)
            case .trailing:
                _ = win32MoveWindow(UnsafeRawPointer(item.hwnd), controlX, item.y, controlWidth, item.height, kTrue)
            }
        }

        let trackWidth = max(1, contentWidth - labelWidth - valueWidth - gap * 2)
        for slider in panelSliders {
            _ = win32MoveWindow(UnsafeRawPointer(slider.label), pad, slider.y + 2, labelWidth, slider.height, kTrue)
            _ = win32MoveWindow(UnsafeRawPointer(slider.track), controlX, slider.y, trackWidth, slider.height, kTrue)
            _ = win32MoveWindow(UnsafeRawPointer(slider.value), controlX + trackWidth + gap, slider.y + 2, valueWidth, slider.height, kTrue)
        }
    }

    private func makeControl(
        className: String,
        style: UInt32,
        text: String?,
        id: Int,
        height: Int32
    ) -> HWND? {
        className.withCString(encodedAs: UTF16.self) { classWide in
            let created: HWND?
            if let text {
                created = text.withCString(encodedAs: UTF16.self) { textWide in
                    CreateWindowExW(0, classWide, textWide, DWORD(style), 0, 0, 1, height, panelHwnd, nil, GetModuleHandleW(nil), nil)
                }
            } else {
                created = CreateWindowExW(0, classWide, nil, DWORD(style), 0, 0, 1, height, panelHwnd, nil, GetModuleHandleW(nil), nil)
            }
            guard let created else { return nil }
            if id != 0 {
                _ = win32SetWindowLongW(UnsafeRawPointer(created), GWLP_ID, Int32(id))
            }
            return created
        }
    }

    private func index<T: Equatable>(of value: T, in all: [T]) -> Int {
        all.firstIndex(of: value) ?? 0
    }

    // MARK: - Event Handling & Sync

    func handleTrackbar(id: Int, position: Int, pbr: FilamentPBRController?) {
        guard let slider = panelSliders.first(where: { $0.spec.id == id }) else { return }
        setValueLabel(slider, position: position)

        let value = Self.decodeSlider(id: id, position: position)
        switch id {
        case ControlID.keyLight: pbr?.mutate { $0.keyLightIntensity = value }
        case ControlID.fillLight: pbr?.mutate { $0.fillLightIntensity = value }
        case ControlID.ambient: pbr?.mutate { $0.ambientIntensity = value }
        case ControlID.exposure: pbr?.mutate { $0.exposure = value }
        case ControlID.contrast: pbr?.mutate { $0.contrast = value }
        case ControlID.saturation: pbr?.mutate { $0.saturation = value }
        case ControlID.whiteBalance: pbr?.mutate { $0.whiteBalance = value }
        case ControlID.bloomStrength: pbr?.mutate { $0.bloomStrength = value }
        default: break
        }
    }

    func handleCheckbox(id: Int, checked: Bool, pbr: FilamentPBRController?) {
        guard let pbr else { return }
        switch id {
        case ControlID.shadows: pbr.mutate { $0.shadowsEnabled = checked }
        case ControlID.bloom: pbr.mutate { $0.bloomEnabled = checked }
        case ControlID.vignette: pbr.mutate { $0.vignetteEnabled = checked }
        case ControlID.occlusion: pbr.mutate { $0.occlusionEnabled = checked }
        case ControlID.reflections: pbr.mutate { $0.reflectionsEnabled = checked }
        case ControlID.depthOfField: pbr.mutate { $0.depthOfFieldEnabled = checked }
        case ControlID.dithering: pbr.mutate { $0.dithering = checked }
        default: break
        }
    }

    func handleCombo(id: Int, selection: Int, pbr: FilamentPBRController?) {
        guard let pbr, selection >= 0 else { return }
        switch id {
        case ControlID.toneMapping:
            let cases = FilamentToneMapping.allCases
            guard selection < cases.count else { return }
            pbr.mutate { $0.toneMapping = cases[selection] }
        case ControlID.antiAliasing:
            let cases = FilamentAntiAliasing.allCases
            guard selection < cases.count else { return }
            pbr.mutate { $0.antiAliasing = cases[selection] }
        case ControlID.hdrQuality:
            let cases = FilamentHDRQuality.allCases
            guard selection < cases.count else { return }
            pbr.mutate { $0.hdrQuality = cases[selection] }
        case ControlID.occlusionMode:
            let cases = FilamentOcclusionMode.allCases
            guard selection < cases.count else { return }
            pbr.mutate { $0.occlusionMode = cases[selection] }
        case ControlID.multiSampleCount:
            guard selection < msaaSampleCounts.count else { return }
            pbr.mutate { $0.multiSampleCount = msaaSampleCounts[selection] }
        default: break
        }
    }

    func handleResetPBR(pbr: FilamentPBRController?) {
        pbr?.reset()
        let neutral = pbr?.settings ?? .neutral

        for slider in panelSliders {
            let position = Self.encodeSlider(id: slider.spec.id, settings: neutral)
            _ = sendMessage(slider.track, TBM_SETPOS, UInt64(kTrue), Int64(position))
            setValueLabel(slider, position: position)
        }

        func control(withID id: Int) -> HWND? {
            panelItems.first(where: { Int(win32GetDlgCtrlID(UnsafeRawPointer($0.hwnd))) == id })?.hwnd
        }

        func setCheck(_ id: Int, _ checked: Bool) {
            guard let control = control(withID: id) else { return }
            _ = sendMessage(control, BM_SETCHECK, UInt64(checked ? BST_CHECKED : BST_UNCHECKED), 0)
        }

        func setCursel(_ id: Int, _ selection: Int) {
            guard let control = control(withID: id) else { return }
            _ = sendMessage(control, CB_SETCURSEL, UInt64(max(0, selection)))
        }

        setCheck(ControlID.shadows, neutral.shadowsEnabled)
        setCheck(ControlID.bloom, neutral.bloomEnabled)
        setCheck(ControlID.vignette, neutral.vignetteEnabled)
        setCheck(ControlID.occlusion, neutral.occlusionEnabled)
        setCheck(ControlID.reflections, neutral.reflectionsEnabled)
        setCheck(ControlID.depthOfField, neutral.depthOfFieldEnabled)
        setCheck(ControlID.dithering, neutral.dithering)

        setCursel(ControlID.toneMapping, index(of: neutral.toneMapping, in: FilamentToneMapping.allCases))
        setCursel(ControlID.antiAliasing, index(of: neutral.antiAliasing, in: FilamentAntiAliasing.allCases))
        setCursel(ControlID.hdrQuality, index(of: neutral.hdrQuality, in: FilamentHDRQuality.allCases))
        setCursel(ControlID.occlusionMode, index(of: neutral.occlusionMode, in: FilamentOcclusionMode.allCases))
        setCursel(ControlID.multiSampleCount, msaaSampleCounts.firstIndex(of: neutral.multiSampleCount) ?? 0)

        print("[Win32Demo] PBR settings reset to neutral.")
    }

    // MARK: - Slider Encoding / Decoding

    static func decodeSlider(id: Int, position: Int) -> Float {
        switch id {
        case ControlID.exposure, ControlID.contrast, ControlID.saturation, ControlID.bloomStrength, ControlID.whiteBalance:
            return Float(position) / 100.0
        default:
            return Float(position)
        }
    }

    static func encodeSlider(id: Int, settings: FilamentPBRSettings) -> Int {
        switch id {
        case ControlID.exposure: return Int((settings.exposure * 100).rounded())
        case ControlID.contrast: return Int((settings.contrast * 100).rounded())
        case ControlID.saturation: return Int((settings.saturation * 100).rounded())
        case ControlID.bloomStrength: return Int((settings.bloomStrength * 100).rounded())
        case ControlID.whiteBalance: return Int((settings.whiteBalance * 100).rounded())
        case ControlID.ambient: return Int(settings.ambientIntensity)
        case ControlID.keyLight: return Int(settings.keyLightIntensity)
        case ControlID.fillLight: return Int(settings.fillLightIntensity)
        default: return 0
        }
    }

    private func setValueLabel(_ slider: PanelSlider, position: Int) {
        let text: String
        switch slider.spec.id {
        case ControlID.keyLight, ControlID.fillLight, ControlID.ambient:
            text = Self.compact(position) + " lx"
        case ControlID.exposure:
            text = String(format: "%.2fx", Double(position) / 100.0)
        case ControlID.contrast, ControlID.saturation, ControlID.bloomStrength:
            text = String(format: "%.2f", Double(position) / 100.0)
        case ControlID.whiteBalance:
            text = String(format: "%+.2f", Double(position) / 100.0)
        default:
            text = "\(position)"
        }
        setText(slider.value, text)
    }

    private static func compact(_ value: Int) -> String {
        if value >= 1000 { return "\(value / 1000)k" }
        return "\(value)"
    }
}
