# SnipBeam

A free, open-source macOS menu-bar app that turns a selected screen region into a normal window you can share in meetings.

Runs locally: no recording, saved frames, uploads, audio capture, accounts, or analytics. Your conferencing app handles sharing.

## Install

Requires an **Apple Silicon Mac running macOS 14 Sonoma or later**.

### Homebrew

With [Homebrew](https://brew.sh) installed:

```bash
brew tap issogr/snipbeam https://github.com/Issogr/SnipBeam
brew install --cask issogr/snipbeam/snipbeam
```

Switching from a manual installation? Quit SnipBeam and move that copy out of Applications before installing with Homebrew.

To update, quit SnipBeam, then run:

```bash
brew update
brew upgrade --cask snipbeam
```

Open **SnipBeam** from Applications. See [First launch](#first-launch) if macOS blocks it.

### Manual download

1. Download **SnipBeam-macos-arm64.zip** from [GitHub Releases](https://github.com/Issogr/SnipBeam/releases). Choose the app ZIP under **Assets**, not the source-code archive.
2. Unzip it and move **SnipBeam.app** to **Applications**.
3. Open SnipBeam and look for the viewfinder icon in the menu bar.

Optional: verify the download with the ZIP and its `.sha256` file in the same directory:

```bash
shasum -a 256 -c SnipBeam-macos-arm64.zip.sha256
```

### First launch

Builds are **ad-hoc signed, not notarized**, including Homebrew installs. If blocked, attempt to open the app, then choose **System Settings → Privacy & Security → Open Anyway** ([Apple's instructions](https://support.apple.com/en-us/102445)).

For a build you trust, you can instead remove its download-quarantine flag:

```bash
xattr -dr com.apple.quarantine "/Applications/SnipBeam.app"
open "/Applications/SnipBeam.app"
```

Use `sudo` only if `xattr` reports **Permission denied**; adjust the path for other install locations. This affects only this app copy and may need repeating after an update. [Screen Recording approval](#screen-recording-permission) is separate.

## Select and share

1. Click the menu-bar icon and choose **Select Region…**.
2. Grant Screen Recording permission when prompted.
3. Drag a rectangle on one display, then release to confirm. **Escape** cancels; the minimum size is **20 × 20 points**.
4. In your conferencing app, choose **Share a window**, then **SnipBeam**.

The preview shows a fixed desktop area. Move other windows into that area to change what appears. SnipBeam excludes its own windows to prevent recursion.

| Control | Behavior |
| --- | --- |
| Resize the preview | Scales the image without changing the captured area. |
| Pause / Resume | Freezes the last frame, then resumes the same region. |
| Stop Sharing / Close preview | Stops active or paused capture and closes the preview. SnipBeam stays in the menu bar. |
| Show Cursor | Shows or hides the pointer in new frames. |
| Hide Title Bar | Hides the title and window buttons. Drag the image to move; uncheck to restore controls. |
| Select Region… again | Replaces the current capture with a new selection. |

Keep the preview open and unminimized while sharing. Compatibility varies by conferencing app, which may need its own Screen Recording permission.

## Screen Recording permission

Enable **SnipBeam** in **System Settings → Privacy & Security → Screen Recording** (or **Screen & System Audio Recording**). If missing, add it with **+**.

Choose **Select Region…** to retry; restart SnipBeam if macOS requests it. Rebuilding or moving an ad-hoc-signed copy may require approval again.

### Reset a stuck permission

If capture still fails, quit SnipBeam and reset its Screen Recording decision:

```bash
tccutil reset ScreenCapture com.example.SnipBeam
open "/Applications/SnipBeam.app"
```

This clears the previous decision, including any approval. Choose **Select Region…** and approve access again in the prompt or System Settings; `tccutil` cannot grant permission.

<details>
<summary>Check the installed app's bundle ID</summary>

```bash
defaults read "/Applications/SnipBeam.app/Contents/Info" CFBundleIdentifier
```

</details>

## Limitations

- One fixed region on one display at a time; no cross-monitor selection or automatic window tracking.
- Display configuration changes, sleep, and user-session switching end capture. Select a region again when you return.
- Protected/DRM content may appear blank. Output is SDR.
- Preview size is not saved between launches.

## Development

Use **Swift 5.9+ and Apple's Command Line Tools**; no Xcode or third-party packages are required. From the repository root:

```bash
xcode-select --install     # Install Command Line Tools if needed
swift build                # Debug build
./scripts/run.sh           # Build, package, sign, and launch
./scripts/build-app.sh     # Release app without launching
./scripts/package-app.sh   # Release ZIP and checksum
```

Packaged output is in `build/`, including `SnipBeam.app`. Quit any running copy before relaunching a rebuild. Packaged apps use App Sandbox and hardened runtime; the raw SwiftPM executable does not. Edit bundle resources in `Resources/`, not the generated app.

### Checks

Run the relevant checks below. There is no `swift test` target.

```bash
./scripts/check.sh                                # Geometry; no Screen Recording permission needed
swift build -Xswiftc -strict-concurrency=complete   # Concurrency changes

# Packaging changes (Python 3 and Ruby)
python3 -B scripts/test-release-notes.py
python3 -B scripts/test-homebrew-cask.py
ruby -c Casks/snipbeam.rb
```

For live checks, grant Screen Recording permission to the packaged app and quit any running copy:

```bash
./scripts/build-app.sh
SNIPBEAM_SANDBOX_PROBE="$PWD/Package.swift" \
  build/SnipBeam.app/Contents/MacOS/SnipBeam --smoke-test
```

The smoke check tests capture, controls, sandbox restrictions, and cleanup without saving frames or sleeping the Mac. Test actual sharing in your conferencing app separately.

Run `./scripts/measure.sh` for CPU, memory, and frame-delivery measurements. These cover SnipBeam's process, not total WindowServer, GPU, or conferencing costs.

### Homebrew releases

- Each release updates `Casks/snipbeam.rb` with the published ZIP's version, build number, URL, and checksum. Build numbers let `brew upgrade` detect every release.
- The workflow pushes to `main` using `GITHUB_TOKEN` with `contents: write`; repository rules must allow it. Cask-only commits do not trigger app releases or appear in release notes.
- If the cask update fails, rerun the workflow. Pull its generated commit before your next push.

### Signing

Local builds use ad-hoc signing without an Apple Developer account. To use a Developer ID certificate from your keychain:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-app.sh
```

Gatekeeper-trusted distribution also requires [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## License

[MIT](LICENSE)
