#!/usr/bin/env python3
"""Commit-based releases, following newsFlow's flow. Offline; never publishes to GitHub."""

import argparse
from datetime import datetime, timezone
import os
from pathlib import Path
import re
import subprocess


def get_release_notes(base="", ref="HEAD", repository="Issogr/SnipBeam", cwd=None):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*", repository):
        raise ValueError("Repository must be owner/name.")

    def git(*args):
        return subprocess.check_output(
            ["git", *args], cwd=cwd, encoding="utf-8", errors="replace", stderr=subprocess.PIPE
        ).strip()

    def resolve(value):
        return git("rev-parse", "--verify", "--end-of-options", value + "^{commit}")

    sha = resolve(ref)
    previous = resolve(base) if base else ""
    if previous == sha:
        return None
    if previous:
        try:
            git("merge-base", "--is-ancestor", previous, sha)
        except subprocess.CalledProcessError as error:
            raise ValueError("Previous release is not an ancestor; refusing older or divergent history.") from error
    tag = "update-" + sha
    if git("tag", "--list", tag) and resolve("refs/tags/" + tag) != sha:
        raise ValueError("Release tag points to another commit: " + tag)

    url = "https://github.com/" + repository
    fields = git("log", "--reverse", "-z", "--format=%H%x00%s", previous + ".." + sha if previous else sha,
                 "--", ".", ":(exclude)Casks").split("\0")
    commits = []
    for index in range(0, len(fields) - 1, 2):
        subject = " ".join(fields[index + 1].split()) or "(no subject)"
        subject = re.sub(r"([\\`*_{}\[\]()<>#!|@])", r"\\\1", subject)
        commit = fields[index]
        commits.append(f"- {subject} ([{commit[:7]}]({url}/commit/{commit}))")
    if not commits:
        return None
    comparison = f"{url}/compare/{previous}...{sha}" if previous else f"{url}/commits/{sha}"
    return {
        "tag": tag,
        "title": f"SnipBeam — {datetime.now(timezone.utc).date().isoformat()} ({sha[:7]})",
        "notes": "## Download\n\nDownload `SnipBeam-macos-arm64.zip`, unzip it, and move `SnipBeam.app` to Applications. "
                 "Requires macOS 14+ on Apple Silicon (arm64).\n\n"
                 "Or install with Homebrew:\n\n```bash\nbrew tap issogr/snipbeam https://github.com/Issogr/SnipBeam\n"
                 "brew install --cask issogr/snipbeam/snipbeam\n```\n\n"
                 "Update with `brew update` followed by `brew upgrade --cask snipbeam`.\n\n"
                 "This build is ad-hoc signed, sandboxed, and not notarized. If macOS blocks it, use "
                 "System Settings → Privacy & Security → Open Anyway after attempting to open the app. "
                 "Screen Recording permission is requested when selecting a region.\n\n"
                 "## Changes\n\n" + "\n".join(commits) + f"\n\n[Full changes]({comparison})\n",
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="", help="Last published release tag; omit for first-release history")
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", "Issogr/SnipBeam"))
    parser.add_argument("--write", action="store_true", help="Write Actions outputs and notes in RUNNER_TEMP")
    args = parser.parse_args()
    if args.write and not (os.environ.get("GITHUB_OUTPUT") and os.environ.get("RUNNER_TEMP")):
        parser.error("--write requires GITHUB_OUTPUT and RUNNER_TEMP")
    release = get_release_notes(args.base, args.ref, args.repository)
    if args.write:
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            if release:
                notes_file = Path(os.environ["RUNNER_TEMP"]) / "snipbeam-release-notes.md"
                notes_file.write_text(release["notes"], encoding="utf-8")
                output.write(f"publish=true\ntag={release['tag']}\ntitle={release['title']}\nnotes_file={notes_file}\n")
            else:
                output.write("publish=false\n")
    print(release["title"] + "\n\n" + release["notes"] if release else "This commit has already been released.")
