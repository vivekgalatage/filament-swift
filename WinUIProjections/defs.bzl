"""Macros for the generated WinUI 3 projections.

BUILD files cannot contain `if` statements or `def` functions, so the "only declare a
module once its generated sources exist" logic lives here.
"""

load("@rules_cc//cc:defs.bzl", "cc_library")
load("@rules_swift//swift:swift.bzl", "swift_library")

# Ordered by dependency: each module needs the ones before it.
PROJECTION_MODULES = {
    "CWinRT": [],
    "WindowsFoundation": [":CWinRT"],
    "UWP": [":CWinRT", ":WindowsFoundation"],
    "WinAppSDK": [":CWinRT", ":WindowsFoundation", ":UWP"],
    "WinUI": [":CWinRT", ":WindowsFoundation", ":UWP", ":WinAppSDK"],
}

def declare_projections(modules = PROJECTION_MODULES, visibility = ["//visibility:public"]):
    """Declares a library per generated projection module.

    Skips any module whose sources have not been generated yet, so a fresh checkout builds
    cleanly on every platform.

    Args:
      modules: dict of module name -> list of labels it depends on.
      visibility: visibility for each declared target.
    """
    for module, deps in modules.items():
        if module == "CWinRT":
            hdrs = native.glob(["Sources/CWinRT/include/**/*.h"], allow_empty = True)
            if not hdrs:
                continue
            c_srcs = native.glob(["Sources/CWinRT/**/*.c"], allow_empty = True)
            cc_library(
                name = "CWinRT",
                 srcs = c_srcs,
                hdrs = hdrs,
                includes = ["Sources/CWinRT/include"],
                deps = deps,
                visibility = visibility,
            )
            continue

        srcs = native.glob(["Sources/" + module + "/**/*.swift"], allow_empty = True)
        if not srcs:
            continue

        # Swift 5 language mode: the generated code carries no concurrency annotations,
        # which is why the demo imports it with `@preconcurrency` from a Swift 6 target.
        swift_library(
            name = module,
            srcs = srcs,
            copts = ["-swift-version", "5"],
            deps = deps,
            visibility = visibility,
        )