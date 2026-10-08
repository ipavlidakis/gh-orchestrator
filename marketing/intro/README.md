# GHOrchestrator introduction

A silent, 25-second, 1920×1080 video at 30 fps, built with [FFrames](https://fframes.studio/) 1.1.0 and rendered with Skia Metal. All repository names, pull requests, accounts and review comments are fictional. The cut contains no installation command.

## Preview and export

Requires Rust and FFmpeg. Run from this directory:

```sh
cargo run --release -- preview --mute
cargo run --release -- render -o rendered.mp4
ffmpeg -hide_banner -loglevel error -y -i rendered.mp4 -map 0:v:0 -c copy -an -movflags +faststart gh-orchestrator-intro.mp4
```

FFrames emits an empty audio track even with `AudioMap::none()`; the final command removes it without re-encoding the video.

## Edit and check

`src/lib.rs` defines the typography, animation and seven scenes: tab chaos, pull requests, checks, review comments, Actions insights, customizable workflow-job alerts and the closing app title. `media/` contains the native app captures, app icon and DM Sans font. This standalone Rust workspace adds no dependencies to the macOS app.

```sh
cargo run --release -- timeline
cargo run --release -- inspect --all-frames --fail-on warning
cargo run --release -- strip all -n 18 -o strip.png
cargo run --release -- frame 4.8s,8.8s,12.6s,15.4s,19.5s,24s
cargo test --release
```

The seven approved frames live in `_frame_snapshots/`. Review intentional visual changes before accepting new baselines with `FFRAMES_UPDATE_SNAPSHOTS=1 cargo test --release`.

## Refresh native demo captures

The fictional fixtures are in `Tests/GHOrchestratorTests/MenuBar/DesignParityRenderingTests.swift` in the repository root. Generate the Tuist project, then run:

```sh
xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -only-testing:GHOrchestratorTests/DesignParityRenderingTests
```

Copy `dashboard-overview.png`, `dashboard-pr-details.png`, `dashboard-comments.png`, `settings-insights.png` and `settings-notifications.png` from `/tmp/gho-shots/` into this project's `media/`, then render again. Captures use the real native views with dummy data. The Settings fixtures show the current five-section sidebar and native search/refresh toolbar; they capture foreground windows because offscreen rendering omits that chrome. Card surfaces use the flat appearance. Preserve each capture's aspect ratio in `src/lib.rs` and keep repository search visible throughout the Settings scenes. The tall review-comments capture pans to the thread content.

DM Sans is distributed under the [SIL Open Font License](LICENSE-DM-Sans.txt).
