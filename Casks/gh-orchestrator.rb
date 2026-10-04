cask "gh-orchestrator" do
  version "0.5.3"
  sha256 "ce8c3a13a82d91de75bb36e70f1cbff4ae87d115ca41f9110586a17652161edf"

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
