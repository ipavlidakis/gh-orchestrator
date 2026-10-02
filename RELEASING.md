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
7. Optionally creates a draft GitHub Release and uploads both assets. If a public release was requested (`draft: false`), publishes it only after both uploads succeed.
8. Publishing a stable release triggers the Homebrew workflow, which verifies the uploaded DMG checksum and commits the cask update to the default branch.

## Automatic Homebrew updates

This repository also serves as the Homebrew tap. `.github/workflows/homebrew.yml`
runs when a release is published, including when a draft is published later.
It downloads the final DMG and checksum asset, verifies their SHA-256 match,
updates `version` and `sha256` in `Casks/gh-orchestrator.rb`, and commits/pushes
the change to the default branch with the repository's `GITHUB_TOKEN`.
No separate tap or additional Actions secret is needed.

The example local config uses `draft: true`. After reviewing the uploaded draft,
publish it to trigger the automatic Homebrew update:

```bash
gh release edit 0.5.3 --repo ipavlidakis/gh-orchestrator --draft=false --latest
gh run list --repo ipavlidakis/gh-orchestrator --workflow homebrew.yml --limit 5
```

Replace `0.5.3` with the new version. Stable tags must match the numeric version
used by the cask's download URL, such as `0.5.3`. Drafts and prereleases are skipped;
only the latest stable release can update the cask, and older versions cannot
roll it back. A checksum mismatch fails the workflow before changing the cask.

If the workflow fails, fix the missing/incorrect assets or repository permission
error shown in its log, then rerun it in Actions or dispatch it for the same tag:

```bash
gh workflow run homebrew.yml --repo ipavlidakis/gh-orchestrator -f tag=0.5.3
```

Rerunning an already-current release verifies its assets without creating a
duplicate commit. Releases created by another Actions workflow using its
`GITHUB_TOKEN` do not trigger `release.published`; that workflow should explicitly
dispatch `homebrew.yml` after uploading and publishing its assets.

Users discover the update with `brew update`, then upgrade with
`brew upgrade --cask --greedy ipavlidakis/gh-orchestrator/gh-orchestrator`,
because the app also supports in-app updates.
