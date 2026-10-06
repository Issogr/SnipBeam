#!/usr/bin/env python3
"""Generate the Homebrew cask from a published app ZIP. Offline; does not publish."""

import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import zipfile


def render_cask(tag, archive):
    if not re.fullmatch(r"update-[0-9a-f]{40}", tag):
        raise ValueError("Expected a commit-based release tag: update-<40 lowercase hex digits>.")
    with zipfile.ZipFile(archive) as package:
        info = plistlib.loads(package.read("SnipBeam.app/Contents/Info.plist"))
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("Expected numeric app and build versions.")
    if info["CFBundleIdentifier"] != "com.example.SnipBeam":
        raise ValueError("Archive is not a SnipBeam app.")
    checksum = hashlib.sha256(Path(archive).read_bytes()).hexdigest()
    return f'''cask "snipbeam" do
  version "{version},{build}"
  sha256 "{checksum}"

  url "https://github.com/Issogr/SnipBeam/releases/download/{tag}/SnipBeam-macos-arm64.zip"
  name "SnipBeam"
  desc "Share a selected screen region as a window"
  homepage "https://github.com/Issogr/SnipBeam"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "SnipBeam.app"
  uninstall quit: "com.example.SnipBeam"

  caveats <<~EOS
    SnipBeam is ad-hoc signed and not notarized. If macOS blocks it, attempt
    to open the app, then choose Open Anyway in System Settings > Privacy & Security.

    For a build you trust, you can instead remove only SnipBeam's download quarantine:
      xattr -dr com.apple.quarantine "#{{appdir}}/SnipBeam.app"
      open "#{{appdir}}/SnipBeam.app"
    If xattr reports Permission denied, repeat the xattr command with sudo.

    Screen Recording still requires your approval in System Settings > Privacy & Security.
    Choose Select Region… to request access. For permission troubleshooting, see:
      https://github.com/Issogr/SnipBeam#screen-recording-permission
  EOS
end
'''


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tag")
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    cask = Path(__file__).resolve().parent.parent / "Casks" / "snipbeam.rb"
    cask.write_text(render_cask(args.tag, args.archive), encoding="utf-8")
