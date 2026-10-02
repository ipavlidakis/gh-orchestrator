cask "gh-orchestrator" do
  version "0.5.2"
  sha256 "f7888604e435d2befad76dc233fe0b9c10a54bb280e91786a26f76e351bdef3c"

  url "https://github.com/ipavlidakis/gh-orchestrator/releases/download/#{version}/GHOrchestrator-#{version}.dmg"
  name "GHOrchestrator"
  desc "Menu bar app for tracking GitHub pull requests and Actions"
  homepage "https://github.com/ipavlidakis/gh-orchestrator"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :sequoia

  app "GHOrchestrator.app"
end
