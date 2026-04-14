# GH Orchestrator Feature Plan: Menu Bar Commands

## Purpose
- This file tracks feature-specific work for the Settings-window app menu behavior.
- Shared repo history and completed base milestones remain in [PLAN.md](/Users/ipavlidakis/workspace/gh-orchestrator/PLAN.md).
- Claim one task at a time in this file by setting its `owner` and moving `status` to `in_progress`.

## Summary
- When the Settings window is active, GHOrchestrator should present its own app menu in the macOS menu bar.
- The app menu must support `About`, `Refresh`, `Settings…`, `Quit`, and `Help`.
- `Refresh` must appear directly under `About`.
- The top-level `Edit`, `View`, and `Window` menus should be hidden while this menu set is active.
- `Help` opens `https://github.com/ipavlidakis/gh-orchestrator`.

## Dependencies
- Reuse the existing app-state and refresh wiring from `T09`, `T10`, and `T12` in [PLAN.md](/Users/ipavlidakis/workspace/gh-orchestrator/PLAN.md).
- Keep all menu-command behavior in the app target; do not move any of this work into the local Swift package.

## Task Board

### T13: Settings Window App Menu Commands
- status: `pending`
- owner: `unassigned`
- depends_on: `PLAN.md:T09`, `PLAN.md:T10`, `PLAN.md:T12`
- goal: make the active Settings window present a GHOrchestrator-specific app menu with the required actions while hiding the unused top-level menus.
- scope:
  - add app-target command definitions for `About`, `Refresh`, `Settings…`, `Quit`, and `Help`.
  - route `Refresh` through the existing dashboard refresh path.
  - keep `Settings…` wired to the existing settings-opening flow.
  - use the standard macOS About panel.
  - add a small app-target AppKit helper if needed to hide the top-level `Edit`, `View`, and `Window` menus when the Settings window is key.
- implementation notes:
  - `Refresh` should appear directly under `About` in the application menu.
  - preserve standard macOS application items that are not explicitly in scope unless they conflict with the required menu layout.
  - opening the Settings window should continue to activate GHOrchestrator so its app menu becomes the active macOS menu bar menu set.
- deliverables:
  - app-target menu command definitions
  - any small app-target AppKit menu-pruning helper required to hide top-level menus
- verification:
  - `tuist generate --no-open`
  - `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData`
  - `./script/build_and_run.sh --verify`
  - manual check with the Settings window frontmost confirming the app menu is active, `Refresh` is under `About`, `Help` opens the repo page, and `Edit` / `View` / `Window` are absent.

## Decision Log
- 2026-04-14: when the Settings window is active, GHOrchestrator must present its app menu in the macOS menu bar with `About`, `Refresh`, `Settings…`, `Quit`, and `Help`; `Refresh` belongs directly under `About`, the top-level `Edit`, `View`, and `Window` menus must be hidden, and `Help` opens `https://github.com/ipavlidakis/gh-orchestrator`.
