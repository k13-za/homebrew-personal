cask "muffon" do
  version "2.2.0"

  name "muffon"
  desc "A music streaming client
        for desktop, which helps you listen to, discover
        and organize music in an advanced way"
  homepage "https://muffon.netlify.app"

  livecheck do
    url "https://github.com/staniel359/muffon/releases/latest"
    strategy :github_latest
  end

  on_arm do
    sha256 "07e19ac200a52be219ced7e0fc7ecf2ab89aa5afef95708433b48e0286aa690f"
    url "https://github.com/staniel359/muffon/releases/download/v#{version}/Muffon-#{version}-arm64.dmg"
  end

  on_intel do
    sha256 "997b1b48ea32089ecc92ab2020f79193285e815c680c8b35f9994d6dc1477ec5"
    url "https://github.com/staniel359/muffon/releases/download/v#{version}/Muffon-#{version}-x64.dmg"
  end

  app "muffon.app"

  uninstall quit: "dev.thesolog.muffon"

  # Documentation: https://docs.brew.sh/Cask-Cookbook#stanza-zap
  zap trash: [
    "~/Library/Application Support/Muffon",
    "~/Library/Caches/dev.thesolog.muffon",
    "~/Library/Preferences/dev.thesolog.muffon.plist",
    "~/Library/Saved Application State/dev.thesolog.muffon.savedState",
  ]
end
