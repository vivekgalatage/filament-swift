import XCTest
@testable import Filament

final class FilamentTests: XCTestCase {
    @MainActor
    func testEngineLifecycle() {
        let engine = FilamentEngine()
        XCTAssertNotNil(engine.engine, "Filament engine should be initialized")
        XCTAssertNotNil(engine.renderer, "Renderer should be created")
        XCTAssertNotNil(engine.scene, "Scene should be created")
        XCTAssertNotNil(engine.view, "View should be created")

        // Test transparent background configuration
        engine.setTransparent(true)
        engine.setTransparent(false)
    }
}
