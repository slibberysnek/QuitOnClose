#!/usr/bin/env python3
"""Build and package QuitOnClose using only Apple's tools and Python's standard library."""

import argparse
import hashlib
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"


def run(*args):
    subprocess.run([str(arg) for arg in args], check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["universal", "arm64", "x86_64"], default="universal")
    parser.add_argument("--sign", default="-", help="Code signing identity; default: ad-hoc")
    options = parser.parse_args()
    if sys.platform != "darwin":
        parser.error("Building requires macOS and Apple's Command Line Tools.")

    version = (ROOT / "VERSION").read_text().strip()
    app = BUILD / "QuitOnClose.app"
    if app.exists():
        shutil.rmtree(app)
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    with (ROOT / "Resources/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    info["CFBundleShortVersionString"] = version
    with (app / "Contents/Info.plist").open("wb") as stream:
        plistlib.dump(info, stream)
    (app / "Contents/PkgInfo").write_bytes(b"APPL????")

    iconset = BUILD / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    run("swift", "-module-cache-path", BUILD / "module-cache", ROOT / "scripts/make-icon.swift", iconset)
    run("iconutil", "-c", "icns", iconset, "-o", resources / "AppIcon.icns")

    architectures = ["arm64", "x86_64"] if options.arch == "universal" else [options.arch]
    sources = sorted((ROOT / "Sources/QuitOnClose").glob("*.swift"))
    binaries = []
    for architecture in architectures:
        binary = BUILD / ("QuitOnClose-" + architecture)
        run("swiftc", "-module-cache-path", BUILD / "module-cache", "-module-name", "QuitOnClose",
            "-target", architecture + "-apple-macosx13.0", "-O", "-warnings-as-errors",
            "-file-prefix-map", str(ROOT) + "=.", "-debug-prefix-map", str(ROOT) + "=.",
            *sources, "-o", binary)
        binaries.append(binary)
    executable = macos / "QuitOnClose"
    if len(binaries) == 2:
        run("lipo", "-create", *binaries, "-output", executable)
    else:
        shutil.copy2(binaries[0], executable)

    run("codesign", "--force", "--sign", options.sign, "--identifier", info["CFBundleIdentifier"],
        "--options", "runtime", "--entitlements", ROOT / "Resources/QuitOnClose.entitlements", app)
    run("codesign", "--verify", "--deep", "--strict", app)
    archive = BUILD / ("QuitOnClose-macOS-" + options.arch + ".zip")
    if archive.exists():
        archive.unlink()
    run("ditto", "-c", "-k", "--keepParent", "--norsrc", app, archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (BUILD / "SHA256SUMS").write_text(digest + "  " + archive.name + "\n")
    print("Built " + str(app))
    print("Packaged " + str(archive))


if __name__ == "__main__":
    main()
