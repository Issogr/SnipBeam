# SnipBeam

A free, MIT-licensed macOS menu-bar utility that turns a rectangular screen region into a normal window called **SnipBeam**. Share that window using your meeting app's standard window-sharing UI.

**Selected screen region → ScreenCaptureKit → Metal preview inside an NSWindow.**

SnipBeam runs entirely locally. It does not save, record, encode, upload, or transmit captured frames. It has no networking, audio capture, accounts, analytics, third-party dependencies, virtual devices, or background services. Your conferencing app handles sharing the preview with participants.

## Requirements

- macOS **14 Sonoma or later**, with a Metal-capable GPU.
- Apple's **Command Line Tools**, including Swift 5.9 or later and the macOS SDK.
- Screen Recording permission for SnipBeam.

Install the command-line tools if needed:

```bash
xcode-select --install
```

Check the installation:

```bash
xcode-select -p
swift --version
```

No Xcode project, workspace, IDE, or Xcode application is required. Use Cursor, VS Code, Zed, or any text editor.

## Build and run

From the repository root:

```bash
swift build
swift build -c release
./scripts/build-app.sh
open build/SnipBeam.app
```

Or build, package, sign, and open in one command:

```bash
./scripts/run.sh
```

`build-app.sh` runs a release build, locates SwiftPM's executable, copies the plist and resources, and signs the bundle ad hoc. The result is:

```text
build/SnipBeam.app/
└── Contents/
    ├── Info.plist
    ├── MacOS/SnipBeam
    └── Resources/AppIcon.icns
```

You can also double-click `build/SnipBeam.app` in Finder. SnipBeam appears in the menu bar; a preview opens only after selection. Quit an already running copy before rebuilding and relaunching so `open` does not reactivate the old process.

SwiftPM builds for the current Mac's architecture by default. There are no downloaded package dependencies. Generated build products are git-ignored.

## Select and share

1. Click the **SnipBeam viewfinder icon** in the menu bar, then **Select Region…**.
2. Grant Screen Recording access if prompted.
3. Drag a rectangle on one display. The drag stays within the display where it started. Release to confirm; **Escape** cancels. Regions smaller than **20 × 20 points** are rejected so you can drag again.
4. A normal **SnipBeam** window shows the selected desktop area live. Move other apps underneath that fixed area to change what appears.
5. In Google Meet/Chrome, Slack, Zoom, Microsoft Teams, Discord, or another conferencing app, choose **Share a window**, then **SnipBeam**. Select the window rather than the entire display.

Keep the preview open and unminimized. Conferencing apps can have their own Screen Recording permission requirements and window-list refresh behavior. SnipBeam uses the standard window-sharing mechanism; individual conferencing clients still need testing on your setup.

- **Resize:** fits the same source region into the window, preserving aspect ratio with black letterboxing.
- **Pause / Resume:** stops/restarts the capture stream, keeping the last frame visible and the same source rectangle. The title stays **SnipBeam**; the subtitle shows **Paused**.
- **Show Cursor:** updates the stream configuration, including while paused; the setting takes effect on new frames.
- **Close preview:** stops capture; the menu-bar app stays available.
- **Select Region… again:** ends the previous capture before starting selection. Cancelling leaves the app idle.
- **Quit SnipBeam:** exits the app and releases the capture session.
- **Sleep or user-session switch:** ends capture and closes the preview. Select a region again when you return; capture does not restart automatically.

All SnipBeam-owned windows are excluded by an application-level `SCContentFilter`, including windows opened after capture starts. Moving the preview over the source area reveals the content underneath it rather than creating a hall of mirrors.

## Screen Recording permission

SnipBeam explains and requests only screen capture access:

> SnipBeam captures the selected portion of your screen locally. Nothing is recorded or uploaded.

If access is denied, use the offered **Open System Settings** button, or navigate to:

**System Settings → Privacy & Security → Screen Recording** (called **Screen & System Audio Recording** on some macOS versions).

Enable **SnipBeam**, then choose **Select Region…** to retry. Quit and reopen the app if macOS requests it. If it is absent from the list, add `build/SnipBeam.app` using the **+** button. Rebuilding an ad-hoc-signed executable can require granting access again; keep the bundle identifier and app location consistent. Run the packaged app for predictable permission identity.

The audio-related wording in macOS Settings does not mean SnipBeam captures audio. Its stream explicitly disables audio and adds only a screen output. Screen-only ScreenCaptureKit access has no required usage-description plist key; SnipBeam presents the explanation in its onboarding before requesting macOS TCC permission.

## Implementation

```text
SCStream (cropped display, own application excluded)
  → FrameReceiver (valid complete CMSampleBuffer only)
  → CVPixelBuffer / IOSurface
  → CVMetalTextureCache / Metal texture
  → CAMetalLayer owned by an MTKView in a normal NSWindow
```

- `sourceRect` is **display-local, top-left-origin logical points**. `CoordinateConverter` translates from bottom-left AppKit coordinates using the selected screen's own origin, clamps to that display, and aligns to physical pixel edges.
- Output width/height use ScreenCaptureKit's `pointPixelScale`; Retina output keeps the region's backing-pixel resolution. Resizing the preview never reconfigures the crop.
- The stream requests up to **60 FPS**, uses **queue depth 3**, BGRA pixels, and SDR sRGB output. ScreenCaptureKit may emit fewer complete frames when the source is unchanged.
- One serial capture/render queue validates and renders frames off the main thread. It retains only the newest pending pixel buffer and permits one GPU submission in flight. Texture mapping happens only when a drawable and GPU slot are available; dropped frames avoid that work. Core Video references stay alive until GPU completion, and per-work-item autorelease pools bound temporary-object lifetimes.
- The Metal device, command queue, texture cache, render-pass descriptor, and pipeline are reused. The frame receiver reads native attachment dictionaries without bridging all metadata into Swift dictionaries. A tiny shader is compiled once per preview from embedded source using Metal's runtime compiler, so the separate Xcode Metal toolchain is unnecessary. No captured frames are converted to `NSImage` or copied to CPU image buffers.
- AppKit work stays on the main actor. `AppDelegate` owns the capture state and serializes control operations so closing a window during an asynchronous start cannot revive the capture.

### Source layout

```text
Package.swift                       SwiftPM executable, macOS 14+
Sources/SnipBeam/
  main.swift                        AppKit entry point
  App/AppDelegate.swift             State and lifecycle
  Capture/                          Stream, frame validation, region, coordinates
  Selection/                        Per-display borderless selection overlays
  Preview/                          Normal window, MTKView, Metal renderer
  Permissions/                      Screen Recording onboarding and retry
  MenuBar/                          Menu commands and enabled state
  Checks/CaptureSmokeTest.swift      Opt-in live integration check
Resources/                          Info.plist, sandbox entitlement, original icon
Tests/                              Geometry assertions and animation fixture
scripts/                            Build, run, sign, icon generation, checks, profiling
```

Replace `com.example.SnipBeam` in `Resources/Info.plist` before distribution. Queue labels use the same prefix for diagnostics.

### Security boundaries

Packaged builds enable **App Sandbox** and **hardened runtime**, including ad-hoc development builds. The only entitlement is `com.apple.security.app-sandbox`: there are no network-client/server, user-file, camera, microphone, automation, JIT, debugger, or library-validation exceptions. Metal's native shader compiler works within these restrictions. Sandbox containers and OS-managed caches still exist; captured frames remain in memory.

Screen Recording remains a separate, broad macOS TCC permission. SnipBeam restricts its stream to the selected rectangle, validates finite/in-bounds geometry and pixel dimensions before configuring capture, and rejects a stale display/scale rather than falling back to whole-screen capture. Display/system sleep and user-session switching close the preview and end the session. These protections do not erase frames already seen by meeting participants.

The standalone executable produced by `swift build` is useful for debugging; the sandbox/hardened-runtime guarantees apply to the signed `.app` produced by `build-app.sh`. Ad-hoc signing does not establish a trusted publisher identity; use Developer ID signing and notarization for public distribution.

The original icon is included. If `Resources/AppIcon.icns` is missing, packaging regenerates it from `scripts/make-icon.swift` with native AppKit and `iconutil`. Additional files in `Resources/` are copied into the bundle; the plist and signing entitlements are handled separately.

## Checks

Geometry checks need no Screen Recording permission or XCTest installation:

```bash
./scripts/check.sh
```

They cover above/below/left/right display origins, Y-axis conversion, 1×/2× scaling, pixel-edge alignment, minimum sizes, cross-display drag clamping, portrait/landscape letterboxing, and rejection of out-of-bounds, non-finite, or overflowing crops.

After granting permission, quit any running copy and run the live integration check:

```bash
./scripts/build-app.sh
build/SnipBeam.app/Contents/MacOS/SnipBeam --smoke-test
```

It briefly opens overlays and previews on connected displays, drives the real menu callbacks and selection views, and checks Escape, frame delivery/presentation, pixel dimensions, normal-window discovery, paused resizing, cursor configuration, resume, preview close, and app exit. It also verifies the sandbox entitlement and tests capture shutdown using process-local sleep/session notifications; it does not actually put the Mac to sleep or switch users. It prints `PASS` or exits nonzero on failure/timeout. No frames are saved, and UI-automation permissions are not required.

To check actual sandbox enforcement against the existing package manifest outside the app container:

```bash
SNIPBEAM_SANDBOX_PROBE="$PWD/Package.swift" \
  build/SnipBeam.app/Contents/MacOS/SnipBeam --smoke-test
```

For a quick local CPU/memory measurement:

```bash
/usr/bin/time -l build/SnipBeam.app/Contents/MacOS/SnipBeam --smoke-test
```

Manual checks still matter: exact visible crop and cursor appearance, dragging across physical monitors with mixed scaling/rotation, display unplug/reconfiguration, permission revocation, and sharing with participants in each conferencing client. A successful window-discovery check alone does not establish compatibility with every client/version.

### Resource measurement

Quit any running copy, grant Screen Recording access, then run:

```bash
./scripts/measure.sh
```

This builds a release app and a separate, temporary animation fixture so capture has a repeatable moving source. It measures idle, capturing, paused, covered, minimized, and closed-preview states after warm-up, with five-second sampling intervals. The fixture exits when the script finishes. The normal app has no profiling timer.

A local 640×360-pixel, 1× animated-region comparison measured **2.43% → 2.10% of one CPU core** while capturing, with about **27 MiB physical footprint** and **57 presentations/s** in both runs. Idle and paused CPU were about **0.01%**; cold idle footprint was about **14 MiB**. These are individual local runs, not a cross-hardware guarantee or a statistically established speedup.

The measurements describe **SnipBeam's process**, not total WindowServer, GPU, or conferencing-app costs. Capture cannot have zero cost: three BGRA buffers for a 3840×2160 region alone represent roughly **95 MiB**, before preview surfaces and other overhead. Select only the area you need and pause when updates are unnecessary. A covered or minimized preview stays live because a conferencing app may still be consuming it; occlusion is not a safe signal to freeze sharing. The target stays 60 FPS at the selected region's native pixel resolution.

## Signing and future distribution

Local builds use **ad-hoc signing**. No Apple Developer membership or notarization is required for local development:

```bash
./scripts/sign-app.sh
codesign --verify --strict --verbose=2 build/SnipBeam.app
```

To use a real identity already installed in your keychain:

```bash
security find-identity -v -p codesigning
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

Or sign an existing bundle:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/sign-app.sh build/SnipBeam.app
```

All packaged builds enable the sandbox and hardened runtime; non-ad-hoc signing also requests a secure timestamp. For future public distribution, sign with **Developer ID Application**, then notarize. With `notarytool` credentials already stored under the keychain profile `SnipBeam-notary`, an example ZIP workflow is:

```bash
ditto -c -k --keepParent build/SnipBeam.app build/SnipBeam.zip
xcrun notarytool submit build/SnipBeam.zip --keychain-profile SnipBeam-notary --wait
xcrun stapler staple build/SnipBeam.app
spctl --assess --type execute --verbose build/SnipBeam.app
ditto -c -k --keepParent build/SnipBeam.app build/SnipBeam.zip
```

The final command repackages the stapled app. A `.dmg` can instead be made with `hdiutil` from a staging directory containing the signed app, then signed/notarized/stapled as a disk image. Account credentials, architecture/universal-build choices, release hosting, and a release pipeline are intentionally outside the development loop.

## v1 scope

One fixed rectangular region on one display at a time. Display configuration changes stop capture and ask for a new selection rather than silently changing the shared area. Protected/DRM content can be blank, as with other macOS screen-capture tools. SDR output only.

No cross-monitor regions, crop editing, presets, recording, screenshots, audio, virtual cameras/displays, integrations, networking, annotations, login items, updates, or services. Preview-window size and menu preferences are not persisted.
