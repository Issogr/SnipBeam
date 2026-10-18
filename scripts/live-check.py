#!/usr/bin/env python3
"""Run packaged capture checks with a separate, relaunchable visual fixture."""

import argparse
import os
from pathlib import Path
import plistlib
import subprocess


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--performance-test", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    subprocess.run([str(root / "scripts/build-app.sh")], cwd=root, check=True)
    bundle = root / "build/CaptureFixture.app"
    executable = bundle / "Contents/MacOS/CaptureFixture"
    executable.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["swiftc", "-parse-as-library", str(root / "Tests/PerformanceFixture.swift"),
                    "-o", str(executable)], check=True)
    with (bundle / "Contents/Info.plist").open("wb") as output:
        plistlib.dump({"CFBundleIdentifier": "com.example.SnipBeam.CaptureFixture",
                      "CFBundleExecutable": "CaptureFixture", "CFBundleName": "SnipBeam Capture Fixture",
                      "CFBundlePackageType": "APPL"}, output)
    subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)

    fixture = app = None
    try:
        fixture = subprocess.Popen([str(executable)], stdout=subprocess.DEVNULL)
        mode = "--performance-test" if args.performance_test else "--smoke-test"
        app = subprocess.Popen([str(root / "build/SnipBeam.app/Contents/MacOS/SnipBeam"), mode],
                               env={**os.environ, "SNIPBEAM_SANDBOX_PROBE": str(root / "Package.swift")},
                               stdout=subprocess.PIPE, text=True)
        for line in app.stdout:
            print(line, end="", flush=True)
            if line.strip() == "FIXTURE: relaunch":
                stop(fixture)
                fixture = subprocess.Popen([str(executable)], stdout=subprocess.DEVNULL)
        return app.wait()
    finally:
        stop(app)
        stop(fixture)


if __name__ == "__main__":
    raise SystemExit(main())
