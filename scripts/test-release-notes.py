#!/usr/bin/env python3
"""Offline release checks using disposable Git repositories, not the working repository."""

import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("release-notes.py")
spec = importlib.util.spec_from_file_location("release_notes", SCRIPT)
release_notes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release_notes)


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="snipbeam-release-")
        self.addCleanup(directory.cleanup)
        self.cwd = Path(directory.name)
        self.git("init", "-q", "-b", "main")

    def git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.cwd, text=True, stderr=subprocess.PIPE).strip()

    def commit(self, subject):
        (self.cwd / "content").write_text(subject, encoding="utf-8")
        self.git("add", "content")
        self.git("-c", "user.name=Release Test", "-c", "user.email=release@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", subject)
        return self.git("rev-parse", "HEAD")

    def notes(self, **kwargs):
        return release_notes.get_release_notes(cwd=self.cwd, **kwargs)

    def test_history_and_retry(self):
        base = self.commit("Already released")
        self.git("tag", "published")
        first = self.commit("Skipped publication")
        latest = self.commit("Support [windows] and @users")
        self.git("tag", "update-" + latest)  # Failed/unpublished tags must not become the baseline.
        release = self.notes(base="published", repository="owner/SnipBeam")
        self.assertEqual(release["tag"], "update-" + latest)
        self.assertNotIn("Already released", release["notes"])
        self.assertIn(first, release["notes"])
        self.assertIn(r"Support \[windows\] and \@users", release["notes"])
        self.assertIn(f"/compare/{base}...{latest}", release["notes"])
        self.assertIn("Already released", self.notes()["notes"])
        self.assertIn("/commits/" + latest, self.notes()["notes"])
        self.assertIsNone(self.notes(base="update-" + latest))

    def test_invalid_history_and_metadata(self):
        base = self.commit("Initial")
        latest = self.commit("Published")
        self.git("switch", "-qc", "divergent", base)
        self.commit("Other branch")
        with self.assertRaisesRegex(ValueError, "not an ancestor"):
            self.notes(base=latest)
        self.git("tag", "update-" + latest, base)
        with self.assertRaisesRegex(ValueError, "another commit"):
            self.notes(base=base, ref=latest)
        with self.assertRaises(ValueError):
            self.notes(repository="../invalid")
        with self.assertRaises(subprocess.CalledProcessError):
            self.notes(base="missing")

    def test_actions_outputs(self):
        self.commit("First build")
        output = self.cwd / "outputs"
        env = {**os.environ, "GITHUB_OUTPUT": str(output), "RUNNER_TEMP": str(self.cwd)}
        subprocess.run([sys.executable, str(SCRIPT), "--write"], cwd=self.cwd, env=env, check=True, stdout=subprocess.PIPE)
        self.assertIn("publish=true\ntag=update-", output.read_text())
        self.assertIn("First build", (self.cwd / "snipbeam-release-notes.md").read_text())
        output.write_text("")
        subprocess.run([sys.executable, str(SCRIPT), "--base", "HEAD", "--write"], cwd=self.cwd, env=env, check=True, stdout=subprocess.PIPE)
        self.assertEqual(output.read_text(), "publish=false\n")

    def test_cask_updates_do_not_become_app_releases(self):
        base = self.commit("Published app")
        (self.cwd / "Casks").mkdir()
        (self.cwd / "Casks" / "snipbeam.rb").write_text("cask metadata")
        self.git("add", "Casks")
        self.git("-c", "user.name=Release Test", "-c", "user.email=release@example.invalid",
                 "-c", "commit.gpgsign=false", "commit", "-qm", "Update SnipBeam Homebrew cask")
        self.assertIsNone(self.notes(base=base))
        self.commit("New app feature")
        notes = self.notes(base=base)["notes"]
        self.assertIn("New app feature", notes)
        self.assertNotIn("Update SnipBeam Homebrew cask", notes)
        self.assertIn("brew install --cask issogr/snipbeam/snipbeam", notes)


if __name__ == "__main__":
    unittest.main()
