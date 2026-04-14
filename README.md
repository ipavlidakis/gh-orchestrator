# GHOrchestrator

GHOrchestrator is a Tuist-managed macOS 15+ menu-bar app for tracking your open GitHub pull requests in a curated set of repositories.

It signs in with GitHub OAuth device flow, stores the resulting session in Keychain, fetches pull request and Actions data directly from the GitHub GraphQL and REST APIs, and keeps the SwiftUI app target thin by pushing transport, parsing, mapping, and storage into a local Swift package.

## Highlights

- Menu-bar-first macOS app built with `MenuBarExtra`
- Repository allowlist configured in Settings with one `owner/repo` per entry
- Direct GitHub API integration with no third-party dependencies
- GitHub OAuth device flow for source builds and public builds
- Pull request grouping by repository, sorted by recent activity
- Review state, unresolved review-thread details, and Actions job/step expansion
- Retry support for failed GitHub Actions jobs when GitHub allows reruns

## Architecture

### App target

- SwiftUI scenes, menu-bar UI, and Settings UI
- Polling lifecycle and refresh coordination
- Browser launch for GitHub device-flow approval
- Top-level app commands and Dock icon behavior

### Local package

- OAuth device-code request and token polling helpers
- Keychain-backed credential storage
- GitHub GraphQL and REST transport
- DTO decoding, mapping, aggregation, and fixtures
- Unit tests for core behavior

## Repository Layout

```text
App/                            SwiftUI app target
Packages/GHOrchestratorCore/    Local Swift package for auth, transport, models, and tests
Tests/GHOrchestratorTests/      App-target unit tests
Config/                         Local example config files
script/                         Run and release helper scripts
PLAN.md                         Shared execution plan and task history
PLAN-menu-bar.md                Feature-specific plan for menu commands
RELEASING.md                    Signed/notarized DMG release workflow
```

## Quick Start

1. Install Xcode and Tuist.
2. Copy `Config/GitHubOAuth.local.example.json` to `Config/GitHubOAuth.local.json`.
3. Add your GitHub OAuth app `clientID` and make sure device flow is enabled for that OAuth app.
4. Generate the workspace:

```bash
tuist generate --no-open
```

5. Build and launch the app:

```bash
./script/build_and_run.sh
```

6. Open Settings, add one or more observed repositories, then use the GitHub pane to sign in.

## Common Commands

Build, launch, and verify:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --verify
```

Run package tests:

```bash
swift test --package-path Packages/GHOrchestratorCore
```

Run app tests:

```bash
xcodebuild test \
  -workspace GHOrchestrator.xcworkspace \
  -scheme GHOrchestrator \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData
```

## Additional Docs

- Source builds: [BUILDING.md](BUILDING.md)
- Release workflow: [RELEASING.md](RELEASING.md)

## Notes

- Generated `.xcworkspace` and `.xcodeproj` files are gitignored. Re-run `tuist generate --no-open` after manifest changes.
- `Config/GitHubOAuth.local.json` and `Config/Release.local.json` are local, gitignored files.
- Source builds without a configured GitHub OAuth client ID intentionally stay in a not-configured state.
