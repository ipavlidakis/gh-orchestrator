# Releasing GHOrchestrator

This repo ships direct-download macOS releases as a signed, notarized, stapled `.dmg`
that can be attached to a GitHub Release.

## One-time prerequisites

1. Install a valid `Developer ID Application` certificate in your login keychain.
2. Make sure the GitHub OAuth app used by shipped builds has:
   - a valid `clientID` configured for the build
   - device flow enabled
3. Store notary credentials in a local keychain profile. Example:

```bash
xcrun notarytool store-credentials GHOrchestratorNotary \
  --apple-id "you@example.com" \
  --team-id "TEAMID1234" \
  --password "app-specific-password"
```

## Local release config

Copy [Config/Release.local.example.json](/Users/ipavlidakis/workspace/gh-orchestrator/Config/Release.local.example.json) to `Config/Release.local.json` and fill in the values you want to use for releases. A starter local file is already present on this machine at [Config/Release.local.json](/Users/ipavlidakis/workspace/gh-orchestrator/Config/Release.local.json) and is gitignored.

The script loads `Config/Release.local.json` automatically for stable settings and secrets. You still provide `--version` and `--build` on each release command. CLI flags override file values.

## Optional environment overrides

```bash
export APPLE_DEVELOPER_TEAM_ID="TEAMID1234"
export APPLE_DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID1234)"
export APPLE_NOTARY_PROFILE="GHOrchestratorNotary"
export GH_ORCHESTRATOR_GITHUB_CLIENT_ID="your-github-oauth-client-id"
```

For GitHub Release uploads, also set:

```bash
export GITHUB_TOKEN="github_pat_or_app_token"
```

## Build a signed, notarized DMG

```bash
./script/release_dmg.sh \
  --version 1.0.0 \
  --build 1
```

This reads `Config/Release.local.json` and writes artifacts under `build/release/<version>-<build>/`.

If you are using the Codex desktop app, the project environment now exposes a `Release` action that prompts for the same `version` and `build` values and then runs the same script.

## Upload to GitHub Releases

```bash
./script/release_dmg.sh \
  --version 1.0.0 \
  --build 1
```

If you do not pass them explicitly, the script derives:

- `tag` = `version`
- `releaseName` = `version`

Optional flags:

- `--config /absolute/path/to/release.json`
- `--draft`
- `--prerelease`
- `--release-notes-file /absolute/path/to/notes.md`
- `--repo owner/name`
- `--skip-notarization`
- `--dry-run`

## What the script does

1. Regenerates the Tuist workspace.
2. Archives the app with a Release configuration and Hardened Runtime enabled.
3. Builds a read-only `UDZO` DMG with the app plus an `/Applications` symlink.
4. Signs the DMG with the `Developer ID Application` identity.
5. Submits the DMG to Apple notarization, waits for completion, and staples the ticket.
6. Writes a SHA-256 checksum file.
7. Optionally creates or updates a GitHub Release and uploads both assets.
