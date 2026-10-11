# PR code renderer

The app ships the generated `App/Resources/PRDiff.js` and licenses. Ordinary Tuist/Xcode builds need no Node.js or network dependency installation.

The diff order comes from the same cached directory tree as the sidebar, including files inside collapsed folders. Native headers toggle from their entire non-button area; action buttons handle their own clicks. Glass surfaces rebuild on appearance changes so detached native hosts do not retain stale materials.

The build makes one guarded change to pinned Pierre 1.5.2: `CodeView.handleResize` uses its existing render queue instead of rendering synchronously during ResizeObserver delivery. This prevents WebKit resize-loop errors on large scroll jumps. An upstream upgrade must recheck the patch; the build fails if its expected source changes.

Viewport messages identify the first visible file without changing navigation state or resending the catalog. The sidebar reveals that file and opens only its ancestor directories. Empty-file annotations reserve space for native explanatory rows; native header frames update immediately after configuration, even when WebKit delays animation frames.

To rebuild after editing this directory:

```sh
npm ci --ignore-scripts --prefix script/pr-diff
npm run build --prefix script/pr-diff
```

The lockfile pins Pierre and build tooling. The build includes one local highlighting worker, a JavaScript regex engine and a limited language set; other files render as plain text. No CDN or OAuth credentials enter WebKit. Native SwiftUI owns the directory tree, filters, file selection, headers, disclosure, Viewed eye controls, line-comment plus, settings and composer. Loaded patches and file metadata cross the bridge within the existing 3,000-file/16 MiB limits. Pierre virtualizes all filtered files; only visible headers and one hovered-line action have native hosting views. Empty header slots supply geometry without web controls. Parsing runs when an expanded patch is configured, never while scrolling. Bump each item's version when its collapse state changes so Pierre applies the update.
