cask "vibebar" do
  arch arm: "arm64", intel: "x86_64"

  version "1.3.5"
  sha256 "09a0a29812463c3895845343e60c10db3b96f2da6f20563688a02cda7c538f4a"

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
