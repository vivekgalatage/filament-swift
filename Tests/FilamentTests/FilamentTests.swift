import XCTest
import FilamentC
@testable import Filament

/// Builds a loaded `FilamentModel` on the main actor, from a nonisolated test method.
private func makeLoadedModel(_ engine: FilamentEngine) -> FilamentModel {
    MainActor.assumeIsolated {
        let m = FilamentModel(engine: engine)
        try? m.loadGlb(data: TestGLBFixture.staticTriangle())
        return m
    }
}

/// Sends a value into a closure that may run on a background thread.
private final class Box<T>: @unchecked Sendable {
    var value: T?
    init(_ v: T) { value = v }
}

private func onBackgroundThreadRelease(_ body: @escaping @Sendable () -> Void) {
    let sem = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        body()
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 20)
}

final class FilamentTests: XCTestCase {
    // MARK: - Engine

    @MainActor
    func testEngineLifecycle() {
        let engine = FilamentEngine(backend: .metal)
        XCTAssertNotNil(engine.engine, "Filament engine should be initialized")
        XCTAssertNotNil(engine.renderer, "Renderer should be created")
        XCTAssertNotNil(engine.scene, "Scene should be created")
        XCTAssertNotNil(engine.view, "View should be created")
        XCTAssertFalse(engine.isShutDown)

        // Test transparent background configuration
        engine.setTransparent(true)
        engine.setTransparent(false)

        engine.shutDown()
        XCTAssertTrue(engine.isShutDown)
        XCTAssertNil(engine.engine)
        // Idempotent
        engine.shutDown()
    }

    @MainActor
    func testEngineCameraAndViewport() throws {
        let engine = FilamentEngine(backend: .metal)
        engine.setCameraProjection(fovInDegrees: 45, aspect: 16.0 / 9.0, near: 0.1, far: 100)
        engine.setCameraLookAt(eye: (0, 0, 3), center: (0, 0, 0), up: (0, 1, 0))
        let view = try XCTUnwrap(engine.view)
        FilamentBridge.setViewport(view, 0, 0, 640, 480)
    }

    @MainActor
    func testOrbitCameraManipulator() {
        let engine = FilamentEngine(backend: .metal)
        let camera = FilamentOrbitCamera(engine: engine)
        XCTAssertEqual(camera.distance, 3.2, accuracy: 1e-5)

        camera.orbit(deltaX: 50, deltaY: 30)
        XCTAssertNotEqual(camera.azimuth, 0.0)
        XCTAssertGreaterThan(camera.elevation, 0.25)

        // Elevation must clamp below pi/2 to avoid gimbal flip.
        camera.orbit(deltaX: 0, deltaY: 100_000)
        XCTAssertLessThan(camera.elevation, .pi / 2.0)

        // Pan shifts target in the camera plane.
        camera.pan(deltaX: 40, deltaY: -20)
        XCTAssertTrue(camera.target.x != 0 || camera.target.y != 0 || camera.target.z != 0)

        // Zoom scales distance within [minDistance, maxDistance].
        camera.zoom(delta: 5.0)
        XCTAssertLessThan(camera.distance, 3.2)
        camera.zoom(delta: -1000.0)
        XCTAssertEqual(camera.distance, camera.maxDistance, accuracy: 1e-5)

        // Reset restores initial state.
        camera.reset()
        XCTAssertEqual(camera.azimuth, 0.0, accuracy: 1e-5)
        XCTAssertEqual(camera.elevation, 0.25, accuracy: 1e-5)
        XCTAssertEqual(camera.distance, 3.2, accuracy: 1e-5)
        XCTAssertEqual(camera.target.x, 0.0, accuracy: 1e-5)
        XCTAssertEqual(camera.target.y, 0.0, accuracy: 1e-5)
        XCTAssertEqual(camera.target.z, 0.0, accuracy: 1e-5)
    }

    @MainActor
    func testEngineAmbientLightDoesNotLeak() {
        let engine = FilamentEngine(backend: .metal)
        // Filament's engine pre-creates one IndirectLight, so this is the baseline.
        let baseline = engine.indirectLightCount

        engine.setAmbientLight(intensity: 40_000)
        XCTAssertEqual(engine.indirectLightCount, baseline + 1)

        for _ in 0..<5 {
            engine.setAmbientLight(intensity: 45_000)
        }
        XCTAssertEqual(engine.indirectLightCount, baseline + 1,
                       "Repeated setAmbientLight must replace the previous light, not accumulate")
    }

    @MainActor
    func testEngineLightLifecycle() throws {
        let engine = FilamentEngine(backend: .metal)
        let key = try XCTUnwrap(engine.addDirectionalLight(direction: (0.4, -1, -0.6), intensity: 120_000))
        let fill = try XCTUnwrap(engine.addDirectionalLight(direction: (-0.5, -0.7, 0.6), intensity: 60_000))
        XCTAssertEqual(engine.activeLightIds, [key, fill])

        engine.removeLight(id: key)
        XCTAssertEqual(engine.activeLightIds, [fill])

        // Unknown and already-removed ids must be ignored rather than importing a stale
        // entity id (which would corrupt a recycled entity).
        engine.removeLight(id: key)
        engine.removeLight(id: 999_999)
        XCTAssertEqual(engine.activeLightIds, [fill])

        // Remaining lights are destroyed with the engine.
        engine.shutDown()
    }

    /// Regression: `deinit` used to call `MainActor.assumeIsolated` and trap (SIGTRAP)
    /// whenever the last reference was released off the main thread.
    func testEngineDeinitOffMainThreadDoesNotTrap() {
        let holder = Box(MainActor.assumeIsolated { FilamentEngine(backend: .metal) })
        onBackgroundThreadRelease { holder.value = nil }
        XCTAssertNil(holder.value)
    }

    /// Regression: destroying the engine while a model still had a loaded GLB aborted the
    /// process with `utils::PreconditionPanic`.
    func testEngineDestroyedWhileModelIsAliveDoesNotAbort() throws {
        let holder = Box(MainActor.assumeIsolated { FilamentEngine(backend: .metal) })
        try MainActor.assumeIsolated {
            let model = FilamentModel(engine: holder.value!)
            try model.loadGlb(data: TestGLBFixture.staticTriangle())
            XCTAssertTrue(model.isLoaded)
        }
        // The model keeps the engine alive; dropping this reference must be safe.
        onBackgroundThreadRelease { holder.value = nil }
    }

    // MARK: - Model

    @MainActor
    func testModelLoadingAndDiscovery() throws {
        let engine = FilamentEngine(backend: .metal)
        let model = FilamentModel(engine: engine)

        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filament-model-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Static model (no animations).
        let staticURL = tmpDir.appendingPathComponent("Static.glb")
        try TestGLBFixture.staticTriangle().write(to: staticURL)
        try model.loadGlb(at: staticURL)
        XCTAssertTrue(model.isLoaded)
        XCTAssertFalse(model.hasAnimations)
        model.setRotation(radiansY: 0.5)

        // Animated model.
        let animatedURL = tmpDir.appendingPathComponent("Animated.glb")
        try TestGLBFixture.animatedTriangle().write(to: animatedURL)
        try model.loadGlb(at: animatedURL)
        XCTAssertTrue(model.isLoaded)
        XCTAssertTrue(model.hasAnimations)
        XCTAssertGreaterThan(model.animations.count, 0)
        XCTAssertEqual(model.activeAnimationIndex, 0, "First animation is selected on load")

        // Animation selection and evaluation.
        model.selectAnimation(at: 0)
        XCTAssertEqual(model.activeAnimationIndex, 0)
        XCTAssertGreaterThan(model.activeAnimationDuration, 0.0)
        model.applyAnimation(time: 0.5)

        // Out-of-range selections are rejected.
        model.selectAnimation(at: -1)
        XCTAssertEqual(model.activeAnimationIndex, 0)
        model.selectAnimation(at: model.animations.count)
        XCTAssertEqual(model.activeAnimationIndex, 0)

        // Disabling resets bone matrices.
        model.selectAnimation(at: nil)
        XCTAssertNil(model.activeAnimationIndex)
        XCTAssertEqual(model.activeAnimationDuration, 0.0)

        model.unload()
        XCTAssertFalse(model.isLoaded)
        XCTAssertFalse(model.hasAnimations)
        XCTAssertNil(model.activeAnimationIndex)

        // Unloading twice is a no-op.
        model.unload()
    }

    @MainActor
    func testMorphTargets() throws {
        let engine = FilamentEngine(backend: .metal)

        // 1. Model without morph targets
        let staticModel = FilamentModel(engine: engine)
        try staticModel.loadGlb(data: TestGLBFixture.staticTriangle())
        XCTAssertFalse(staticModel.hasMorphTargets)
        XCTAssertEqual(staticModel.morphTargets.count, 0)
        XCTAssertEqual(staticModel.getMorphWeight(at: 0), 0.0)

        // 2. Model with morph targets
        let sphereModel = FilamentModel(engine: engine)
        let sphereURL = URL(fileURLWithPath: "Resources/MorphSphere.glb")
        try sphereModel.loadGlb(at: sphereURL)
        XCTAssertTrue(sphereModel.hasMorphTargets)
        XCTAssertEqual(sphereModel.morphTargets.count, 4)
        XCTAssertEqual(
            sphereModel.morphTargets.map(\.name),
            ["Squash & Stretch", "Twist", "Spikes", "Bend"]
        )

        // 3. Initial weights are 0.0
        for i in 0..<sphereModel.morphTargets.count {
            XCTAssertEqual(sphereModel.getMorphWeight(at: i), 0.0)
            XCTAssertEqual(sphereModel.morphTargets[i].weight, 0.0)
        }

        // 4. Set weight by index
        sphereModel.setMorphWeight(at: 0, weight: 0.75)
        XCTAssertEqual(sphereModel.getMorphWeight(at: 0), 0.75)
        XCTAssertEqual(sphereModel.morphTargets[0].weight, 0.75)

        // 5. Set weight by name
        sphereModel.setMorphWeight(named: "Twist", weight: 0.9)
        XCTAssertEqual(sphereModel.getMorphWeight(at: 1), 0.9)
        XCTAssertEqual(sphereModel.morphTargets[1].weight, 0.9)

        // 6. Backwards compatibility methods (setBlendShape)
        sphereModel.setBlendShape(index: 2, weight: 0.3)
        XCTAssertEqual(sphereModel.getMorphWeight(at: 2), 0.3)
        sphereModel.setBlendShape(name: "Bend", weight: 0.6)
        XCTAssertEqual(sphereModel.getMorphWeight(at: 3), 0.6)

        // 7. Reset all weights
        sphereModel.resetMorphWeights()
        for i in 0..<sphereModel.morphTargets.count {
            XCTAssertEqual(sphereModel.getMorphWeight(at: i), 0.0)
            XCTAssertEqual(sphereModel.morphTargets[i].weight, 0.0)
        }

        // 8. Out of range index is gracefully ignored
        sphereModel.setMorphWeight(at: -1, weight: 1.0)
        sphereModel.setMorphWeight(at: 999, weight: 1.0)
        XCTAssertEqual(sphereModel.getMorphWeight(at: -1), 0.0)
        XCTAssertEqual(sphereModel.getMorphWeight(at: 999), 0.0)

        // 9. Unload clears morph targets
        sphereModel.unload()
        XCTAssertFalse(sphereModel.hasMorphTargets)
        XCTAssertTrue(sphereModel.morphTargets.isEmpty)

        // 10. Test with furu 6.glb if present on disk
        let furuURL = URL(fileURLWithPath: "/Users/vivekg/Downloads/furu 6.glb")
        if FileManager.default.fileExists(atPath: furuURL.path) {
            let furuModel = FilamentModel(engine: engine)
            try furuModel.loadGlb(at: furuURL)
            print("furuModel loaded! morph targets count: \(furuModel.morphTargets.count)")
            print("furuModel animations count: \(furuModel.animations.count)")
            print("furuModel activeAnimationIndex: \(String(describing: furuModel.activeAnimationIndex))")
            
            XCTAssertFalse(furuModel.hasCustomMorphWeights)
            XCTAssertEqual(furuModel.morphTargets.count, 96)
            
            // Setting a named morph target synchronizes all entities sharing that target
            furuModel.setMorphWeight(named: "viseme_FF", weight: 0.85)
            XCTAssertTrue(furuModel.hasCustomMorphWeights)
            let ffTargets = furuModel.morphTargets.filter { $0.name == "viseme_FF" }
            XCTAssertEqual(ffTargets.count, 3, "viseme_FF exists on Head, MouthInner, and Teeth")
            for t in ffTargets {
                XCTAssertEqual(t.weight, 0.85, accuracy: 1e-4)
            }

            // Setting by index for a named target also syncs matching submeshes
            if let firstFF = ffTargets.first {
                furuModel.setMorphWeight(at: firstFF.id, weight: 0.42)
                for t in furuModel.morphTargets.filter({ $0.name == "viseme_FF" }) {
                    XCTAssertEqual(t.weight, 0.42, accuracy: 1e-4)
                }
            }

            // applyMorphWeights re-applies stored weights even after applyAnimation
            furuModel.applyAnimation(time: 0.5)
            furuModel.applyMorphWeights()
            XCTAssertTrue(furuModel.hasCustomMorphWeights)

            // Resetting clears all weights
            furuModel.resetMorphWeights()
            XCTAssertFalse(furuModel.hasCustomMorphWeights)
            for t in furuModel.morphTargets {
                XCTAssertEqual(t.weight, 0.0)
            }
            furuModel.unload()
        }
    }

    @MainActor
    func testModelRejectsInvalidData() throws {
        let engine = FilamentEngine(backend: .metal)
        let model = FilamentModel(engine: engine)

        XCTAssertThrowsError(try model.loadGlb(data: Data())) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, "FilamentModel")
        }
        XCTAssertThrowsError(try model.loadGlb(data: Data(repeating: 0x41, count: 1024)))
        XCTAssertFalse(model.isLoaded)
        XCTAssertFalse(model.hasAnimations)
    }

    /// Regression: model `deinit` trapped when released off the main thread.
    func testModelDeinitOffMainThreadDoesNotTrap() {
        let engineHolder = Box(MainActor.assumeIsolated { FilamentEngine(backend: .metal) })
        let modelHolder = Box(makeLoadedModel(engineHolder.value!))
        onBackgroundThreadRelease { modelHolder.value = nil }
        XCTAssertNil(modelHolder.value)
        MainActor.assumeIsolated { engineHolder.value = nil }
    }

    // MARK: - PBR settings

    @MainActor
    func testPBRControllerAppliesSettingsAndDoesNotLeakColorGrading() {
        let engine = FilamentEngine(backend: .metal)
        let baseline = engine.colorGradingCount

        let pbr = FilamentPBRController(engine: engine)
        // The controller owns exactly the key + fill lights (no duplicates).
        XCTAssertEqual(engine.activeLightIds.count, 2)
        XCTAssertGreaterThan(engine.colorGradingCount, baseline)

        // Repeatedly changing grade-only fields must rebuild, not accumulate, the LUT.
        let afterInit = engine.colorGradingCount
        for toneMapping in FilamentToneMapping.allCases {
            pbr.mutate { $0.toneMapping = toneMapping }
        }
        XCTAssertEqual(engine.colorGradingCount, afterInit,
                       "Rebuilding color grading must not leak ColorGrading objects")

        for value in stride(from: -1.0, through: 1.0, by: 0.25) {
            pbr.mutate { $0.whiteBalance = Float(value) }
            pbr.mutate { $0.saturation = Float(value) + 1.0 }
            pbr.mutate { $0.contrast = Float(value) + 1.0 }
        }
        XCTAssertEqual(engine.colorGradingCount, afterInit)
        XCTAssertEqual(pbr.settings.toneMapping, .gt7)
    }

    @MainActor
    func testPBRControllerNeutralDefaultsArePhysicallySane() {
        // Filament's exposure is calibrated for ~100k lux lights at f/16, 1/125s, ISO100.
        // Defaults that drift away from that produce a blown-out image.
        let s = FilamentPBRSettings.neutral
        XCTAssertEqual(s.exposure, 1.0, "Neutral exposure must be a 1.0 multiplier")
        XCTAssertEqual(s.whiteBalance, 0.0, "White balance must default to neutral, not Kelvin")
        XCTAssertEqual(s.tint, 0.0)
        XCTAssertEqual(s.contrast, 1.0)
        XCTAssertEqual(s.saturation, 1.0)
        XCTAssertEqual(s.vibrance, 1.0)
        XCTAssertGreaterThanOrEqual(s.keyLightIntensity, 100_000)
        XCTAssertFalse(s.bloomEnabled, "Effects must default to off")
        XCTAssertFalse(s.occlusionEnabled)
        XCTAssertFalse(s.reflectionsEnabled)
    }

    @MainActor
    func testPBRControllerAppliesEveryControlWithoutCrashing() {
        let engine = FilamentEngine(backend: .metal)
        let pbr = FilamentPBRController(engine: engine)

        // Walk every enum case and every toggle so no bridge call is left untested.
        for mapping in FilamentToneMapping.allCases {
            for aa in FilamentAntiAliasing.allCases {
                for quality in FilamentHDRQuality.allCases {
                    for occlusion in FilamentOcclusionMode.allCases {
                        var s = FilamentPBRSettings.neutral
                        s.toneMapping = mapping
                        s.antiAliasing = aa
                        s.multiSampleCount = 4
                        s.hdrQuality = quality
                        s.occlusionMode = occlusion
                        s.bloomEnabled = true
                        s.bloomStrength = 0.3
                        s.vignetteEnabled = true
                        s.occlusionEnabled = true
                        s.reflectionsEnabled = true
                        s.depthOfFieldEnabled = true
                        s.dithering = false
                        pbr.update(s)
                    }
                }
            }
        }

        pbr.setKeyLightDirection((0, -1, 0))
        pbr.setKeyLightColor((1, 0.9, 0.8))
        pbr.reset()
        XCTAssertEqual(pbr.settings, .neutral)

        engine.shutDown()
    }

    @MainActor
    func testEngineClampsOutOfRangeControlValues() {
        let engine = FilamentEngine(backend: .metal)
        // MSAA supports 1/2/4/8; anything else is clamped rather than passed through.
        engine.setMultiSampleCount(3)
        engine.setMultiSampleCount(100)
        engine.setExposure(0.0)      // must not produce a zero/negative exposure
        engine.setExposure(10_000)
        engine.setBloom(enabled: true, strength: 1, levels: 99)  // levels clamped to <= 11
        XCTAssertNotNil(engine.view)
    }

    @MainActor
    func testEngineLightControlsIgnoreUnknownIDs() {
        let engine = FilamentEngine(backend: .metal)
        // Must be no-ops rather than importing a stale entity id.
        engine.setLightIntensity(id: 999_999, intensity: 1)
        engine.setLightColor(id: 999_999, color: (1, 1, 1))
        engine.setLightDirection(id: 999_999, direction: (0, -1, 0))
        engine.setLightShadows(id: 999_999, enabled: true)
        XCTAssertTrue(engine.activeLightIds.isEmpty)
    }

    // MARK: - Discovery

    @MainActor
    func testModelDiscoveryAndSelectionMerging() throws {
        let dirA = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filament-discovery-a-\(UUID().uuidString)")
        let dirB = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("filament-discovery-b-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: dirA)
            try? FileManager.default.removeItem(at: dirB)
        }

        // Empty directory -> empty list (no embedded fallback).
        let emptyResult = ModelDiscovery.discoverModels(extraSearchPaths: [dirA], includeDefaultPaths: false)
        XCTAssertTrue(emptyResult.isEmpty, "Empty directory must return no models")

        // Non-.glb files and directories are ignored; .GLB uppercase is accepted.
        let dummy = Data([0x67, 0x6C, 0x54, 0x46])
        try dummy.write(to: dirA.appendingPathComponent("ignored.gltf"))
        try dummy.write(to: dirA.appendingPathComponent("Upper.GLB"))
        try FileManager.default.createDirectory(
            at: dirA.appendingPathComponent("Dir.glb"), withIntermediateDirectories: true
        )

        let found = ModelDiscovery.discoverModels(extraSearchPaths: [dirA], includeDefaultPaths: false)
        XCTAssertEqual(found.map(\.name), ["Upper"])

        // Earlier search paths win on name collisions.
        let primaryBox = dirA.appendingPathComponent("Box.glb")
        let secondaryBox = dirB.appendingPathComponent("Box.glb")
        let extraModel = dirB.appendingPathComponent("Alpha.glb")
        try dummy.write(to: primaryBox)
        try dummy.write(to: secondaryBox)
        try dummy.write(to: extraModel)

        let resolved = ModelDiscovery.discoverModels(extraSearchPaths: [dirA, dirB], includeDefaultPaths: false)
        XCTAssertEqual(resolved.map(\.name), ["Alpha", "Box", "Upper"])
        XCTAssertEqual(
            resolved.first { $0.name == "Box" }?.url.standardizedFileURL.path,
            primaryBox.standardizedFileURL.path,
            "Earlier search paths must take priority on name collisions"
        )

        // Merging files/directories selected from a file dialog adds new models and returns first selected index.
        var models: [ModelAsset] = []
        let firstIdx = ModelDiscovery.mergeSelectedURLs([primaryBox], into: &models)
        XCTAssertEqual(firstIdx, 0)
        XCTAssertEqual(models.map(\.name), ["Box"])

        // Merging a directory scans all .glb files inside and avoids duplicating existing files.
        let dirIdx = ModelDiscovery.mergeSelectedURLs([dirA], into: &models)
        XCTAssertEqual(dirIdx, 0)
        XCTAssertEqual(models.map(\.name), ["Box", "Upper"])

        // Re-selecting an already loaded file jumps to its existing index without duplicating.
        let existingIdx = ModelDiscovery.mergeSelectedURLs([primaryBox], into: &models)
        XCTAssertEqual(existingIdx, 0)
        XCTAssertEqual(models.count, 2)
    }
}

/// Builds minimal valid glTF 2.0 binary (`.glb`) buffers in memory strictly for unit tests.
enum TestGLBFixture {
    static func staticTriangle() -> Data {
        let json = """
        {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"mesh":0}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":6}],"buffers":[{"byteLength":80}]}
        """
        return packGLB(json: json, bin: triangleGeometryBin())
    }

    static func animatedTriangle() -> Data {
        let json = """
        {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Tri","mesh":0,"translation":[0,0,0]}],"meshes":[{"primitives":[{"attributes":{"POSITION":0,"NORMAL":1},"indices":2}]}],"animations":[{"name":"Move","samplers":[{"input":3,"interpolation":"LINEAR","output":4}],"channels":[{"sampler":0,"target":{"node":0,"path":"translation"}}]}],"accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","min":[0,0,0],"max":[1,1,0]},{"bufferView":1,"componentType":5126,"count":3,"type":"VEC3"},{"bufferView":2,"componentType":5123,"count":3,"type":"SCALAR"},{"bufferView":3,"componentType":5126,"count":2,"type":"SCALAR","min":[0],"max":[1]},{"bufferView":4,"componentType":5126,"count":2,"type":"VEC3"}],"bufferViews":[{"buffer":0,"byteOffset":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":36},{"buffer":0,"byteOffset":72,"byteLength":6},{"buffer":0,"byteOffset":80,"byteLength":8},{"buffer":0,"byteOffset":88,"byteLength":24}],"buffers":[{"byteLength":112}]}
        """
        var bin = triangleGeometryBin()
        // Keyframe timestamps: 0.0, 1.0 (8 bytes at offset 80)
        appendFloats([0.0, 1.0], to: &bin)
        // Keyframe translations: (0,0,0) -> (0,1,0) (24 bytes at offset 88)
        appendFloats([0, 0, 0, 0, 1, 0], to: &bin)
        return packGLB(json: json, bin: bin)
    }

    private static func triangleGeometryBin() -> Data {
        var bin = Data()
        // 3 positions (36 bytes at offset 0)
        appendFloats([0, 0, 0, 1, 0, 0, 0, 1, 0], to: &bin)
        // 3 normals (36 bytes at offset 36)
        appendFloats([0, 0, 1, 0, 0, 1, 0, 0, 1], to: &bin)
        // 3 uint16 indices + 1 uint16 padding (8 bytes at offset 72 -> total 80 bytes)
        for idx: UInt16 in [0, 1, 2, 0] {
            var le = idx.littleEndian
            withUnsafeBytes(of: &le) { bin.append(contentsOf: $0) }
        }
        return bin
    }

    private static func appendFloats(_ floats: [Float], to data: inout Data) {
        for f in floats {
            var bits = f.bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
    }

    private static func packGLB(json: String, bin: Data) -> Data {
        var jsonBytes = Data(json.utf8)
        while jsonBytes.count % 4 != 0 {
            jsonBytes.append(0x20) // space padding per glTF spec
        }
        var binBytes = bin
        while binBytes.count % 4 != 0 {
            binBytes.append(0x00)
        }

        let totalLength = UInt32(12 + 8 + jsonBytes.count + 8 + binBytes.count)
        var out = Data()
        appendUInt32(0x46546C67, to: &out) // "glTF"
        appendUInt32(2, to: &out)          // version 2
        appendUInt32(totalLength, to: &out)

        appendUInt32(UInt32(jsonBytes.count), to: &out)
        appendUInt32(0x4E4F534A, to: &out) // "JSON"
        out.append(jsonBytes)

        appendUInt32(UInt32(binBytes.count), to: &out)
        appendUInt32(0x004E4942, to: &out) // "BIN\0"
        out.append(binBytes)
        return out
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        var le = value.littleEndian
        withUnsafeBytes(of: &le) { data.append(contentsOf: $0) }
    }
}