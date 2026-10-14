import Foundation

/// Interactive spherical orbit, pan, and zoom camera controller for `FilamentEngine`.
///
/// Supports:
/// - **Orbit (tumble)**: `orbit(deltaX:deltaY:)` rotates around `target` via azimuth & elevation.
/// - **Pan (truck/pedestal)**: `pan(deltaX:deltaY:)` translates `target` in the camera's view plane,
///   scaled proportionally to the current `distance`.
/// - **Zoom (dolly)**: `zoom(delta:)` scales `distance` smoothly within `[minDistance, maxDistance]`.
/// - **Reset**: `reset()` restores the default home camera position and target.
@MainActor
public final class FilamentOrbitCamera {
    public let engine: FilamentEngine

    /// Horizontal angle in radians around the world +Y axis (0 looks from +Z toward origin).
    public private(set) var azimuth: Double
    /// Vertical angle in radians above the XZ plane, clamped to avoid gimbal flip.
    public private(set) var elevation: Double
    /// Distance from `target` to the camera eye position.
    public private(set) var distance: Double
    /// World-space look-at target point.
    public private(set) var target: (x: Double, y: Double, z: Double)

    /// Optional turntable rotation when idle. Automatically disabled on manual mouse orbit/pan.
    public var isAutoOrbiting: Bool = false
    /// When true, manual mouse movements will not disengage auto-orbiting.
    public var lockAutoOrbit: Bool = false

    public var orbitSensitivity: Double = 0.007
    public var panSensitivity: Double = 0.0015
    public var minDistance: Double = 0.2
    public var maxDistance: Double = 50.0

    private let defaultAzimuth: Double
    private let defaultElevation: Double
    private let defaultDistance: Double
    private let defaultTarget: (x: Double, y: Double, z: Double)

    private static let maxElevation: Double = (.pi / 2.0) - 0.04

    public init(
        engine: FilamentEngine,
        azimuth: Double = 0.0,
        elevation: Double = 0.25,
        distance: Double = 3.2,
        target: (x: Double, y: Double, z: Double) = (0.0, 0.0, 0.0)
    ) {
        self.engine = engine
        self.defaultAzimuth = azimuth
        self.defaultElevation = min(max(elevation, -Self.maxElevation), Self.maxElevation)
        self.defaultDistance = min(max(distance, 0.2), 50.0)
        self.defaultTarget = target

        self.azimuth = self.defaultAzimuth
        self.elevation = self.defaultElevation
        self.distance = self.defaultDistance
        self.target = self.defaultTarget

        applyToEngine()
    }

    /// Orbits the camera around `target` given pointer movement in pixels (`deltaX` right, `deltaY` down).
    public func orbit(deltaX: Double, deltaY: Double) {
        if !lockAutoOrbit { isAutoOrbiting = false }
        azimuth -= deltaX * orbitSensitivity
        elevation = min(
            max(elevation + deltaY * orbitSensitivity, -Self.maxElevation),
            Self.maxElevation
        )
        applyToEngine()
    }

    /// Pans `target` in the camera's local right/up plane given pointer movement in pixels (`deltaX` right, `deltaY` down).
    public func pan(deltaX: Double, deltaY: Double) {
        if !lockAutoOrbit { isAutoOrbiting = false }
        let basis = cameraBasis()
        let scale = distance * panSensitivity
        let moveRight = -deltaX * scale
        let moveUp = deltaY * scale

        target.x += moveRight * basis.right.x + moveUp * basis.up.x
        target.y += moveRight * basis.right.y + moveUp * basis.up.y
        target.z += moveRight * basis.right.z + moveUp * basis.up.z
        applyToEngine()
    }

    /// Zooms the camera toward (`delta > 0`) or away from (`delta < 0`) `target`.
    public func zoom(delta: Double) {
        guard delta != 0 else { return }
        let factor = pow(0.92, delta)
        distance = min(max(distance * factor, minDistance), maxDistance)
        applyToEngine()
    }

    /// Explicitly sets the distance from target.
    public func setDistance(_ newDistance: Double) {
        distance = min(max(newDistance, minDistance), maxDistance)
        applyToEngine()
    }

    /// Programmatically sets camera spherical angles, distance, and/or look-at target.
    public func setPose(
        azimuth: Double? = nil,
        elevation: Double? = nil,
        distance: Double? = nil,
        target: (x: Double, y: Double, z: Double)? = nil
    ) {
        if let azimuth { self.azimuth = azimuth }
        if let elevation { self.elevation = min(max(elevation, -Self.maxElevation), Self.maxElevation) }
        if let distance { self.distance = min(max(distance, minDistance), maxDistance) }
        if let target { self.target = target }
        applyToEngine()
    }

    /// Restores the camera to its initial azimuth, elevation, distance, and target.
    public func reset() {
        azimuth = defaultAzimuth
        elevation = defaultElevation
        distance = defaultDistance
        target = defaultTarget
        applyToEngine()
    }

    /// Advances auto-orbit if enabled and updates the engine camera.
    public func update(dt: Float) {
        if isAutoOrbiting {
            azimuth += 0.75 * Double(dt)
            applyToEngine()
        }
    }

    /// Pushes the current eye, target, and up vectors to `FilamentEngine`.
    public func applyToEngine() {
        let basis = cameraBasis()
        let eye = (
            x: target.x + distance * basis.forwardFromTarget.x,
            y: target.y + distance * basis.forwardFromTarget.y,
            z: target.z + distance * basis.forwardFromTarget.z
        )
        engine.setCameraLookAt(
            eye: (eye.x, eye.y, eye.z),
            center: (target.x, target.y, target.z),
            up: (basis.up.x, basis.up.y, basis.up.z)
        )
    }

    private func cameraBasis() -> (
        forwardFromTarget: (x: Double, y: Double, z: Double),
        right: (x: Double, y: Double, z: Double),
        up: (x: Double, y: Double, z: Double)
    ) {
        let cosElev = cos(elevation)
        let sinElev = sin(elevation)
        let cosAzim = cos(azimuth)
        let sinAzim = sin(azimuth)

        let dir = (
            x: cosElev * sinAzim,
            y: sinElev,
            z: cosElev * cosAzim
        )
        let right = (
            x: cosAzim,
            y: 0.0,
            z: -sinAzim
        )
        let up = (
            x: -sinElev * sinAzim,
            y: cosElev,
            z: -sinElev * cosAzim
        )
        return (dir, right, up)
    }
}
