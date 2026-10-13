import Foundation
import FilamentC

/// Runs Filament teardown work on the main actor from any thread.
///
/// Filament objects must be destroyed on the thread that created them, and every
/// `Filament*` type in this module is `@MainActor` isolated. `deinit` however is
/// *nonisolated*, so it can run on whichever thread dropped the last reference.
/// Calling `MainActor.assumeIsolated` there traps (SIGTRAP) when that is not the
/// main thread, so `deinit` bodies funnel their cleanup through this helper instead:
/// synchronous on the main thread, and hopped onto the main actor otherwise.
public enum FilamentMainActor {
    /// Executes `body` on the main actor, never trapping.
    public static func perform(_ body: @escaping @Sendable @MainActor () -> Void) {
        if Thread.isMainThread {
            // Already on the main thread; `assumeIsolated` is safe here.
            MainActor.assumeIsolated { body() }
        } else {
            // Last reference dropped off the main thread: schedule the teardown and let
            // the captured `Sendable` snapshot keep the raw Filament pointers alive.
            Task { @MainActor in body() }
        }
    }
}

/// Non-isolated holder for a raw Filament swap chain handle.
///
/// Swap chains are created and destroyed on the main actor, but the owning host view's
/// `deinit` is not main-actor isolated, so the handle lives in this box instead of in an
/// isolated stored property. `take()` clears and returns the handle so teardown runs
/// exactly once, from any thread.
public final class FilamentSwapChainBox: @unchecked Sendable {
    private var raw: OpaquePointer?

    public init(_ handle: OpaquePointer? = nil) {
        self.raw = handle
    }

    /// The current handle, or `nil` when no swap chain is attached.
    public var handle: OpaquePointer? { raw }

    /// Replaces the handle and returns the previous one.
    @discardableResult
    public func set(_ newValue: OpaquePointer?) -> OpaquePointer? {
        let previous = raw
        raw = newValue
        return previous
    }

    /// Clears and returns the handle. Subsequent `handle` reads return `nil`.
    public func take() -> OpaquePointer? {
        let previous = raw
        raw = nil
        return previous
    }
}