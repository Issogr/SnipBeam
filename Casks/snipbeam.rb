cask "snipbeam" do
  version "0.1.0,5"
  sha256 "b32c56f9d87f548fbddfe6f16c6e79597b96e7bcaf20e56fd8e85717aa9d2a52"

  url "https://github.com/Issogr/SnipBeam/releases/download/update-43af7fa0c48b4cd61ce161ecb6052e6b9db3d7da/SnipBeam-macos-arm64.zip"
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
