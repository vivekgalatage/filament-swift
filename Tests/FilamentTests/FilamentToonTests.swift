import XCTest
import FilamentC
@testable import Filament

final class FilamentToonTests: XCTestCase {
    @MainActor
    func testToonMaterialLifecycleAndParameters() throws {
        let engine = FilamentEngine(backend: .metal)
        let celURL = URL(fileURLWithPath: "Resources/Materials/ToonCel.filamat")
        guard FileManager.default.fileExists(atPath: celURL.path) else {
            XCTFail("ToonCel.filamat does not exist at Resources/Materials/ToonCel.filamat")
            return
        }

        let toonMaterial = try engine.createToonMaterial(from: celURL)
        XCTAssertNotNil(toonMaterial.rawMaterial, "Material handle should be created")
        XCTAssertNotNil(toonMaterial.rawInstance, "MaterialInstance handle should be created")

        // Test parameter mutations
        toonMaterial.baseColor = (r: 1.0, g: 0.5, b: 0.2, a: 1.0)
        XCTAssertEqual(toonMaterial.baseColor.r, 1.0)
        XCTAssertEqual(toonMaterial.baseColor.g, 0.5)

        toonMaterial.lightColor = (r: 1.0, g: 0.95, b: 0.9)
        XCTAssertEqual(toonMaterial.lightColor.r, 1.0)

        toonMaterial.shadowColorMultiplier = (r: 0.4, g: 0.4, b: 0.6)
        XCTAssertEqual(toonMaterial.shadowColorMultiplier.b, 0.6)

        toonMaterial.lightDirection = (x: 0.0, y: -1.0, z: -0.5)
        toonMaterial.shadowThreshold = 0.1
        toonMaterial.highlightThreshold = 0.8
        toonMaterial.edgeFeather = 0.02
        XCTAssertEqual(toonMaterial.shadowThreshold, 0.1)
        XCTAssertEqual(toonMaterial.highlightThreshold, 0.8)
        XCTAssertEqual(toonMaterial.edgeFeather, 0.02)

        // Directional light synchronization
        let dir: (Float, Float, Float) = (0.3, -0.8, -0.5)
        let col: (Float, Float, Float) = (1.0, 1.0, 0.9)
        toonMaterial.syncWithDirectionalLight(direction: dir, color: col)
        XCTAssertEqual(toonMaterial.lightDirection.x, 0.3)
        XCTAssertEqual(toonMaterial.lightColor.b, 0.9)
    }

    @MainActor
    func testToonOutlineMaterialLifecycleAndParameters() throws {
        let engine = FilamentEngine(backend: .metal)
        let outlineURL = URL(fileURLWithPath: "Resources/Materials/ToonOutline.filamat")
        guard FileManager.default.fileExists(atPath: outlineURL.path) else {
            XCTFail("ToonOutline.filamat does not exist at Resources/Materials/ToonOutline.filamat")
            return
        }

        let outlineMaterial = try engine.createOutlineMaterial(from: outlineURL)
        XCTAssertNotNil(outlineMaterial.rawMaterial)
        XCTAssertNotNil(outlineMaterial.rawInstance)

        // Test parameter mutations
        outlineMaterial.outlineColor = (r: 0.12, g: 0.08, b: 0.05, a: 1.0)
        outlineMaterial.outlineThickness = 3.0
        XCTAssertEqual(outlineMaterial.outlineThickness, 3.0)
        XCTAssertEqual(outlineMaterial.outlineColor.r, 0.12)
    }

    @MainActor
    func testApplyToonMaterialToGlbModel() throws {
        let engine = FilamentEngine(backend: .metal)
        let celURL = URL(fileURLWithPath: "Resources/Materials/ToonCel.filamat")
        let outlineURL = URL(fileURLWithPath: "Resources/Materials/ToonOutline.filamat")

        let toonMaterial = try engine.createToonMaterial(from: celURL)
        let outlineMaterial = try engine.createOutlineMaterial(from: outlineURL)

        // Load 3D model
        let model = FilamentModel(engine: engine)
        let sphereURL = URL(fileURLWithPath: "Resources/MorphSphere.glb")
        try model.loadGlb(at: sphereURL)
        XCTAssertTrue(model.isLoaded)

        // Apply Toon material to glTF asset
        model.applyToonMaterial(toonMaterial)

        // Apply Outline material to glTF asset
        model.applyOutlineMaterial(outlineMaterial)

        // Directional light setup
        let lightId = engine.addDirectionalLight(direction: (0, -1, -1), color: (1, 1, 1), intensity: 100_000)
        XCTAssertNotNil(lightId)

        if let lightId {
            toonMaterial.syncWithDirectionalLight(direction: (0, -1, -1), color: (1, 1, 1))
            engine.removeLight(id: lightId)
        }

        model.unload()
        XCTAssertFalse(model.isLoaded)
    }

    @MainActor
    func testRenderFuruOutline() throws {
        let furuURL = URL(fileURLWithPath: "/Users/vivekg/Downloads/furu 6.glb")
        guard FileManager.default.fileExists(atPath: furuURL.path) else { return }

        let engine = FilamentEngine(backend: .metal)
        let celURL = URL(fileURLWithPath: "Resources/Materials/ToonCel.filamat")
        let outlineURL = URL(fileURLWithPath: "Resources/Materials/ToonOutline.filamat")

        let toonMaterial = try engine.createToonMaterial(from: celURL)
        let outlineMaterial = try engine.createOutlineMaterial(from: outlineURL)

        let body = FilamentModel(engine: engine)
        try body.loadGlb(at: furuURL)
        body.applyToonMaterial(toonMaterial)
        body.setRotation(radiansY: 0.0)

        let outline = FilamentModel(engine: engine)
        try outline.loadGlb(at: furuURL)
        outline.applyOutlineMaterial(outlineMaterial)
        outline.setRotation(radiansY: 0.0)

        guard let eng = engine.engine, let ren = engine.renderer, let v = engine.view else { return }
        let w: UInt32 = 256
        let h: UInt32 = 256
        guard let sc = engine.createHeadlessSwapChain(width: w, height: h) else { return }
        FilamentBridge.setViewport(v, 0, 0, w, h)

        engine.setCameraProjection(fovInDegrees: 45, aspect: 1.0, near: 0.1, far: 100)
        engine.setCameraLookAt(eye: (0, 0, 3.2), center: (0, 0, 0), up: (0, 1, 0))

        _ = FilamentBridge.beginFrame(ren, sc)
        FilamentBridge.renderView(ren, v)

        let bufSize = Int(w * h * 4)
        var pixels = [UInt8](repeating: 0, count: bufSize)
        let readOk = FilamentBridge.readPixels(eng, ren, 0, 0, w, h, &pixels, bufSize)
        FilamentBridge.endFrame(ren)

        print("[Test] readOk = \(readOk)")
        var nonZeroCount = 0
        var sampleColor = (0, 0, 0, 0)
        for i in stride(from: 0, to: bufSize, by: 4) {
            if pixels[i + 3] > 0 {
                nonZeroCount += 1
                if sampleColor == (0, 0, 0, 0) {
                    sampleColor = (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
                }
            }
        }
        print("[Test] nonZeroCount = \(nonZeroCount) of \(w * h), sampleColor = \(sampleColor)")

        engine.destroySwapChain(sc)
        body.unload()
        outline.unload()
    }
}
