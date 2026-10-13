#!/usr/bin/env python3
"""Generate the native Swift WinRT projections that the WinUI 3 demo needs.

Runs swiftwinrt.exe against the Windows App SDK + Windows SDK metadata and writes
the generated Swift modules straight into ``../Sources/`` so they become ordinary
SwiftPM targets of this package:

    Sources/CWinRT  Sources/WindowsFoundation  Sources/UWP  Sources/WinAppSDK  Sources/WinUI

Keeping the generated modules *inside this package* is what makes SwiftPM work at
all: they are targets of the same package, so there is no cross-package
local-path dependency (which is why the upstream multi-repo layout had to move to
CMake -- see thebrowsercompany/swift-winrt #238).

Windows-only. Run once, and again whenever ``projections.json`` changes:

    python WinUIProjections/scripts/generate_winui_projection.py

Optional overrides (all default to the layout used by vaiu/src/setu):

    --swiftwinrt   path to swiftwinrt.exe
    --nuget-dir    directory containing the extracted Microsoft.WindowsAppSDK package
    --windows-winmd path to Windows.winmd from the Windows SDK
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# swiftwinrt writes one directory per module under <output>/Sources/.
MODULES = ["CWinRT", "WindowsFoundation", "UWP", "WinAppSDK", "WinUI"]

# Metadata the projections need but never emit themselves.
KNOWN_ISSUES = """
Known upstream issues this inherits (not bugs in this script):
  * swift-winrt #231 - projecting everything creates circular module dependencies.
    Avoided by the explicit `include` allow-list in projections.json.
  * swift-winrt #262 - some generated `typealias` wrappers are emitted without
    `public`, which breaks importing modules. Fixed below.
  * swift-winrt #263 - Windows App SDK 1.8 changed its NuGet layout and breaks
    generation. Pinned to 1.6.250602001 in setup_windows.ps1.
"""


def newest_versioned_dir(root: Path, prefix: str):
    """Newest ``<prefix>.<version>`` directory under root.

    Picks the highest version rather than relying on glob ordering, which is
    arbitrary on some filesystems.
    """
    if not root.exists():
        return None

    def version_key(path: Path):
        tail = path.name[len(prefix) + 1:]
        parts = []
        for chunk in tail.split("."):
            parts.append(int(chunk) if chunk.isdigit() else -1)
        return parts

    candidates = [p for p in root.glob(prefix + ".*") if p.is_dir()]
    if not candidates:
        return None
    return max(candidates, key=version_key)


def find_windows_winmd(explicit: Path | None) -> Path | None:
    if explicit:
        return explicit if explicit.exists() else None
    # Windows.winmd ships with the Windows SDK; check UnionMetadata and References.
    env = os.environ.get("WindowsSdkDir")
    roots = []
    if env:
        roots.append(Path(env) / "UnionMetadata")
        roots.append(Path(env) / "References")
        roots.append(Path(env))
    roots += [
        Path(r"C:\Program Files (x86)\Windows Kits\10\UnionMetadata"),
        Path(r"C:\Program Files (x86)\Windows Kits\10\References"),
        Path(r"C:\Program Files\Windows Kits\10\UnionMetadata"),
        Path(r"C:\Program Files\Windows Kits\10\References"),
    ]
    for root in roots:
        if not root.exists():
            continue
        hits = sorted(root.rglob("Windows.winmd"), reverse=True)
        if hits:
            return hits[0]
    return None


def patch_generated(output_root: Path) -> int:
    """Add `public` to generated typealias wrappers (swift-winrt #262)."""
    import re

    pattern = re.compile(r"(?m)^(\s*)typealias\s+(\w*(?:Handler|Event|Callback|Action)Wrapper)\s*=")
    patched = 0
    for swift_file in output_root.rglob("*.swift"):
        text = swift_file.read_text(encoding="utf-8")
        updated = pattern.sub(r"\1public typealias \2 =", text)
        if updated != text:
            swift_file.write_text(updated, encoding="utf-8")
            patched += 1
    return patched


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    default_projections = repo_root / "WinUIProjections" / "projections.json"

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--swiftwinrt", type=Path, default=None,
                        help="path to swiftwinrt.exe (bootstrapped by setup_windows.ps1)")
    parser.add_argument("--nuget-dir", type=Path, default=None,
                        help="directory holding Microsoft.WindowsAppSDK (bootstrapped by setup_windows.ps1)")
    parser.add_argument("--windows-winmd", type=Path, default=None,
                        help="path to Windows.winmd from the Windows SDK")
    parser.add_argument("--projections", type=Path, default=default_projections)
    args = parser.parse_args()

    if not args.projections.exists():
        print(f"error: projections.json not found at {args.projections}", file=sys.stderr)
        return 1
    config = json.loads(args.projections.read_text(encoding="utf-8"))

    # 1. Locate swiftwinrt.exe (bootstrapped by setup_windows.ps1).
    swiftwinrt = args.swiftwinrt
    if swiftwinrt is None:
        candidates = [
            repo_root / "WinUIProjections" / "_tools" / "swiftwinrt" / "bin" / "swiftwinrt.exe",
            repo_root / "tools" / "swiftwinrt" / "bin" / "swiftwinrt.exe",
            repo_root / "WinUIProjections" / "_tools" / "swiftwinrt" / "build" / "Release" / "swiftwinrt.exe",
        ]
        swiftwinrt = next((c for c in candidates if c.exists()), None)
    if swiftwinrt is None or not swiftwinrt.exists():
        print("error: swiftwinrt.exe not found. Run .\\setup_windows.ps1 first to bootstrap "
              "SwiftWinRT, WindowsAppSDK, and generate projections.", file=sys.stderr)
        return 1
    print(f"Using swiftwinrt: {swiftwinrt}")

    # 2. Locate Windows SDK metadata + Windows App SDK NuGet package.
    windows_winmd = find_windows_winmd(args.windows_winmd)
    if windows_winmd is None:
        print("error: Windows.winmd not found. Install the Windows 10/11 SDK or pass --windows-winmd.",
              file=sys.stderr)
        return 1

    search_dirs = [args.nuget_dir] if args.nuget_dir else [
        repo_root / "WinUIProjections" / "_packages",
        repo_root / "tools" / "nuget_packages",
    ]
    wasdk_dir = next(
        (d for root in search_dirs if root for d in [newest_versioned_dir(root, "Microsoft.WindowsAppSDK")] if d),
        None,
    )
    if wasdk_dir is None:
        print("error: Microsoft.WindowsAppSDK package not found. Run .\\setup_windows.ps1 first "
              "to bootstrap dependencies.", file=sys.stderr)
        return 1
    print(f"Using Windows App SDK: {wasdk_dir}")

    # uap10.0 holds Microsoft.UI.Xaml et al; uap10.0.18362 holds the SDK contracts the
    # projections reference.
    winmd_inputs = sorted(str(p) for p in wasdk_dir.glob("lib/uap10.0/*.winmd"))
    winmd_inputs += sorted(str(p) for p in wasdk_dir.glob("lib/uap10.0.18362/*.winmd"))
    if not winmd_inputs:
        print(f"error: no winmd under {wasdk_dir}/lib/uap10.0. The package layout changed "
              "(swift-winrt #263); pin an older Windows App SDK in projections.json.",
              file=sys.stderr)
        return 1
    print(f"Using {len(winmd_inputs)} winmd input(s); reference {windows_winmd}")

    # 3. Run swiftwinrt once; it emits every module under <output>/Sources/.
    out_dir = repo_root / "WinUIProjections" / "_projection"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    cmd = [
        str(swiftwinrt),
        "-reference", str(windows_winmd),
        "-support", "WindowsFoundation",
        "-output", str(out_dir),
        "-overwrite",
    ]
    for ns in config.get("include", []):
        cmd += ["-include", ns]
    for ns in config.get("exclude", []):
        cmd += ["-exclude", ns]
    for winmd in winmd_inputs:
        cmd += ["-input", winmd]

    print(f"[swiftwinrt] {len(cmd)} arguments, output -> {out_dir}")
    result = subprocess.run(cmd, cwd=str(repo_root))
    if result.returncode != 0:
        print(f"error: swiftwinrt failed with {result.returncode}", file=sys.stderr)
        return result.returncode

    # 4. Patch, then move the modules into WinUIProjections/Sources/ where SwiftPM finds them.
    generated_sources = out_dir / "Sources"
    patched = patch_generated(out_dir)
    if patched:
        print(f"[patch] added `public` to generated wrappers in {patched} file(s) (#262)")

    sources_root = repo_root / "WinUIProjections" / "Sources"
    synced = 0
    for module in MODULES:
        src = generated_sources / module
        if not src.exists():
            print(f"  [skip] {module}: not produced by swiftwinrt")
            continue
        dst = sources_root / module
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        print(f"  [sync] {module} -> {dst}")
        synced += 1

    if synced == 0:
        print("error: no modules generated", file=sys.stderr)
        return 1

    shutil.rmtree(out_dir, ignore_errors=True)
    print("\nDone. Run the WinUI 3 demo with:")
    print("  swift run --package-path Examples WinUI3Demo")
    print("  # or: bazel run //Examples:WinUI3Demo")
    print(KNOWN_ISSUES)
    return 0


if __name__ == "__main__":
    sys.exit(main())