# Building GHOrchestrator From Source

This guide covers local source builds for the menu-bar app. For signed DMG release packaging, use [RELEASING.md](RELEASING.md).

## Prerequisites

- macOS with Xcode installed
- Xcode command line tools available on `PATH`
- Tuist installed and available on `PATH`
- A GitHub OAuth app that has device flow enabled

GHOrchestrator targets macOS 15+ and uses Swift 6 / SwiftPM for the local package.

## 1. Configure GitHub OAuth

GHOrchestrator uses GitHub OAuth device flow. Source builds need a GitHub OAuth client ID before the app is generated or built.

Start from the committed example file:

```bash
cp Config/GitHubOAuth.local.example.json Config/GitHubOAuth.local.json
```

Edit `Config/GitHubOAuth.local.json` so it looks like:

```json
{
  "clientID": "YOUR_GITHUB_OAUTH_CLIENT_ID"
}
```

Notes:

- `Config/GitHubOAuth.local.json` is gitignored.
- Only the public `clientID` is required for device flow.
- If you prefer, you can use `GH_ORCHESTRATOR_GITHUB_CLIENT_ID` as a build-time fallback, but the local JSON file is the primary repo workflow.
- If the app later reports that OAuth is not configured, regenerate the workspace after fixing the local config.

Useful GitHub links already used by the app:

- OAuth app registration: `https://github.com/settings/applications/new`
- OAuth app docs: `https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps`

## 2. Generate the Workspace

The checked-in manifests are the source of truth. The generated `.xcworkspace` and `.xcodeproj` are gitignored.

```bash
tuist generate --no-open
```

Re-run this whenever `Project.swift`, `Workspace.swift`, or package wiring changes.

## 3. Build and Run

The repo includes a helper that generates the workspace when needed, kills stale workspace-scoped `xcodebuild` processes, builds the app, stops a currently running app instance, and launches the new build.

```bash
./script/build_and_run.sh
```

Other supported modes:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

What they do:

- `--verify`: launch the built app and confirm the process starts
- `--logs`: launch the app and stream app process logs
- `--telemetry`: launch the app and stream unified logging for the app subsystem
- `--debug`: launch the built executable under LLDB

## 4. First Launch

After the app starts:

1. Open Settings from the menu bar.
2. In `Repositories`, add one or more repositories in `owner/repo` format.
3. In `GitHub`, start `Sign in with GitHub`.
4. Approve the one-time device code in your browser.

The dashboard refreshes on the configured polling interval whether the menu is hidden or visible. Opening the menu does not force an automatic refresh.

## 5. Verification

The repo baseline verification flow is:

```bash
tuist generate --no-open
swift test --package-path Packages/GHOrchestratorCore
xcodebuild test \
  -workspace GHOrchestrator.xcworkspace \
  -scheme GHOrchestrator \
  -destination 'platform=macOS' \
  -derivedDataPath DerivedData
./script/build_and_run.sh --verify
```

Use the package test command when you are changing code under `Packages/GHOrchestratorCore`. Use the `xcodebuild test` command when app-target behavior or shared integration points change.

## 6. Troubleshooting

### "OAuth not configured"

- Confirm `Config/GitHubOAuth.local.json` exists and contains a non-empty `clientID`.
- Regenerate the workspace after adding or changing the file:

```bash
tuist generate --no-open
```

### Device flow errors during sign-in

- Make sure the GitHub OAuth app has device flow enabled.
- Confirm the configured client ID belongs to the OAuth app you expect.

### Build or test commands appear stuck

- Re-run `./script/build_and_run.sh` or the explicit build/test command.
- The helper script already clears stale `xcodebuild` processes for this workspace before building, which fixes the common local stall this repo has seen.

### Manifest changes do not appear in Xcode

- Regenerate the workspace with `tuist generate --no-open`.

## Related Docs

- Repo overview: [README.md](README.md)
- Release packaging: [RELEASING.md](RELEASING.md)
