# Homebrew Cask for Cocxy Terminal
# Usage: brew tap cocxy/tap && brew install --cask cocxy
#
# This formula will be published to a separate tap repository
# when the first public release is ready.

cask "cocxy" do
  version "0.1.0"
  sha256 :no_check # Updated on each release

  url "https://github.com/salp2403/cocxy-terminal/releases/download/v#{version}/CocxyTerminal-#{version}.dmg"
  name "Cocxy Terminal"
  desc "Native macOS terminal built for AI agent workflows"
  homepage "https://cocxy.dev"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sonoma"

  app "Cocxy Terminal.app"

  binary "#{appdir}/Cocxy Terminal.app/Contents/Resources/cocxy"

  zap trash: [
    "~/.config/cocxy",
    "~/Library/Preferences/com.cocxy.terminal.plist",
    "~/Library/Caches/com.cocxy.terminal",
  ]
end
