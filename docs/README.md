# GHOrchestrator product website

Static HTML, CSS and a small clipboard enhancement. No build step or frontend dependencies.

Live URL: https://ipavlidakis.github.io/gh-orchestrator/

## Preview

From the repository root:

```sh
python3 -m http.server 8080 --directory docs
```

Open http://localhost:8080. The page uses relative asset paths so it also works under the GitHub Pages repository prefix.

## Publish and update

In the repository's **Settings → Pages**, choose **Deploy from a branch**, select **main** and **/docs**, then save. GitHub Pages publishes this directory directly; `.nojekyll` keeps it a plain static site.

Subsequent pushes to `main` publish automatically through GitHub's built-in Pages deployment. No custom workflow or build step is needed.

Edit `index.html` (including its embedded CSS) or `install.js`, preview at desktop and mobile widths, then commit and push to `main`. The Homebrew commands match the tap in this repository. Download links always point to the latest stable GitHub release, so releases require no website version edit.

## Media

`assets/intro.mp4` is the silent 25-second FFrames video from `marketing/intro/gh-orchestrator-intro.mp4`, including customizable success/failure workflow-job notifications. It is checked in here so Pages hosts it directly. Keep its poster in sync when replacing the video.

The five WebP screenshots come from `marketing/intro/media/` and use fictional native fixtures from `DesignParityRenderingTests.swift`. They are compressed copies without content changes. The notification capture shows selected workflow/job filters and enabled completion alerts. Open a screenshot on the page to inspect it at full size. The app icon comes from the app's generated artwork.

Videos never autoplay; loading is user-initiated. Screenshots load lazily. No analytics, cookies or third-party embeds are used.
