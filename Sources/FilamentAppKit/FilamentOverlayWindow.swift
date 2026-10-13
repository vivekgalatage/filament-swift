import AppKit
import Filament
import QuartzCore

/// A floating, borderless, transparent desktop overlay window backed by Filament and Metal.
///
/// Provides true alpha-composited 3D rendering directly on the macOS desktop, matching the
/// companion overlay window capabilities of Linux (`FilamentGTK`) and Windows (`FilamentWin32`).
///
/// Features:
/// - **Alpha Transparency**: 3D models float directly on the desktop with transparent background.
/// - **Desktop Floating**: Stays on top of all application windows (`.floating` level).
/// - **Interactive Manipulation**: Drag from anywhere on the window background to reposition;
///   orbit, pan, and zoom the 3D model using mouse or trackpad gestures.
/// - **Click-Through Support**: Toggle `isClickThrough = true` to pass all mouse clicks to desktop windows beneath.
/// - **Full Shading Parity**: Supports Standard PBR, Toon Cel, Inked Outline, and Outline-Only transparent modes.
@MainActor
public final class FilamentOverlayWindow: NSObject, NSWindowDelegate {
    public let window: NSWindow
    public let filamentView: FilamentView
    public let model: FilamentModel
    public let outlineModel: FilamentModel
    public let pbr: FilamentPBRController
    public let camera: FilamentOrbitCamera

    private var barView: NSVisualEffectView?

    public var isClickThrough: Bool {
        get { window.ignoresMouseEvents }
        set {
            window.ignoresMouseEvents = newValue
            barView?.alphaValue = newValue ? 0.4 : 1.0
        }
    }

    public var onClose: (() -> Void)?

    private(set) var currentModelURL: URL?
    private(set) var toonMaterial: FilamentToonMaterial?
    private(set) var outlineMaterial: FilamentToonOutlineMaterial?
    private(set) var depthMaskMaterial: FilamentDepthMaskMaterial?
    private(set) var currentShadingMode: Int = 0 // 0: PBR, 1: Cel, 2: Toon+Out, 3: PBR+Out, 4: OutOnly

    private var renderTimer: Timer?
    private var lastFrameTime: CFTimeInterval = CACurrentMediaTime()
    private var animationTime: Float = 0.0
    private var isAnimationPlaying: Bool = true

    public init(
        width: CGFloat = 420,
        height: CGFloat = 520,
        initialOrigin: CGPoint? = nil,
        engine: FilamentEngine? = nil
    ) {
        let eng = engine ?? FilamentEngine(backend: .metal, config: .largeModelPreset)
        eng.setTransparent(true)

        let origin: CGPoint
        if let initialOrigin {
            origin = initialOrigin
        } else if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            origin = CGPoint(x: sf.maxX - width - 40, y: sf.minY + 60)
        } else {
            origin = CGPoint(x: 100, y: 100)
        }

        let contentRect = NSRect(origin: origin, size: CGSize(width: width, height: height))
        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.level = .floating
        win.isMovableByWindowBackground = true
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.minSize = NSSize(width: 180, height: 180)

        self.window = win
        self.filamentView = FilamentView(frame: NSRect(origin: .zero, size: contentRect.size), engine: eng)
        self.filamentView.isTransparent = true
        self.filamentView.autoresizingMask = [.width, .height]

        self.pbr = FilamentPBRController(engine: eng)
        self.model = FilamentModel(engine: eng)
        self.outlineModel = FilamentModel(engine: eng)
        self.camera = FilamentOrbitCamera(engine: eng, distance: 3.2)
        self.filamentView.orbitCamera = camera

        super.init()
        win.delegate = self

        guard let contentView = win.contentView else { return }
        contentView.addSubview(filamentView)

        setupFloatingControls(in: contentView)
        ensureMaterials()
        startRenderLoop()
    }

    private final class OverlayDragGripView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    private func setupFloatingControls(in contentView: NSView) {
        // Floating pill bar for Drag Grip, Close, Orbit, and Reset
        let bar = NSVisualEffectView()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.material = .hudWindow
        bar.state = .active
        bar.wantsLayer = true
        bar.layer?.cornerRadius = 14
        bar.layer?.masksToBounds = true
        self.barView = bar

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6

        // Drag Grip handle
        let grip = OverlayDragGripView()
        grip.translatesAutoresizingMaskIntoConstraints = false
        let gripLabel = NSTextField(labelWithString: "⠿")
        gripLabel.font = NSFont.systemFont(ofSize: 11)
        gripLabel.textColor = .secondaryLabelColor
        gripLabel.toolTip = "Drag to Move Floating Overlay"
        gripLabel.translatesAutoresizingMaskIntoConstraints = false
        grip.addSubview(gripLabel)
        NSLayoutConstraint.activate([
            gripLabel.centerXAnchor.constraint(equalTo: grip.centerXAnchor),
            gripLabel.centerYAnchor.constraint(equalTo: grip.centerYAnchor),
            grip.widthAnchor.constraint(equalToConstant: 14),
            grip.heightAnchor.constraint(equalToConstant: 22),
        ])
        stack.addArrangedSubview(grip)

        // Close button
        let closeBtn = NSButton(title: "✕", target: self, action: #selector(onCloseClicked))
        closeBtn.bezelStyle = .circular
        closeBtn.controlSize = .mini
        closeBtn.isBordered = false
        closeBtn.font = NSFont.systemFont(ofSize: 11, weight: .bold)
        closeBtn.toolTip = "Close Overlay"
        stack.addArrangedSubview(closeBtn)

        // Orbit toggle button
        let orbitBtn = NSButton(title: "⟳", target: self, action: #selector(onOrbitClicked))
        orbitBtn.bezelStyle = .circular
        orbitBtn.controlSize = .mini
        orbitBtn.isBordered = false
        orbitBtn.toolTip = "Toggle Turntable Orbit"
        stack.addArrangedSubview(orbitBtn)

        // Reset view button
        let resetBtn = NSButton(title: "⊙", target: self, action: #selector(onResetCameraClicked))
        resetBtn.bezelStyle = .circular
        resetBtn.controlSize = .mini
        resetBtn.isBordered = false
        resetBtn.toolTip = "Reset Camera View"
        stack.addArrangedSubview(resetBtn)

        bar.addSubview(stack)
        contentView.addSubview(bar)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 28),

            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
        ])
    }

    // MARK: - Lifecycle & Visibility

    public func show() {
        window.makeKeyAndOrderFront(nil)
    }

    public func hide() {
        window.orderOut(nil)
    }

    public func close() {
        shutdown()
        window.close()
        onClose?()
    }

    public func shutdown() {
        renderTimer?.invalidate()
        renderTimer = nil
        model.unload()
        outlineModel.unload()
        filamentView.stopRendering()
    }

    public func windowWillClose(_ notification: Notification) {
        shutdown()
        onClose?()
    }

    public func windowDidResize(_ notification: Notification) {
        filamentView.updateViewport()
    }

    // MARK: - Actions

    @objc private func onCloseClicked() {
        close()
    }

    @objc private func onOrbitClicked() {
        camera.isAutoOrbiting.toggle()
    }

    @objc private func onResetCameraClicked() {
        camera.reset()
    }

    // MARK: - Model & Shading Control

    public func loadModel(from url: URL) throws {
        currentModelURL = url
        animationTime = 0.0

        try model.loadGlb(at: url)
        model.setRotation(radiansY: 0.0)
        model.setPriority(4)
        if model.hasAnimations {
            model.selectAnimation(at: 0)
            isAnimationPlaying = model.activeAnimationDuration > 0.001
        }

        try outlineModel.loadGlb(at: url)
        outlineModel.setRotation(radiansY: 0.0)
        outlineModel.setPriority(6)
        if outlineModel.hasAnimations {
            outlineModel.selectAnimation(at: 0)
        }

        ensureMaterials()
        applyShadingMode()
    }

    public func setShadingMode(index: Int) {
        currentShadingMode = index
        applyShadingMode()
    }

    public func setOutlineColor(r: Float, g: Float, b: Float, a: Float = 1.0) {
        ensureMaterials()
        outlineMaterial?.outlineColor = (r, g, b, a)
    }

    public func setOutlineThickness(_ thickness: Float) {
        ensureMaterials()
        outlineMaterial?.outlineThickness = thickness
    }

    public func setOutlineGradientMode(_ mode: FilamentToonOutlineMaterial.GradientMode) {
        ensureMaterials()
        outlineMaterial?.gradientMode = mode
    }

    public func setOutlineStops(_ stops: [FilamentToonOutlineMaterial.GradientStop]) {
        ensureMaterials()
        outlineMaterial?.stops = stops
    }

    public func setOutlineGradientScale(_ scale: Float) {
        ensureMaterials()
        outlineMaterial?.gradientScale = scale
    }

    public func setOutlineGradientPhase(_ phase: Float) {
        ensureMaterials()
        outlineMaterial?.gradientPhase = phase
    }

    public func setOutlineFlowSpeed(_ speed: Float) {
        ensureMaterials()
        outlineMaterial?.flowAnimationSpeed = speed
    }

    public func setOutlineNoiseScale(_ noise: Float) {
        ensureMaterials()
        outlineMaterial?.noiseScale = noise
    }

    private func applyShadingMode() {
        guard let url = currentModelURL else { return }
        ensureMaterials()

        switch currentShadingMode {
        case 0: // Standard PBR
            outlineModel.setVisible(false)
            try? model.loadGlb(at: url)
            model.setRotation(radiansY: 0.0)
            model.setPriority(4)
            if model.hasAnimations {
                model.selectAnimation(at: 0)
            }

        case 1: // Toon Cel
            outlineModel.setVisible(false)
            model.setPriority(4)
            if let toon = toonMaterial {
                model.applyToonMaterial(toon)
            }

        case 2: // Toon + Outline
            model.setPriority(4)
            if let toon = toonMaterial {
                model.applyToonMaterial(toon)
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case 3: // PBR + Outline
            try? model.loadGlb(at: url)
            model.setRotation(radiansY: 0.0)
            model.setPriority(4)
            if model.hasAnimations {
                model.selectAnimation(at: 0)
            }
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        case 4: // Outline Only (Transparent Body)
            model.setPriority(4)
            if let mask = depthMaskMaterial {
                model.applyDepthMaskMaterial(mask)
            }
            model.setVisible(true)
            if let outline = outlineMaterial {
                outlineModel.applyOutlineMaterial(outline)
            }
            outlineModel.setPriority(6)
            outlineModel.setVisible(true)

        default: break
        }
    }

    private func ensureMaterials() {
        guard toonMaterial == nil || outlineMaterial == nil || depthMaskMaterial == nil else { return }
        let engine = filamentView.engine
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = sourceDir.deletingLastPathComponent().deletingLastPathComponent()
        let candidateDirs = [
            repoRoot.appendingPathComponent("Resources/Materials", isDirectory: true),
            repoRoot.appendingPathComponent("Examples/Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "Examples/Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "Resources/Materials", isDirectory: true),
            URL(fileURLWithPath: "../Resources/Materials", isDirectory: true),
        ]

        for dir in candidateDirs {
            let celURL = dir.appendingPathComponent("ToonCel.filamat")
            let outURL = dir.appendingPathComponent("ToonOutline.filamat")
            let maskURL = dir.appendingPathComponent("DepthMask.filamat")

            if FileManager.default.fileExists(atPath: celURL.path) && toonMaterial == nil {
                toonMaterial = try? engine.createToonMaterial(from: celURL)
                toonMaterial?.syncWithDirectionalLight(direction: (0.2, -1.0, -0.6), color: (1.0, 0.98, 0.95))
            }
            if FileManager.default.fileExists(atPath: outURL.path) && outlineMaterial == nil {
                outlineMaterial = try? engine.createOutlineMaterial(from: outURL)
            }
            if FileManager.default.fileExists(atPath: maskURL.path) && depthMaskMaterial == nil {
                depthMaskMaterial = try? engine.createDepthMaskMaterial(from: maskURL)
            }
        }
    }

    // MARK: - Render Loop

    private func startRenderLoop() {
        lastFrameTime = CACurrentMediaTime()
        let timer = Timer.scheduledTimer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(onRenderTimer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    @objc private func onRenderTimer() {
        let now = CACurrentMediaTime()
        let dt = Float(min(0.25, max(0, now - lastFrameTime)))
        lastFrameTime = now

        if isAnimationPlaying && model.hasAnimations {
            animationTime += dt
            let duration = model.activeAnimationDuration
            if duration > 0.001 {
                animationTime = animationTime.truncatingRemainder(dividingBy: duration)
            }
            model.applyAnimation(time: animationTime)
            if outlineModel.isLoaded && outlineModel.isVisible {
                outlineModel.applyAnimation(time: animationTime)
            }
        }

        model.applyMorphWeights()
        if outlineModel.isLoaded && outlineModel.isVisible {
            outlineModel.applyMorphWeights()
        }

        if let out = outlineMaterial, out.flowAnimationSpeed != 0 {
            let nextPhase = (out.gradientPhase + dt * out.flowAnimationSpeed).truncatingRemainder(dividingBy: 1.0)
            out.gradientPhase = nextPhase >= 0 ? nextPhase : (nextPhase + 1.0)
        }

        camera.update(dt: dt)
        _ = filamentView.renderFrame()
    }
}
