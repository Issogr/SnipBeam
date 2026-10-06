# SnipBeam

A free, open-source macOS menu-bar app that turns a selected screen region into a normal window you can share in meetings.

**Selected screen region → ScreenCaptureKit → Metal preview → shareable window.**

SnipBeam works entirely locally. It does not record, save, or upload captured frames, and has no audio capture, accounts, or analytics. Your conferencing app handles sharing the preview with participants.

## Install

Requires an **Apple Silicon Mac running macOS 14 Sonoma or later**.

### Homebrew

With [Homebrew](https://brew.sh) installed:

```bash
brew tap issogr/snipbeam https://github.com/Issogr/SnipBeam
brew install --cask issogr/snipbeam/snipbeam
```

This repository is also the tap; the explicit URL is needed because it is named `SnipBeam`, not `homebrew-snipbeam`. If you previously installed the app manually, quit it and move that copy out of Applications before the first Homebrew installation.

To update, quit SnipBeam, then run:

```bash
brew update
brew upgrade --cask snipbeam
```

Open **SnipBeam** from Applications after installing or updating. Homebrew checks the release's SHA-256 checksum; it does not grant macOS trust or Screen Recording permission. The current builds are **ad-hoc signed, not notarized**, so the first-launch steps below still apply.

### Manual download

1. Download **SnipBeam-macos-arm64.zip** from [GitHub Releases](https://github.com/Issogr/SnipBeam/releases). Choose the app ZIP under **Assets**, not the source-code archive.
2. Unzip it and move **SnipBeam.app** to **Applications**.
3. Open SnipBeam and look for the viewfinder icon in the menu bar.

No developer tools are needed. Builds are currently **ad-hoc signed, not notarized**. If macOS blocks the first launch, attempt to open the app, then go to **System Settings → Privacy & Security → Open Anyway**.

To verify a download, place the ZIP and its `.sha256` file in the same directory and run:

```bash
shasum -a 256 -c SnipBeam-macos-arm64.zip.sha256
```

## Select and share

1. Click the menu-bar icon and choose **Select Region…**.
2. Grant Screen Recording permission when prompted.
3. Drag a rectangle on one display, then release to confirm. **Escape** cancels; the minimum size is **20 × 20 points**.
4. In Google Meet, Slack, Zoom, Teams, Discord, or another conferencing app, choose **Share a window**, then **SnipBeam**.

The preview shows a fixed area of your desktop. Move other windows underneath that area to change what appears. SnipBeam's own windows are excluded to prevent recursive previews.

| Control | Behavior |
| --- | --- |
| Resize the preview | Scales the image without changing the captured region. |
| Pause / Resume | Freezes the last frame, then resumes the same region. |
| Stop Sharing | Stops active or paused capture and closes the preview, including when its title bar is hidden. SnipBeam stays available in the menu bar. |
| Show Cursor | Includes or hides the pointer in new frames. |
| Hide Title Bar | Hides the preview's title and window buttons, leaving only the image. Drag the image to move the window; uncheck this menu-bar option to restore the buttons. |
| Close the preview | Stops capture while keeping the menu-bar app available. |
| Select Region… again | Ends the previous capture and starts a new selection. |

Keep the preview open and unminimized while sharing. Conferencing apps may need their own Screen Recording permission, and window-sharing behavior varies by client.

## Screen Recording permission

SnipBeam needs this macOS permission to display the selected region, even though it does not record anything.

Open **System Settings → Privacy & Security → Screen Recording** (called **Screen & System Audio Recording** on some versions) and enable **SnipBeam**. If it is missing, add the app with the **+** button.

Then choose **Select Region…** to retry. Quit and reopen SnipBeam if macOS requests it. Rebuilding or moving an ad-hoc-signed copy may require granting permission again. The audio wording in Settings does not mean SnipBeam captures audio.

## Limitations

- One fixed region on one display at a time; no cross-monitor selection or automatic window tracking.
- Display configuration changes, sleep, and user-session switching end capture. Select a region again when you return.
- Protected/DRM content may appear blank. Output is SDR.
- Preview size and menu preferences are not saved between launches.

## Development

Use **Swift 5.9+ and Apple's Command Line Tools** with any text editor. No Xcode project, Xcode application, or third-party Swift packages are required.

Install the tools if needed:

```bash
xcode-select --install
```

From the repository root:

```bash
swift build             # Compile a debug build
./scripts/run.sh        # Build, package, sign, and launch the app
```

The app is generated at `build/SnipBeam.app`. Quit an existing copy before rebuilding and relaunching, or macOS may reactivate the old process.

- `./scripts/build-app.sh` builds the release app without launching it.
- `./scripts/package-app.sh` creates `build/SnipBeam-macos-arm64.zip` and its checksum.
- Packaged builds use App Sandbox and hardened runtime; the raw SwiftPM executable does not have those protections.

### Code layout

- `Sources/SnipBeam/App/` owns application state and lifecycle.
- `Capture/`, `Selection/`, and `Preview/` under `Sources/SnipBeam/` contain the capture pipeline, selection overlays, and Metal rendering.
- `Resources/` contains bundle metadata, entitlements, and the icon; edit these sources rather than the generated app.
- `Tests/` and `Sources/SnipBeam/Checks/` contain geometry, integration, and performance checks.

### Checks

Run the geometry checks without Screen Recording permission:

```bash
./scripts/check.sh
```

This project uses standalone assertions rather than a `swift test` target. For concurrency changes, also run:

```bash
swift build -Xswiftc -strict-concurrency=complete
```

For live capture checks, grant Screen Recording permission to the packaged app, quit any running copy, then run:

```bash
./scripts/build-app.sh
SNIPBEAM_SANDBOX_PROBE="$PWD/Package.swift" \
  build/SnipBeam.app/Contents/MacOS/SnipBeam --smoke-test
```

The check opens temporary previews and tests selection, rendering, controls, sandbox restrictions, and cleanup. It does not save frames or put the Mac to sleep. Sharing with participants still needs testing in your conferencing app.

To measure resource use on your Mac:

```bash
./scripts/measure.sh
```

Measurements cover SnipBeam's process, not total WindowServer, GPU, or conferencing costs. Larger regions cost more; select only what you need and pause when updates are unnecessary.

For changes to packaging tooling, run its offline checks with Python 3:

```bash
python3 -B scripts/test-release-notes.py
python3 -B scripts/test-homebrew-cask.py
ruby -c Casks/snipbeam.rb
```

### Homebrew releases

The release workflow updates `Casks/snipbeam.rb` in this repository after publishing the app ZIP. It reads the app version and build number from the published ZIP and pins that exact release URL and checksum. The build number makes every published update visible to `brew upgrade`, even when the app's marketing version stays the same.

The workflow uses its existing `GITHUB_TOKEN` with `contents: write` to push a cask-only commit to `main`; no extra repository or token is needed. Repository rules must allow that workflow push. Cask-only changes do not trigger app releases and are omitted from release notes. If the cask update fails after publication, rerun the workflow; it can update the cask without rebuilding the already-published app. Pull the generated commit before pushing your next local change.

### Signing

Local development uses ad-hoc signing and needs no Apple Developer account. To use a Developer ID certificate already installed in your keychain:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/package-app.sh
```

Trusted public distribution also requires [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution). Neither is required to build and run SnipBeam locally.

## License

[MIT](LICENSE)
