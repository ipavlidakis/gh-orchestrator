# GHOrchestrator product website

Static HTML, CSS and a small clipboard enhancement. No build step or frontend dependencies.

Live URL: https://ipavlidakis.github.io/gh-orchestrator/

## Preview

From the repository root:

```sh
python3 -m http.server 8080 --directory website
```

Open http://localhost:8080. The page uses relative asset paths so it also works under the GitHub Pages repository prefix.

## Publish and update

In the repository's **Settings → Pages**, choose **GitHub Actions** as the publishing source. Branch-based Pages publishing only supports the repository root or `/docs`; the included workflow publishes `website/` directly.

`.github/workflows/pages.yml` uploads only `website/` and deploys after changes to that directory reach `main`. After enabling Pages for the first time, run **Deploy product website** from the Actions tab using **Run workflow**. Subsequent website changes deploy automatically.

Edit `index.html` (including its embedded CSS) or `install.js`, preview at desktop and mobile widths, then commit and push to `main`. The Homebrew commands match the tap in this repository. Download links always point to the latest stable GitHub release, so releases require no website version edit.

## Media

`assets/intro.mp4` is the silent 24-second FFrames video from `marketing/intro/gh-orchestrator-intro.mp4`. It is checked in here so Pages hosts it directly. Keep its poster in sync when replacing the video.

The four WebP screenshots come from `marketing/intro/media/` and use fictional native fixtures from `DesignParityRenderingTests.swift`. They are compressed copies without content changes. Open a screenshot on the page to inspect it at full size. The app icon comes from the app's generated artwork.

Videos never autoplay; loading is user-initiated. Screenshots load lazily. No analytics, cookies or third-party embeds are used.
