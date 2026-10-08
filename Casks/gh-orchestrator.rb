cask "gh-orchestrator" do
  version "0.5.8"
  sha256 "fb07f271e745a9c6318e64e6eb6b887f509471607015a3a5c89263ccc5d5d4e5"

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
