#!/usr/bin/env python3
"""Offline checks for checksum-pinned Homebrew releases."""

import hashlib
import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("homebrew_cask", Path(__file__).with_name("update-homebrew-cask.py"))
homebrew_cask = importlib.util.module_from_spec(spec)
spec.loader.exec_module(homebrew_cask)


class HomebrewCaskTests(unittest.TestCase):
    def test_release_metadata_and_validation(self):
        tag = "update-" + "a" * 40
        info = {
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "42",
            "CFBundleIdentifier": "com.example.SnipBeam",
        }
        with tempfile.TemporaryDirectory(prefix="snipbeam-cask-") as directory:
            archive = Path(directory) / "SnipBeam-macos-arm64.zip"

            def render():
                with zipfile.ZipFile(archive, "w") as package:
                    package.writestr("SnipBeam.app/Contents/Info.plist", plistlib.dumps(info))
                return homebrew_cask.render_cask(tag, archive)

            cask = render()
            self.assertIn('version "0.1.0,42"', cask)
            self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), cask)
            self.assertIn(f"/releases/download/{tag}/SnipBeam-macos-arm64.zip", cask)
            self.assertIn('depends_on arch: :arm64', cask)
            self.assertIn('depends_on macos: :sonoma', cask)
            self.assertIn('app "SnipBeam.app"', cask)
            info["CFBundleVersion"] = "43"
            self.assertIn('version "0.1.0,43"', render())
            for invalid_tag in ["latest", "../main", 'update-#{system("false")}']:
                with self.assertRaises(ValueError):
                    homebrew_cask.render_cask(invalid_tag, archive)
            for key, value in [("CFBundleVersion", "0"), ("CFBundleShortVersionString", '#{system("false")}'),
                               ("CFBundleIdentifier", "another.app")]:
                original = info[key]
                info[key] = value
                with self.assertRaises(ValueError):
                    render()
                info[key] = original


if __name__ == "__main__":
    unittest.main()
