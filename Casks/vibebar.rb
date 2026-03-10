cask "vibebar" do
  arch arm: "arm64", intel: "x86_64"

  version "1.3.3"
  sha256 "3d3ce849cb718f03d7e1cc4b5d71828d342cc5b5b5428d2ce9300bb298b638e8"

  url "https://github.com/yelog/vibebar/releases/download/v#{version}/VibeBar-#{version}-universal.dmg"
  name "VibeBar"
  desc "Menu bar app for monitoring AI coding sessions"
  homepage "https://github.com/yelog/vibebar"

  livecheck do
    url :url
    regex(/^v?(\d+(?:\.\d+)+(?:-(?:beta|alpha|rc)\.?\d*)?)$/i)
    strategy :github_latest
  end

  auto_updates true

  app "VibeBar.app"

  postflight do
    # Create necessary directories for VibeBar
    FileUtils.mkdir_p("#{Dir.home}/Library/Application Support/VibeBar/sessions")
    FileUtils.mkdir_p("#{Dir.home}/Library/Application Support/VibeBar/runtime")
  end

  uninstall quit: "com.vibebar.app"

  zap trash: [
    "~/Library/Application Support/VibeBar",
    "~/Library/Preferences/com.vibebar.app.plist",
    "~/Library/Caches/com.vibebar.app",
    "~/Library/Logs/VibeBar",
  ]
end
