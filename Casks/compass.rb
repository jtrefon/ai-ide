cask "compass" do
  version :latest
  sha256 :no_check

  url "https://github.com/jtrefon/ai-ide/releases/latest/download/compass.dmg"
  name "Compass"
  desc "Native AI-powered IDE for macOS"
  homepage "https://github.com/jtrefon/ai-ide"

  app "Compass.app"
end
