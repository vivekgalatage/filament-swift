import Foundation
import Filament
import FilamentGTK

/// GTK 4 desktop demo application in Swift.
/// Integrates Google Filament (Vulkan backend) with a native GTK 4 window and drawing area.
@MainActor
final class GTK4DemoApp {
    private var window: OpaquePointer?
    private var scene: GTKSceneController?
    private var controlPanel: GTKControlPanel?
    private var overlayWindow: FilamentOverlayWindow?

    func run() {
        print("[GTK4Demo] Starting GTK 4 application...")
        let appId = "org.filament.swift.gtk4demo"
        // G_APPLICATION_NON_UNIQUE = 32 allows standalone execution without D-Bus single-instance handoff
        guard let app = gtk_application_new(appId, 32) else {
            print("[GTK4Demo] Failed to create GTK application.")
            return
        }
        defer { g_object_unref(app) }

        let unmanagedSelf = Unmanaged.passRetained(self).toOpaque()

        let activateCallback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { appPtr, userData in
            guard let appPtr, let userData else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                selfApp.setupWindow(app: appPtr)
            }
        }

        g_signal_connect_data(
            app,
            "activate",
            unsafeBitCast(activateCallback, to: (@convention(c) () -> Void).self),
            unmanagedSelf,
            nil,
            0
        )

        let status = g_application_run(app, CommandLine.argc, CommandLine.unsafeArgv)
        print("[GTK4Demo] Exited with status: \(status)")

        shutdown()
        Unmanaged<GTK4DemoApp>.fromOpaque(unmanagedSelf).release()
    }

    func setupWindow(app: OpaquePointer) {
        let window = gtk_application_window_new(app)
        self.window = window
        gtk_window_set_title(window, "Filament Swift — GTK 4 Demo (Linux)")
        gtk_window_set_default_size(window, 1024, 720)

        setupHeaderBar(on: window)

        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)
        gtk_window_set_child(window, box)

        let drawingArea = gtk_drawing_area_new()
        gtk_widget_set_hexpand(drawingArea, 1)
        gtk_widget_set_vexpand(drawingArea, 1)
        gtk_box_append(box, drawingArea)

        let scene = GTKSceneController(drawingArea: drawingArea)
        self.scene = scene

        attachPointerControllers(to: drawingArea)

        let panelScroller = gtk_scrolled_window_new()
        gtk_scrolled_window_set_policy(panelScroller, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
        gtk_widget_set_size_request(panelScroller, 320, -1)
        gtk_widget_set_vexpand(panelScroller, 1)
        gtk_box_append(box, panelScroller)

        if let panelBox = gtk_box_new(GTK_ORIENTATION_VERTICAL, 6) {
            gtk_scrolled_window_set_child(panelScroller, panelBox)
            self.controlPanel = GTKControlPanel(controller: scene.controller, in: panelBox)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let realizeCallback: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { selfApp.scene?.attachSwapChainIfPossible() }
        }
        g_signal_connect_data(
            drawingArea,
            "realize",
            unsafeBitCast(realizeCallback, to: (@convention(c) () -> Void).self),
            selfPtr,
            nil,
            0
        )

        let drawCallback: @convention(c) (OpaquePointer?, OpaquePointer?, Int32, Int32, UnsafeMutableRawPointer?) -> Void = { _, cr, width, height, userData in
            guard let userData, let cr else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                selfApp.scene?.draw(cr: cr, width: width, height: height)
            }
        }
        gtk_drawing_area_set_draw_func(drawingArea, drawCallback, selfPtr, nil)

        let tickCallback: @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutableRawPointer?) -> Int32 = { _, _, userData in
            guard let userData else { return 1 }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                selfApp.scene?.onFrameTick()
                selfApp.overlayWindow?.renderFrame()
            }
            return 1 // G_SOURCE_CONTINUE
        }
        _ = gtk_widget_add_tick_callback(drawingArea, tickCallback, selfPtr, nil)

        gtk_window_present(window)
        print("[GTK4Demo] Window presented. Drag: Orbit | Right/Middle/Shift-Drag: Pan | Scroll: Zoom")
    }

    private func setupHeaderBar(on window: OpaquePointer?) {
        let headerBar = gtk_header_bar_new()
        gtk_window_set_titlebar(window, headerBar)

        let openBtn = gtk_button_new_with_label("Open Model…")
        let resetCamBtn = gtk_button_new_with_label("Reset View")
        let animBtn = gtk_button_new_with_label("Cycle Anim")
        let overlayBtn = gtk_button_new_with_label("Floating Overlay")

        gtk_header_bar_pack_start(headerBar, openBtn)
        gtk_header_bar_pack_start(headerBar, resetCamBtn)
        gtk_header_bar_pack_end(headerBar, overlayBtn)
        gtk_header_bar_pack_end(headerBar, animBtn)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let openClicked: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { selfApp.presentOpenDialog() }
        }
        g_signal_connect_data(openBtn, "clicked", unsafeBitCast(openClicked, to: (@convention(c) () -> Void).self), selfPtr, nil, 0)

        let resetCamClicked: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { selfApp.scene?.resetCamera() }
        }
        g_signal_connect_data(resetCamBtn, "clicked", unsafeBitCast(resetCamClicked, to: (@convention(c) () -> Void).self), selfPtr, nil, 0)

        let animClicked: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { selfApp.scene?.cycleNextAnimation() }
        }
        g_signal_connect_data(animBtn, "clicked", unsafeBitCast(animClicked, to: (@convention(c) () -> Void).self), selfPtr, nil, 0)

        let overlayClicked: @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?) -> Void = { _, userData in
            guard let userData else { return }
            let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { selfApp.toggleOverlay() }
        }
        g_signal_connect_data(overlayBtn, "clicked", unsafeBitCast(overlayClicked, to: (@convention(c) () -> Void).self), selfPtr, nil, 0)
    }

    /// Attaches GTK 4 drag and scroll controllers to `drawingArea` for interactive Orbit, Pan, and Zoom.
    private func attachPointerControllers(to drawingArea: OpaquePointer?) {
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        if let drag = gtk_gesture_drag_new() {
            // Listen to all mouse buttons (1 = left/orbit, 2 = middle/pan, 3 = right/pan).
            gtk_gesture_single_set_button(drag, 0)

            let dragBegin: @convention(c) (OpaquePointer?, Double, Double, UnsafeMutableRawPointer?) -> Void = { _, _, _, userData in
                guard let userData else { return }
                let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { selfApp.scene?.beginDrag() }
            }
            g_signal_connect_data(
                drag,
                "drag-begin",
                unsafeBitCast(dragBegin, to: (@convention(c) () -> Void).self),
                selfPtr,
                nil,
                0
            )

            let dragUpdate: @convention(c) (OpaquePointer?, Double, Double, UnsafeMutableRawPointer?) -> Void = { gesture, offsetX, offsetY, userData in
                guard let userData else { return }
                let button = gtk_gesture_single_get_current_button(gesture)
                let modifiers = gtk_event_controller_get_current_event_state(gesture)
                let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated {
                    selfApp.scene?.updateDrag(offsetX: offsetX, offsetY: offsetY, button: button, modifiers: modifiers)
                }
            }
            g_signal_connect_data(
                drag,
                "drag-update",
                unsafeBitCast(dragUpdate, to: (@convention(c) () -> Void).self),
                selfPtr,
                nil,
                0
            )

            gtk_widget_add_controller(drawingArea, drag)
        }

        if let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_VERTICAL) {
            let onScroll: @convention(c) (OpaquePointer?, Double, Double, UnsafeMutableRawPointer?) -> Int32 = { _, _, dy, userData in
                guard let userData else { return 0 }
                let selfApp = Unmanaged<GTK4DemoApp>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { selfApp.scene?.handleScroll(dy: dy) }
                return 1
            }
            g_signal_connect_data(
                scroll,
                "scroll",
                unsafeBitCast(onScroll, to: (@convention(c) () -> Void).self),
                selfPtr,
                nil,
                0
            )
            gtk_widget_add_controller(drawingArea, scroll)
        }
    }

    private func presentOpenDialog() {
        GTKFileDialog.present(parentWindow: window) { [weak self] url in
            self?.scene?.openModel(at: url)
        }
    }

    private func toggleOverlay() {
        if let existing = overlayWindow {
            existing.hide()
            self.overlayWindow = nil
            print("[GTK4Demo] Floating companion overlay closed.")
            return
        }

        print("[GTK4Demo] Launching transparent floating companion overlay...")
        let overlay = FilamentOverlayWindow(width: 420, height: 560, initialX: 120, initialY: 120)
        let sourceDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repoRoot = sourceDir.deletingLastPathComponent().deletingLastPathComponent()
        let fallbackPaths = [
            repoRoot.appendingPathComponent("Resources", isDirectory: true),
            repoRoot.appendingPathComponent("Examples/Resources", isDirectory: true),
        ]
        let modelUrl = scene?.activeModelUrl ?? ModelDiscovery.discoverModels(extraSearchPaths: fallbackPaths).first?.url
        if let modelUrl {
            do {
                try overlay.loadModel(from: modelUrl)
            } catch {
                print("[GTK4Demo] Failed to load model for overlay: \(error)")
            }
        }
        overlay.show()
        self.overlayWindow = overlay
        print("[GTK4Demo] Floating companion overlay active across desktop (borderless, transparent).")
    }

    private func shutdown() {
        overlayWindow?.hide()
        overlayWindow = nil
        scene?.shutdown()
        scene = nil
        controlPanel = nil
        window = nil
    }
}

@main
struct GTK4DemoMain {
    static func main() {
        if getenv("GDK_BACKEND") == nil {
            setenv("GDK_BACKEND", "x11", 0)
        }
        let app = GTK4DemoApp()
        withExtendedLifetime(app) {
            app.run()
        }
    }
}
