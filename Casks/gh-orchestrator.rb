cask "gh-orchestrator" do
  version "0.5.9"
  sha256 "7337dd83f401da6e5a88c7003af1eb07c50bad117546cd12c9c01d2826064202"

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
