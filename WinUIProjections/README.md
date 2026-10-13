# WinUI 3 projections + demo (Windows)

This directory holds two things: the **generated WinRT projections** consumed by the
`WinUI3Demo` demo, and the script that produces them.

```
WinUIProjections/
├── Package.swift                # declares the projection targets once generated
├── projections.json             # include/exclude allow-list per namespace
├── scripts/generate_winui_projection.py
└── Sources/
    ├── WinRTVersion/            # always present; keeps the manifest resolvable
    └── {CWinRT,WindowsFoundation,UWP,WinAppSDK,WinUI}/   # generated, gitignored
```

The projections are a separate package because SwiftPM can only read sources inside its own
package root — generated code has to be a target of *some* package, and this keeps
machine-generated files out of the library's `Sources/`.

---

# The demo

A **WinUI 3** demo for Filament: a Win32 top-level window with two child windows — one
owning the Filament swap chain, one hosting a real WinUI 3 XAML island (`Microsoft.UI.Xaml`
controls) for the PBR panel.

```
Win32 top-level window  (WS_CLIPCHILDREN)
├── render child HWND  → Filament Vulkan swap chain
└── panel  child HWND  → DesktopWindowXamlSource (WinUI 3 XAML island)
```

**Two child windows instead of a `SwapChainPanel`** is the key design decision, and it
comes from the working reference in `vaiu/src/setu`: XAML gives a `SwapChainPanel` its own
hidden child HWND, so hosting one means hunting for that HWND to hand to
`Engine::createSwapChain`. Sibling child windows sidestep the whole problem, keep the
Filament surface from being composited through XAML, and let a plain Win32 `WM_SIZE` drive
the layout.

The UI is built **in code**, not XAML markup. That is what keeps this out of MSBuild's
`XamlCompiler` and therefore buildable by SwiftPM.

---

## Provenance

The WinUI 3 interop here is **not invented** — it is modelled on a project that already
does exactly this: [`vaiu/src/setu`](https://github.com/) (`shell/Sources/SetuApp`), whose
generated projection is checked into `Sources/{CWinUI,WinAppSDK,UWP}`. Everything below
was read off that working code, which is why there are no `VERIFY:` markers in the sources:

| Concern | Verified API |
| --- | --- |
| Island setup | `DesktopWindowXamlSource()`, `try x.initialize(WinAppSDK.WindowId(value: UInt64(UInt(bitPattern: hwnd))))`, `x.content = <UIElement>` |
| Events | `button.click.addHandler { _, _ in … }` — events are `Event<WinUI.RoutedEventHandler>` |
| Structs | `WinUI.Thickness(left:top:right:)`, `WinUI.CornerRadius(topLeft:…)` |
| Brushes | `SolidColorBrush(UWP.Color(a:r:g:b:))` |
| Layout | `.width/.height` are `Double` (DIPs); `Grid.setColumn(el, n) throws` |
| XAML metadata | `class App: Application, IXamlMetadataProvider` + `queryInterface` forwarding |
| Runtime | `RoInitialize(RO_INIT_SINGLETHREADED)` then `MddBootstrapInitialize2` |

**Not yet verified:** `Slider`, `CheckBox` and `ComboBox`. They are not in the reference
projection, so they are marked `NEW` in `projections.json` and are the first thing to check
if the build fails in the control panel.

> ## Status: unverified
>
> Written **without access to a Windows machine**. Nothing here has been compiled, linked
> or run. The structure, architecture and API usage come from a known-working project, so
> the risk is concentrated in the three `NEW` control types and the codegen step. Treat the
> first build as a debugging session.

---

## Prerequisites

- Windows 10 1809+ / Windows 11
- **Swift 6.x for Windows**
- **Windows 10/11 SDK** (`Windows.winmd`)
- **Windows App Runtime 1.6** installed on the machine:
  ```powershell
  winget install Microsoft.WindowsAppRuntime.1.6
  ```

`swiftwinrt.exe` (`TheBrowserCompany.SwiftWinRT` `0.6.0`) and the `Microsoft.WindowsAppSDK`
(`1.6.250602001`) NuGet package are downloaded and extracted automatically by
`generate_winui_projection.py`.

## Build & Run

```powershell
# 1. Generate the WinRT projections (once; re-run when projections.json changes)
python WinUIProjections\scripts\generate_winui_projection.py

# 2. Build + run the WinUI 3 demo (SwiftPM or Bazel)
swift run --package-path Examples WinUI3Demo
# or:
bazel run //Examples:WinUI3Demo
```

`generate_winui_projection.py` writes `CWinRT`, `WindowsFoundation`, `UWP`, `WinAppSDK` and
`WinUI` into `WinUIProjections/Sources/`, where that package's `Package.swift` picks them
up as targets **only if they exist** — so a checkout without them still configures and
builds everywhere. `Examples/Package.swift` then adds `//WinUIProjections` as a path
dependency and declares the `WinUI3Demo` target. In Bazel, the projections are `//WinUIProjections:*`
targets and the demo is `//Examples:WinUI3Demo`, declared only once the bindings are present.

## Why SwiftPM works here (and usually doesn't)

WinRT bindings are generated code, and the upstream layout puts them in a *separate*
package that depends on `swift-cwinrt` through a local path — which SwiftPM rejects
([swift-winrt #238]). Generating them into **this** package removes that dependency
entirely; they become ordinary targets of `WinUIProjections`:

```swift
.target(name: "WinUI", dependencies: ["CWinRT", "WindowsFoundation", "UWP", "WinAppSDK"],
        path: "Sources/WinUI", swiftSettings: [.swiftLanguageMode(.v5)])
```

Note the **Swift 5 language mode**: the generated code is not concurrency-annotated, which
is why `WinUI3Demo` imports it with `@preconcurrency`.

One SwiftPM gotcha applies here: for a `.package(path:)` dependency the package identity is
the **directory** name, not the `name:` in its manifest. So `Examples/Package.swift` refers
to the library as `package: "filament-swift"`, not `"FilamentSwift"`.

## Known upstream issues

| Issue | Symptom | Handling |
| --- | --- | --- |
| [#263](https://github.com/thebrowsercompany/swift-winrt/issues/263) | App SDK 1.8+ changed its NuGet layout; generation breaks. | Pinned to a 1.7-era package. The script probes for winmds and fails loudly rather than generating nothing. |
| [#262](https://github.com/thebrowsercompany/swift-winrt/issues/262) | Generated `typealias` wrappers lack `public`. | Patched automatically by `patch_generated()` in the script. |
| [#231](https://github.com/thebrowsercompany/swift-winrt/issues/231) | Projecting everything creates circular module dependencies. | Avoided structurally by the `include` allow-list in `projections.json`. |

## Adding a control

1. Add its namespace to `include` in `WinUIProjections/projections.json`.
2. Re-run `generate_winui_projection.py`.
3. Read the real signature out of `Sources/WinUI/Microsoft.UI.Xaml.Controls.swift` — that
   file is the authoritative API for this project, and it is far faster than guessing.