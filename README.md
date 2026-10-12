# FilamentSwift

Cross-platform **Swift 6** bindings and host views for **Google Filament** (v1.77.3) with first-class glTF 2.0 / `.glb` support, PBR rendering, and native alpha transparency.

Designed for desktop and mobile: **macOS (AppKit / Metal)**, **Windows (WinUI 3 / Direct3D / Vulkan)**, and **Linux (GTK 4 / Vulkan)**.

---

## Features

- **Direct Swift 6 C++ Interop**: Zero Objective-C++ (`.mm`) boilerplate. Swift calls Filament C++ APIs directly via `-cxx-interoperability-mode=default`.
- **Precompiled Binary Distribution**: Automatically fetches official static libraries for macOS, Linux, and Windows with SHA256 verification (no source compilation needed).
- **True Alpha Transparency**: Built for floating 3D widgets, card overlays, and composited scenes over native OS host views.
- **First-Class GLB Support**: Built-in `gltfio` integration for loading PBR models with textures, animations, and skinning.
- **Both SwiftPM and Bazel**: Use either standard Swift Package Manager or Bazel Bzlmod (`MODULE.bazel`).

---

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vivekgalatage/filament-swift.git", from: "1.77.3"),
]
```

Or reference locally:
```swift
dependencies: [
    .package(path: "path/to/filament-swift"),
]
```

### Bazel (Bzlmod)

Add to `MODULE.bazel`:

```starlark
filament_repo = use_repo_rule("@filament_swift//:filament_repo.bzl", "filament_repo")
filament_repo(name = "filament")
```

---

## Quick Start (macOS AppKit)

```swift
import AppKit
import Filament

final class My3DCardView: NSView {
    private var filamentView: FilamentView!
    private var model: FilamentModel!

    override init(frame: NSRect) {
        super.init(frame: frame)

        // 1. Create transparent Filament view
        filamentView = FilamentView(frame: bounds)
        filamentView.isTransparent = true
        filamentView.autoresizingMask = [.width, .height]
        addSubview(filamentView)

        // 2. Load .glb model
        model = FilamentModel(engine: filamentView.engine)
        if let glbURL = Bundle.main.url(forResource: "avatar", withExtension: "glb") {
            try? model.loadGlb(at: glbURL)
        }
    }
}
```

---

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.
