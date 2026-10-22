# Template for Casks/superlaunchpad.rb in DantesChmo/homebrew-tap.
# .github/workflows/homebrew.yml rewrites the `version` and `sha256` lines
# for every published release; edit everything else here, not in the tap.
cask "superlaunchpad" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/DantesChmo/SuperLaunchpad/releases/download/v#{version}/SuperLaunchpad-#{version}.dmg"
  name "SuperLaunchpad"
  desc "Fullscreen app launcher in the style of the classic Launchpad"
  homepage "https://github.com/DantesChmo/SuperLaunchpad"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app updates itself through Sparkle, so `brew upgrade` leaves it alone
  # unless run with --greedy; otherwise both would fight over the bundle.
  auto_updates true
  depends_on macos: ">= :sequoia"

  app "SuperLaunchpad.app"

  zap trash: [
    "~/Library/Application Support/com.dantes.SuperLaunchpad",
    "~/Library/Preferences/com.dantes.SuperLaunchpad.plist",
  ]
end
