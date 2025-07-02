cask "letta" do
  version "0.7.0"

  livecheck do
    url "https://github.com/letta/letta/releases/latest"
    strategy :github_latest
  end

  on_arm do
    sha256 "4332f61ec62ddad59620bb0f4d8d8185c6bb31b451fd6ea6d69a2a9f6ae5796e"
    url "https://downloads.letta.com/mac/dmg/arm64"
  end

  name "Letta Desktop"
  desc "Desktop client for Letta"
  homepage "https://letta.com/"

  app "Letta Desktop.app"

  uninstall quit: "com.letta.desktop"

  zap trash: [
    "~/Library/Application Support/Letta Desktop",
    "~/Library/Caches/com.letta.desktop",
    "~/Library/Preferences/com.letta.desktop.plist",
    "~/Library/Saved Application State/com.letta.desktop.savedState",
  ]
end