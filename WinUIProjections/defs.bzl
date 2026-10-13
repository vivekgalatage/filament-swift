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

    Always declares all projection targets so dependents (like `//Examples:WinUI3Demo`) never
    fail target loading. Any module whose generated sources are not yet on disk is marked
    `target_compatible_with = [":projections_not_generated"]`, so `bazel build //...` cleanly
    skips it until `WinUIProjections/scripts/generate_winui_projection.py` has been run.

    Args:
      modules: dict of module name -> list of labels it depends on.
      visibility: visibility for each declared target.
    """
    for module, deps in modules.items():
        if module == "CWinRT":
            hdrs = native.glob(["Sources/CWinRT/include/**/*.h"], allow_empty = True)
            textual_hdrs = native.glob(["Sources/CWinRT/include/**/*.modulemap"], allow_empty = True)
            c_srcs = native.glob(["Sources/CWinRT/**/*.c"], allow_empty = True)
            compat = ["@platforms//os:windows"] if hdrs else [":projections_not_generated"]
            cc_library(
                name = "CWinRT",
                srcs = c_srcs,
                hdrs = hdrs,
                textual_hdrs = textual_hdrs,
                includes = ["Sources/CWinRT/include"] if hdrs else [],
                target_compatible_with = compat,
                deps = deps,
                visibility = visibility,
            )
            continue

        srcs = native.glob(["Sources/" + module + "/**/*.swift"], allow_empty = True)
        compat = ["@platforms//os:windows"] if srcs else [":projections_not_generated"]

        # Swift 5 language mode: the generated code carries no concurrency annotations,
        # which is why the demo imports it with `@preconcurrency` from a Swift 6 target.
        swift_library(
            name = module,
            module_name = module,
            srcs = srcs if srcs else ["Sources/WinRTVersion/WinRTVersion.swift"],
            copts = ["-swift-version", "5"],
            target_compatible_with = compat,
            deps = deps,
            visibility = visibility,
        )