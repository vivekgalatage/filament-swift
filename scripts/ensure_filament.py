#!/usr/bin/env python3
"""Cross-platform script to fetch and unpack Google Filament v1.77.3.

Downloads the official prebuilt binary archive from GitHub releases for the
current OS (macOS, Linux, Windows) and architecture (arm64, x86_64), verifies
its SHA256 checksum, and unpacks it into `<repo>/.filament`.

Usage:
    python3 scripts/ensure_filament.py [--print-include | --print-lib | --check-only]
"""

import argparse
import hashlib
import os
import platform
import shutil
import sys
import tarfile
import tempfile
import urllib.request

FILAMENT_VERSION = "1.77.3"

RELEASES = {
    ("Darwin", "arm64"): {
        "url": f"https://github.com/google/filament/releases/download/v{FILAMENT_VERSION}/filament-v{FILAMENT_VERSION}-mac.tgz",
        "sha256": "c1ef146a7efa504fcdc3aa06aa2db9b2f89d91436fcb87f2b4c15c95862ffeb8",
        "lib_subdir": "lib/arm64",
    },
    ("Darwin", "x86_64"): {
        "url": f"https://github.com/google/filament/releases/download/v{FILAMENT_VERSION}/filament-v{FILAMENT_VERSION}-mac.tgz",
        "sha256": "c1ef146a7efa504fcdc3aa06aa2db9b2f89d91436fcb87f2b4c15c95862ffeb8",
        "lib_subdir": "lib/arm64",
    },
    ("Linux", "x86_64"): {
        "url": f"https://github.com/google/filament/releases/download/v{FILAMENT_VERSION}/filament-v{FILAMENT_VERSION}-linux.tgz",
        "sha256": "6d3391197dcbdec318dd8a7f4e8d6fd0766794231d53c756a1565fd92bba31b2",
        "lib_subdir": "lib/x86_64",
    },
    ("Linux", "aarch64"): {
        "url": f"https://github.com/google/filament/releases/download/v{FILAMENT_VERSION}/filament-v{FILAMENT_VERSION}-arm-linux.tgz",
        "sha256": "f97e78c63011c82d98eee7bc2a56cccc406e3bc36dbf6db6f3b79c0052ed3fba",
        "lib_subdir": "lib/arm64",
    },
    ("Windows", "AMD64"): {
        "url": f"https://github.com/google/filament/releases/download/v{FILAMENT_VERSION}/filament-v{FILAMENT_VERSION}-windows.tgz",
        "sha256": "e8705d817b7a884fa2d185080ceb80dd42c4ba339930d49dedc79b5761215285",
        "lib_subdir": "lib/x86_64/md",
    },
    ("Windows", "x86_64"): {
        "url": f"https://github.com/google/filament/releases/download/v{FILAMENT_VERSION}/filament-v{FILAMENT_VERSION}-windows.tgz",
        "sha256": "e8705d817b7a884fa2d185080ceb80dd42c4ba339930d49dedc79b5761215285",
        "lib_subdir": "lib/x86_64/md",
    },
}


def log(msg: str):
    sys.stderr.write(f"filament: {msg}\n")
    sys.stderr.flush()


def get_platform_info():
    sys_name = platform.system()
    machine = platform.machine()
    key = (sys_name, machine)
    if key in RELEASES:
        return RELEASES[key]
    if sys_name == "Linux" and machine in ("arm64", "aarch64"):
        return RELEASES[("Linux", "aarch64")]
    if sys_name == "Darwin":
        return RELEASES[("Darwin", "arm64")]
    if sys_name == "Windows":
        return RELEASES[("Windows", "AMD64")]
    raise RuntimeError(f"Unsupported platform: {sys_name} {machine}")


def download_with_sha256(url: str, expected_sha: str, dest_path: str):
    log(f"downloading {url} ...")
    h = hashlib.sha256()
    req = urllib.request.Request(url, headers={"User-Agent": "Filament-Swift-Fetch/1.0"})
    with urllib.request.urlopen(req) as resp, open(dest_path, "wb") as f:
        total = int(resp.headers.get("Content-Length", 0))
        downloaded = 0
        chunk_size = 1024 * 1024
        while True:
            chunk = resp.read(chunk_size)
            if not chunk:
                break
            f.write(chunk)
            h.update(chunk)
            downloaded += len(chunk)
            if total > 0:
                pct = (downloaded / total) * 100
                sys.stderr.write(f"\rfilament: downloading {downloaded // (1024*1024)}MB / {total // (1024*1024)}MB ({pct:.1f}%)")
                sys.stderr.flush()
    sys.stderr.write("\n")
    digest = h.hexdigest()
    if digest.lower() != expected_sha.lower():
        raise ValueError(f"SHA256 mismatch for {url}: expected {expected_sha}, got {digest}")
    log("checksum verified.")


def ensure_filament(output_dir: str = None) -> str:
    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    target_dir = output_dir or os.path.join(repo_dir, ".filament")
    header_check = os.path.join(target_dir, "include", "filament", "Engine.h")

    if os.path.isfile(header_check):
        return target_dir

    env_dir = os.environ.get("FILAMENT_DIR", "").strip()
    if env_dir and os.path.isfile(os.path.join(env_dir, "include", "filament", "Engine.h")):
        return env_dir

    info = get_platform_info()
    os.makedirs(os.path.dirname(target_dir), exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="filament_download_") as tmp_dir:
        archive_path = os.path.join(tmp_dir, "filament.tgz")
        local_archive = os.environ.get("FILAMENT_TGZ", "").strip()

        if local_archive and os.path.isfile(local_archive):
            log(f"using local archive: {local_archive}")
            shutil.copyfile(local_archive, archive_path)
        else:
            download_with_sha256(info["url"], info["sha256"], archive_path)

        unpack_dir = os.path.join(tmp_dir, "unpacked")
        os.makedirs(unpack_dir, exist_ok=True)
        log("extracting archive...")
        with tarfile.open(archive_path, "r:*") as tar:
            tar.extractall(path=unpack_dir)

        src_root = unpack_dir
        if os.path.isdir(os.path.join(unpack_dir, "filament")):
            src_root = os.path.join(unpack_dir, "filament")

        tmp_target = target_dir + ".tmp"
        if os.path.exists(tmp_target):
            shutil.rmtree(tmp_target, ignore_errors=True)

        shutil.move(src_root, tmp_target)

        if os.path.exists(target_dir):
            shutil.rmtree(target_dir, ignore_errors=True)
        os.replace(tmp_target, target_dir)

    log(f"successfully installed Filament v{FILAMENT_VERSION} into {target_dir}")
    return target_dir


def main():
    parser = argparse.ArgumentParser(description="Ensure Google Filament v1.77.3 is available.")
    parser.add_argument("--output-dir", help="Custom output directory")
    parser.add_argument("--print-include", action="store_true", help="Print include directory path")
    parser.add_argument("--print-lib", action="store_true", help="Print platform library directory path")
    parser.add_argument("--check-only", action="store_true", help="Check without downloading")
    args = parser.parse_args()

    script_dir = os.path.dirname(os.path.abspath(__file__))
    repo_dir = os.path.dirname(script_dir)
    target_dir = args.output_dir or os.path.join(repo_dir, ".filament")
    header_check = os.path.join(target_dir, "include", "filament", "Engine.h")

    if args.check_only:
        if os.path.isfile(header_check):
            print(target_dir)
            sys.exit(0)
        else:
            sys.exit(1)

    filament_dir = ensure_filament(args.output_dir)
    info = get_platform_info()

    if args.print_include:
        print(os.path.join(filament_dir, "include"))
    elif args.print_lib:
        lib_path = os.path.join(filament_dir, info["lib_subdir"])
        if not os.path.isdir(lib_path):
            lib_path = os.path.join(filament_dir, "lib")
        print(lib_path)
    else:
        print(filament_dir)


if __name__ == "__main__":
    main()
