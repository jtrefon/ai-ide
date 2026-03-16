cask "osx-ide" do
  version :latest
  sha256 :no_check

  url "https://github.com/jtrefon/ai-ide/releases/latest/download/osx-ide.dmg"
  name "osx-ide"
  desc "Native AI-powered IDE for macOS"
  homepage "https://github.com/jtrefon/ai-ide"

  app "osx-ide.app"
end
