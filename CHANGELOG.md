# Changelog

## 0.5.4 (Build 51) - 2026-10-07

- Show review comments with author avatars, timestamps, bordered cards, and full comment text.
- Restore the saved Dock visibility preference when the Settings window closes.
- Suppress the dashboard header's rectangular focus decoration and match the logo to the scope control's height with aspect-fit symbol scaling.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.5.3...0.5.4

## 0.5.3 (Build 50) - 2026-10-04

- Fixed Actions jobs remaining queued after they had completed on GitHub.
- Workflow summaries now reflect all jobs, and rerunning any job refreshes its cached results.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.5.2...0.5.3

## 0.5.2 (Build 49) - 2026-10-02

- Added Homebrew installation using the project's own tap.
- Updated the README with Homebrew instructions and screenshots of the current design.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.5.1...0.5.2

## 0.5.1 (Build 48) - 2026-10-01

- Load Actions insights much faster: job lookups are batched through GraphQL, run pages load concurrently, and completed runs are cached in memory.
- Speed up popover refresh by fetching workflow-run jobs concurrently and caching completed runs.
- Show Insights filters step by step (repository, workflow, job, period) with the first option preselected.
- Load Insights automatically whenever a filter changes; the Refresh button is gone.
- Fix Insights summary and trend card padding.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.5.0...0.5.1

## 0.5.0 (Build 47) - 2026-10-01

- Redesign the menu bar popover with a single-row header, status-chip PR cards, a checks progress bar, expandable workflow and job details, and a footer showing the update time and remaining API calls.
- Fit the popover height to its content and make repository headers collapse and expand from anywhere on the row.
- Add repository sorting by last modified, name, or team, ascending or descending.
- Redesign Settings with a Liquid Glass sidebar, title, and cards on macOS 26 and a flat fallback elsewhere.
- Refresh the app, Dock, and menu bar icons, with a status badge and attention count on the menu bar glyph.
- Enable Retry job only once the workflow run finishes and show GitHub's reason when a retry is denied.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.6...0.5.0

## 0.4.6 (Build 46) - 2026-10-01

- Make skipped jobs neutral and status text easier to read.
- Use native macOS controls throughout the dashboard and Settings.
- Add saved PR sorting by title or creation date.
- Fix Settings labels, workflow picker alignment, and notification preview layout.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.5...0.4.6

## 0.4.5 (Build 45) - 2026-07-16

- Fixed dashboard browser links so opening a pull request, workflow, job, step, check, or review comment no longer leaves GHOrchestrator visible in the Dock when the hidden-Dock preference is enabled.
- Routed dashboard URL opening through the app controller and added regression coverage for restoring the effective Dock policy after browser handoff.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.4...0.4.5

## 0.4.4 (Build 44) - 2026-05-12

- Fixed the menu-bar dashboard More menu so selecting Settings opens the Settings window through the active app-menu command.
- Preserved the existing AppKit selector fallbacks for Settings routing and added presenter coverage for the app-menu path.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.3...0.4.4

## 0.4.3 (Build 43) - 2026-05-07

- Replaced the SwiftUI `MenuBarExtra` dashboard host with an AppKit-owned status item and popover so menu-bar window sizing is stable.
- Added explicit dashboard popover sizing and preserved the existing dashboard actions, filters, Settings routing, and update install path.
- Added trailing spacing and overlay autohiding scrollbar behavior for the loaded dashboard list.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.2...0.4.3

## 0.4.2 (Build 42) - 2026-05-07

- Fixed the menu-bar dashboard loading state so refresh progress appears in the header without collapsing the window content.
- Made all-repository dashboard refreshes resilient to single-repository API failures by preserving successful repository results when at least one fetch succeeds.
- Added regression coverage for partial and all-failed repository snapshot refreshes.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.1...0.4.2

## 0.4.1 (Build 41) - 2026-04-17

- Added an `Update` action to the menu-bar window’s trailing More menu so a detected app update can be installed directly from the dashboard window.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.4.0...0.4.1

## 0.4.0 (Build 40) - 2026-04-17

- Added a Debug-only notification preview panel in Settings so every supported local notification trigger can be tested with synthetic sample data before enabling it for live repositories.
- Refreshed the macOS icon system with new Dock and menu-bar artwork, including appearance-aware Dock icons and a template-rendered monochrome status item glyph.
- Routed preview notifications through the same formatter and delivery path as live alerts so test sends match shipped notification behavior.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.3.1...0.4.0

## 0.3.1 (Build 31) - 2026-04-17

- Added the pull request title to workflow job completion notification descriptions so alerts are easier to identify from Notification Center.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.3.0...0.3.1

## 0.3.0 (Build 30) - 2026-04-16

- Refreshed the README with a fuller product overview for the current GHOrchestrator surface area.
- Added a screenshot gallery covering the menu-bar dashboard, expanded PR details, unresolved review comments, notifications, and insights settings.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.2.0...0.3.0

## 0.2.0 (Build 20) - 2026-04-15

- Added an Actions Insights dashboard in Settings for workflow success and duration trends.
- Added duration labels for individual GitHub Actions workflow steps in the menu-bar dashboard.
- Updated workflow job notification copy so local notifications are clearer.

**Full Changelog**: https://github.com/ipavlidakis/gh-orchestrator/compare/0.1.0...0.2.0
