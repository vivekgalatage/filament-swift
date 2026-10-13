"""Repository rule that downloads and exposes Google Filament v1.77.3."""

FILAMENT_VERSION = "1.77.3"

_RELEASES = {
    "mac_arm64": {
        "url": "https://github.com/google/filament/releases/download/v1.77.3/filament-v1.77.3-mac.tgz",
        "sha256": "c1ef146a7efa504fcdc3aa06aa2db9b2f89d91436fcb87f2b4c15c95862ffeb8",
        "lib_dir": "lib/arm64",
    },
    "mac_x86_64": {
        "url": "https://github.com/google/filament/releases/download/v1.77.3/filament-v1.77.3-mac.tgz",
        "sha256": "c1ef146a7efa504fcdc3aa06aa2db9b2f89d91436fcb87f2b4c15c95862ffeb8",
        "lib_dir": "lib/arm64",
    },
    "linux_x86_64": {
        "url": "https://github.com/google/filament/releases/download/v1.77.3/filament-v1.77.3-linux.tgz",
        "sha256": "6d3391197dcbdec318dd8a7f4e8d6fd0766794231d53c756a1565fd92bba31b2",
        "lib_dir": "lib/x86_64",
    },
    "linux_arm64": {
        "url": "https://github.com/google/filament/releases/download/v1.77.3/filament-v1.77.3-arm-linux.tgz",
        "sha256": "f97e78c63011c82d98eee7bc2a56cccc406e3bc36dbf6db6f3b79c0052ed3fba",
        "lib_dir": "lib/arm64",
    },
    "windows_x86_64": {
        "url": "https://github.com/google/filament/releases/download/v1.77.3/filament-v1.77.3-windows.tgz",
        "sha256": "e8705d817b7a884fa2d185080ceb80dd42c4ba339930d49dedc79b5761215285",
        "lib_dir": "lib/x86_64",
    },
}

def _watch(repository_ctx, path):
    if hasattr(repository_ctx, "watch"):
        repository_ctx.watch(path)

def _build_mac(lib_dir):
    return """\
load("@rules_cc//cc:defs.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
)

cc_library(
    name = "filament",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
    srcs = [
        "{lib_dir}/libfilament.a",
        "{lib_dir}/libbackend.a",
        "{lib_dir}/libbluevk.a",
        "{lib_dir}/libbluegl.a",
        "{lib_dir}/libfilabridge.a",
        "{lib_dir}/libfilaflat.a",
        "{lib_dir}/libutils.a",
        "{lib_dir}/libgeometry.a",
        "{lib_dir}/libsmol-v.a",
        "{lib_dir}/libibl.a",
    ],
    linkopts = [
        "-framework", "Metal",
        "-framework", "MetalKit",
        "-framework", "CoreGraphics",
        "-framework", "QuartzCore",
        "-framework", "Cocoa",
        "-lc++",
    ],
)

cc_library(
    name = "gltfio",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
    srcs = [
        "{lib_dir}/libgltfio.a",
        "{lib_dir}/libgltfio_core.a",
        "{lib_dir}/libdracodec.a",
        "{lib_dir}/libbasis_transcoder.a",
        "{lib_dir}/libmeshoptimizer.a",
        "{lib_dir}/libuberarchive.a",
        "{lib_dir}/libuberzlib.a",
        "{lib_dir}/libzstd.a",
        "{lib_dir}/libstb.a",
        "{lib_dir}/libktxreader.a",
    ],
    deps = [":filament"],
)

cc_library(
    name = "all",
    deps = [
        ":filament",
        ":gltfio",
    ],
)

filegroup(
    name = "matc",
    srcs = glob(["bin/matc"], allow_empty = True),
)

filegroup(
    name = "filament_files",
    srcs = glob(["**"], exclude = ["BUILD.bazel", "WORKSPACE"]),
)
""".format(lib_dir = lib_dir)

def _build_linux(lib_dir):
    return """\
load("@rules_cc//cc:defs.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
)

cc_library(
    name = "filament",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
    srcs = [
        "{lib_dir}/libfilament.a",
        "{lib_dir}/libbackend.a",
        "{lib_dir}/libbluevk.a",
        "{lib_dir}/libbluegl.a",
        "{lib_dir}/libfilabridge.a",
        "{lib_dir}/libfilaflat.a",
        "{lib_dir}/libutils.a",
        "{lib_dir}/libgeometry.a",
        "{lib_dir}/libsmol-v.a",
        "{lib_dir}/libibl.a",
    ],
    linkopts = [
        "-lpthread",
        "-ldl",
        "-lX11",
        "-lc++",
        "-lc++abi",
    ],
)

cc_library(
    name = "gltfio",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
    srcs = [
        "{lib_dir}/libgltfio.a",
        "{lib_dir}/libgltfio_core.a",
        "{lib_dir}/libdracodec.a",
        "{lib_dir}/libbasis_transcoder.a",
        "{lib_dir}/libmeshoptimizer.a",
        "{lib_dir}/libuberarchive.a",
        "{lib_dir}/libuberzlib.a",
        "{lib_dir}/libzstd.a",
        "{lib_dir}/libstb.a",
        "{lib_dir}/libktxreader.a",
    ],
    deps = [":filament"],
)

cc_library(
    name = "all",
    deps = [
        ":filament",
        ":gltfio",
    ],
)

filegroup(
    name = "matc",
    srcs = glob(["bin/matc"], allow_empty = True),
)

filegroup(
    name = "filament_files",
    srcs = glob(["**"], exclude = ["BUILD.bazel", "WORKSPACE"]),
)
""".format(lib_dir = lib_dir)

def _build_windows(lib_dir):
    return """\
load("@rules_cc//cc:defs.bzl", "cc_library")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "headers",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
)

cc_library(
    name = "filament",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
    srcs = [
        "{lib_dir}/filament.lib",
        "{lib_dir}/backend.lib",
        "{lib_dir}/bluevk.lib",
        "{lib_dir}/bluegl.lib",
        "{lib_dir}/filabridge.lib",
        "{lib_dir}/filaflat.lib",
        "{lib_dir}/utils.lib",
        "{lib_dir}/geometry.lib",
        "{lib_dir}/smol-v.lib",
        "{lib_dir}/ibl.lib",
    ],
    linkopts = [
        "gdi32.lib",
        "user32.lib",
        "opengl32.lib",
        "shlwapi.lib",
        "dwmapi.lib",
        "ole32.lib",
        "shell32.lib",
    ],
)

cc_library(
    name = "gltfio",
    hdrs = glob(["include/**/*.h"], allow_empty = True),
    includes = ["include"],
    srcs = [
        "{lib_dir}/gltfio.lib",
        "{lib_dir}/gltfio_core.lib",
        "{lib_dir}/dracodec.lib",
        "{lib_dir}/basis_transcoder.lib",
        "{lib_dir}/meshoptimizer.lib",
        "{lib_dir}/uberarchive.lib",
        "{lib_dir}/uberzlib.lib",
        "{lib_dir}/zstd.lib",
        "{lib_dir}/stb.lib",
        "{lib_dir}/ktxreader.lib",
    ],
    deps = [":filament"],
)

cc_library(
    name = "all",
    deps = [
        ":filament",
        ":gltfio",
    ],
)

filegroup(
    name = "matc",
    srcs = glob(["bin/matc.exe", "bin/matc"], allow_empty = True),
)

filegroup(
    name = "filament_files",
    srcs = glob(["**"], exclude = ["BUILD.bazel", "WORKSPACE"]),
)
""".format(lib_dir = lib_dir)

def _filament_repo_impl(repository_ctx):
    os_name = repository_ctx.os.name.lower()
    is_macos = "mac" in os_name or "darwin" in os_name
    is_windows = "windows" in os_name
    is_linux = "linux" in os_name

    arch = repository_ctx.os.arch.lower()
    is_arm = "arm" in arch or "aarch64" in arch

    if is_macos:
        key = "mac_arm64" if is_arm else "mac_x86_64"
    elif is_windows:
        key = "windows_x86_64"
    elif is_linux:
        key = "linux_arm64" if is_arm else "linux_x86_64"
    else:
        fail("Unsupported OS for Google Filament: " + os_name)

    release_info = _RELEASES[key]

    dir_env = repository_ctx.os.environ.get("FILAMENT_DIR", "").strip()
    tgz_env = repository_ctx.os.environ.get("FILAMENT_TGZ", "").strip()
    url_env = repository_ctx.os.environ.get("FILAMENT_URL", "").strip()
    sha_env = repository_ctx.os.environ.get("FILAMENT_SHA256", "").strip()

    root = repository_ctx.path(Label("//:MODULE.bazel")).dirname
    local_cache = root.get_child(".filament")

    if dir_env:
        dir_path = repository_ctx.path(dir_env)
        _watch(repository_ctx, dir_path)
        if not dir_path.exists:
            fail("FILAMENT_DIR path does not exist: " + str(dir_path))
        for item in ["include", "lib", "bin"]:
            sub = dir_path.get_child(item)
            if sub.exists:
                repository_ctx.symlink(sub, item)
    elif tgz_env:
        tgz_path = repository_ctx.path(tgz_env)
        _watch(repository_ctx, tgz_path)
        if not tgz_path.exists:
            fail("FILAMENT_TGZ path does not exist: " + str(tgz_path))
        repository_ctx.extract(tgz_path, output = "")
    elif local_cache.get_child("include").get_child("filament").get_child("Engine.h").exists:
        _watch(repository_ctx, local_cache)
        for item in ["include", "lib", "bin"]:
            sub = local_cache.get_child(item)
            if sub.exists:
                repository_ctx.symlink(sub, item)
    else:
        url = url_env if url_env else release_info["url"]
        sha256 = sha_env if sha_env else release_info["sha256"]
        repository_ctx.download_and_extract(url = url, sha256 = sha256, output = "")

    if repository_ctx.path("filament").exists:
        if repository_ctx.path("filament/include").exists and not repository_ctx.path("include").exists:
            repository_ctx.symlink("filament/include", "include")
        if repository_ctx.path("filament/lib").exists and not repository_ctx.path("lib").exists:
            repository_ctx.symlink("filament/lib", "lib")
        if repository_ctx.path("filament/bin").exists and not repository_ctx.path("bin").exists:
            repository_ctx.symlink("filament/bin", "bin")

    lib_dir = release_info["lib_dir"]
    if not repository_ctx.path(lib_dir).exists:
        for cand in ["lib/arm64", "lib/aarch64", "lib/x86_64", "lib"]:
            if repository_ctx.path(cand).exists:
                lib_dir = cand
                break

    if is_windows and repository_ctx.path(lib_dir + "/md").exists:
        lib_dir = lib_dir + "/md"

    if is_macos:
        content = _build_mac(lib_dir)
    elif is_linux:
        content = _build_linux(lib_dir)
    else:
        content = _build_windows(lib_dir)

    repository_ctx.file("BUILD.bazel", content = content)
    repository_ctx.file("WORKSPACE", "")

filament_repo = repository_rule(
    implementation = _filament_repo_impl,
    environ = [
        "FILAMENT_DIR",
        "FILAMENT_TGZ",
        "FILAMENT_URL",
        "FILAMENT_SHA256",
    ],
    doc = "Downloads or vendors Google Filament v1.77.3 for macOS, Linux, and Windows.",
)
