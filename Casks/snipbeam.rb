cask "snipbeam" do
  version "0.1.0,2"
  sha256 "b3acd285adb841ab6b15f33ce6dbd83c7f606ae883ec8d07e34d1f13d7d116d7"

  url "https://github.com/Issogr/SnipBeam/releases/download/update-5882c39e4306edcbbffccc32195ddd623cab30c6/SnipBeam-macos-arm64.zip"
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
    Screen Recording permission is requested when selecting a region.
  EOS
end
