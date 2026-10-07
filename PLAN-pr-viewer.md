# In-app PR Viewer

## Decision Log
- 2026-10-08: Add General Settings > Open PR destination (Browser by default, In App opt-in). Route GitHub PR and comment URLs through AppController; other links retain their normal destination.
- 2026-10-08: Match the supplied references with a summary and chronological activity column, persistent merge/thread/review/check sidebar, and compact toolbar. Code diffs are deferred. This first viewer reads GitHub data; GitHub editing/reply/resolve actions open their original URLs.
- 2026-10-08: Use a reusable native table for the variable-height conversation, bounded page sizes, prepared Markdown outside scrolling, and explicit load-more controls. Do not mount all comment views or perform HTTP, parsing, or avatar downloads during scrolling.

## Task Board
### PV01: Build and validate the PR viewer
- status: `done`
- owner: `codex-main`
- goal: present a performant native PR conversation window when the saved destination is In App.
- verification: `swift test` passed all 102 core tests; `xcodebuild test` passed all 105 app tests. Covered saved defaults, PR/comment routing, window reuse, browser fallback, Dock restoration, sign-out cleanup, pagination, cancellation, stale-response rejection, expansion/collapse and repeated thread navigation. Existing SceneStorage warnings remain in three unrelated rendering tests.
- verification: Tuist generation and `./script/build_and_run.sh --verify` passed; development build launched. Exact summary/activity/thread/reply GraphQL queries validated against a live GitHub PR. Native UI automation could not inspect the menu-bar app (timeout); authenticated end-to-end browsing remains a manual acceptance check.
- verification: Fully measured 2,004-row native conversation, 80 scroll/layout/display jumps: p95 4.49 ms, maximum 7.30 ms, three mounted/visible cells. This is a local synthetic stress result, not a guarantee for every machine. TextKit measurement runs off the main actor in cancellable batches; scrolling reads cached metrics.
- verification: Light/dark summary, dark activity and compact-window rendering inspected; resized-title regression checks the wrapped header's actual frame height. Layout uses actual native cell width, including table insets. Evidence: [summary](/Users/ipavlidakis/workspace/gh-orchestrator/DerivedData/PRViewerQA/summary-dark.png), [activity](/Users/ipavlidakis/workspace/gh-orchestrator/DerivedData/PRViewerQA/activity-dark.png), [compact](/Users/ipavlidakis/workspace/gh-orchestrator/DerivedData/PRViewerQA/compact-dark.png), [performance](/Users/ipavlidakis/workspace/gh-orchestrator/DerivedData/PRViewerQA/performance.json).
- verification: Open Code Review delegation preview/rules and manual source review covered all ten selected production files; four test files and three design/plan files were reviewed separately (excluded by OCR's default paths/extensions). No unresolved findings; `git diff --check` passed.
- notes: Local implementation only; no publication requested. Viewer actions open GitHub for editing/replying/resolving; code diffs remain deferred as requested. Account changes close viewer windows and cancel loading.
