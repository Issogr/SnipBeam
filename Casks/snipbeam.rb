cask "snipbeam" do
  version "0.1.0,7"
  sha256 "6fdaec78731748e16f81f51430f28372cf83821b3bab60737187d3f41efd6150"

  url "https://github.com/Issogr/SnipBeam/releases/download/update-c882f53ac2acde22889e9a0d19026cd56d8495a7/SnipBeam-macos-arm64.zip"
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
      xattr -dr com.apple.quarantine "#{appdir}/SnipBeam.app"
      open "#{appdir}/SnipBeam.app"
    If xattr reports Permission denied, repeat the xattr command with sudo.

    Screen Recording still requires your approval in System Settings > Privacy & Security.
    Choose Select Region… to request access. For permission troubleshooting, see:
      https://github.com/Issogr/SnipBeam#screen-recording-permission
  EOS
end
