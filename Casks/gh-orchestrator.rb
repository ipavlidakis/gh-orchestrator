cask "gh-orchestrator" do
  version "0.5.7"
  sha256 "b94a29c934557f1393168f26c8369995aaa74104b2c4abecd6c890c39d624856"

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
