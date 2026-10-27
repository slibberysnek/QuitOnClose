#!/usr/bin/env python3
"""Run deterministic tests without requesting Accessibility or posting input events."""

from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
if sys.platform != "darwin":
    sys.exit("Tests require macOS and Apple's Command Line Tools.")
build = ROOT / "build/tests"
build.mkdir(parents=True, exist_ok=True)
# The test extension shares a file with private implementation details. This
# keeps testing hooks out of the shipped application's public interface.
source = build / "main.swift"
source.write_text((ROOT / "Sources/QuitOnClose/WindowMonitor.swift").read_text() + "\n"
                  + (ROOT / "Tests/WindowMonitorTests.swift").read_text())
executable = build / "WindowMonitorTests"
subprocess.run(["swiftc", "-module-cache-path", str(ROOT / "build/module-cache"),
                "-warnings-as-errors", str(source), "-o", str(executable)], check=True)
subprocess.run([str(executable)], check=True)
