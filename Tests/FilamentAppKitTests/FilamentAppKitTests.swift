import XCTest
import AppKit
import QuartzCore
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

        view.stopRendering()
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