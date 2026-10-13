import XCTest
import AppKit
import QuartzCore
import Filament
import FilamentC
@testable import FilamentAppKit

final class FilamentAppKitTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        _ = await MainActor.run {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }

    @MainActor
    func testViewCreatesSwapChainAndRenders() throws {
        let view = FilamentView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let layer = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertEqual(layer.pixelFormat, .bgra8Unorm)
        XCTAssertTrue(layer.isOpaque, "Opaque by default")

        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        window.orderFront(nil)
        view.updateViewport()

        // beginFrame can legitimately return false when the display drops the frame, but
        // the view must never fail to produce a swap chain.
        for _ in 0..<3 {
            view.renderFrame()
        }

        // Toggling transparency must rebuild the swap chain with CONFIG_TRANSPARENT.
        view.isTransparent = true
        XCTAssertFalse(layer.isOpaque)
        view.isTransparent = false
        XCTAssertTrue(layer.isOpaque)

        // Test rendering a model with morph targets and applying blend shapes.
        let sphereURL = URL(fileURLWithPath: "Resources/MorphSphere.glb")
        let model = FilamentModel(engine: view.engine)
        try model.loadGlb(at: sphereURL)
        XCTAssertEqual(model.morphTargets.count, 4)
        for target in model.morphTargets {
            model.setBlendShape(index: target.id, weight: 0.8)
        }
        view.renderFrame()

        view.stopRendering()
        window.contentView = nil
    }

    @MainActor
    func testMorphTargetsActuallyDeformMesh() throws {
        let view = FilamentView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        window.orderFront(nil)
        view.updateViewport()

        // Recreate swapChain with readable flag
        guard let metalLayer = view.layer as? CAMetalLayer,
              let eng = view.engine.engine else {
            XCTFail("Missing engine or metalLayer")
            return
        }
        let nativeWindow = Unmanaged.passUnretained(metalLayer).toOpaque()
        let flags = FilamentBridge.getSwapChainFlagReadable()
        let sc = FilamentBridge.createSwapChain(eng, nativeWindow, flags)
        
        let sphereURL = URL(fileURLWithPath: "Resources/MorphSphere.glb")
        let model = FilamentModel(engine: view.engine)
        try model.loadGlb(at: sphereURL)
        model.resetMorphWeights()

        let w = UInt32(view.bounds.width * 2)
        let h = UInt32(view.bounds.height * 2)
        let bufSize = Int(w * h * 4)
        var pixelsBase = [UInt8](repeating: 0, count: bufSize)
        var pixelsDeformed = [UInt8](repeating: 0, count: bufSize)

        // Warm up and render base frame
        guard let renderer = view.engine.renderer, let fView = view.engine.view else { return }
        _ = FilamentBridge.beginFrame(renderer, sc)
        FilamentBridge.renderView(renderer, fView)
        let readOk1 = FilamentBridge.readPixels(eng, renderer, 0, 0, w, h, &pixelsBase, bufSize)
        FilamentBridge.endFrame(renderer)
        print("readOk1: \(readOk1)")

        // Now deform with Spikes target (id 2) at weight 1.0
        model.setMorphWeight(at: 2, weight: 1.0)
        _ = FilamentBridge.beginFrame(renderer, sc)
        FilamentBridge.renderView(renderer, fView)
        let readOk2 = FilamentBridge.readPixels(eng, renderer, 0, 0, w, h, &pixelsDeformed, bufSize)
        FilamentBridge.endFrame(renderer)
        print("readOk2: \(readOk2)")

        var diffCount = 0
        for i in 0..<bufSize {
            if pixelsBase[i] != pixelsDeformed[i] {
                diffCount += 1
            }
        }
        print("Morph target test: diffCount = \(diffCount) out of \(bufSize) bytes")
        XCTAssertGreaterThan(diffCount, 0, "Deforming morph target must change rendered pixels!")

        // Now test furu 6.glb if present
        let furuURL = URL(fileURLWithPath: "/Users/vivekg/Downloads/furu 6.glb")
        if FileManager.default.fileExists(atPath: furuURL.path) {
            let furuModel = FilamentModel(engine: view.engine)
            try furuModel.loadGlb(at: furuURL)
            furuModel.resetMorphWeights()

            _ = FilamentBridge.beginFrame(renderer, sc)
            FilamentBridge.renderView(renderer, fView)
            _ = FilamentBridge.readPixels(eng, renderer, 0, 0, w, h, &pixelsBase, bufSize)
            FilamentBridge.endFrame(renderer)

            // Deform furu: eyeBlink_L (id 3)
            furuModel.setMorphWeight(at: 3, weight: 1.0)
            _ = FilamentBridge.beginFrame(renderer, sc)
            FilamentBridge.renderView(renderer, fView)
            _ = FilamentBridge.readPixels(eng, renderer, 0, 0, w, h, &pixelsDeformed, bufSize)
            FilamentBridge.endFrame(renderer)

            var furuDiffCount = 0
            for i in 0..<bufSize {
                if pixelsBase[i] != pixelsDeformed[i] {
                    furuDiffCount += 1
                }
            }
            print("Furu eyeBlink_L diffCount: \(furuDiffCount) out of \(bufSize) bytes")
            XCTAssertGreaterThan(furuDiffCount, 0, "Deforming furu eyeBlink_L must change rendered pixels!")

            // What happens if applyAnimation(time: 0.0) is called?
            furuModel.applyAnimation(time: 0.0)
            _ = FilamentBridge.beginFrame(renderer, sc)
            FilamentBridge.renderView(renderer, fView)
            _ = FilamentBridge.readPixels(eng, renderer, 0, 0, w, h, &pixelsDeformed, bufSize)
            FilamentBridge.endFrame(renderer)

            var animDiffCount = 0
            for i in 0..<bufSize {
                if pixelsBase[i] != pixelsDeformed[i] {
                    animDiffCount += 1
                }
            }
            print("After applyAnimation(0), animDiffCount against base: \(animDiffCount)")
            furuModel.unload()
        }

        FilamentBridge.destroySwapChain(eng, sc)
        window.contentView = nil
    }

    /// Regression: the AppKit view `deinit` trapped when released off the main thread.
    @MainActor
    func testViewDeinitOffMainThreadDoesNotTrap() {
        final class Box<T>: @unchecked Sendable {
            var value: T?
            init(_ v: T) { value = v }
        }
        let holder = Box(FilamentView(frame: NSRect(x: 0, y: 0, width: 320, height: 240)))
        let sem = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            holder.value = nil
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 20)
        XCTAssertNil(holder.value)
    }
}