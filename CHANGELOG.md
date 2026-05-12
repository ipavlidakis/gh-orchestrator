# Changelog

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
