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

`assets/intro.mp4` is the silent 25-second FFrames video from `marketing/intro/gh-orchestrator-intro.mp4`, showing global authored/review-requested PR categories, repository search in Insights and Notifications, and customizable workflow-job notifications. It is checked in here so Pages hosts it directly. Keep its poster in sync when replacing the video.

The five WebP screenshots come from `marketing/intro/media/` and use fictional native fixtures from `DesignParityRenderingTests.swift`. The Settings fixtures use the production panes in a native window with the current five-section sidebar and system search/refresh toolbar. Capture them in the foreground, since offscreen rendering omits native sidebar and toolbar surfaces. Their card surfaces use the flat appearance. The notification capture shows saved repositories, selected workflow/job filters and enabled completion alerts. Open a screenshot on the page to inspect it at full size. The app icon comes from the app's generated artwork.

After refreshing the native PNGs, copy them to both `marketing/intro/media/` and `docs/screenshots/`, then create the display WebPs with `cwebp -q 90 input.png -o output.webp`. Keep each image's HTML width and height consistent with the exported dimensions. The video preserves each capture's aspect ratio and keeps repository search visible throughout both Settings scenes; the taller review-comments capture pans to the thread content. Export the poster from the updated video at 4.5 seconds and compress it with the same WebP command. Update the media URL version query in `index.html` when replacing assets so returning visitors load the new captures.

Videos never autoplay; loading is user-initiated. Screenshots load lazily. No analytics, cookies or third-party embeds are used.
