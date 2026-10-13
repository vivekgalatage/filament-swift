/// Reports how the generated WinUI 3 projections were set up.
///
/// Exists so this package always has at least one target, and therefore a manifest that
/// resolves, even before `WinUIProjections/scripts/generate_winui_projection.py` has run
/// on a Windows machine. Consumers can use `projectionsGenerated` to decide whether the
/// WinUI 3 demo target is available.
public enum WinUIProjections {
    /// `true` when the WinRT bindings have been generated into `Sources/`.
    ///
    /// Always `false` on a fresh checkout — generation needs swiftwinrt and the Windows
    /// App SDK, both Windows-only.
    public static var projectionsGenerated: Bool { false }

    /// Human-readable status, handy for diagnosing "target not found" errors.
    public static var status: String {
        projectionsGenerated
            ? "WinRT projections generated."
            : """
              WinRT projections NOT generated. Run, on Windows:
                python WinUIProjections/scripts/generate_winui_projection.py
              """
    }
}