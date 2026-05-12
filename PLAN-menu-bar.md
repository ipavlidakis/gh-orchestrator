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
- When the Settings window is open, GHOrchestrator should remain reachable from the Dock even if the user's normal app behavior hides the Dock icon.
- The menu-bar window’s trailing `More` menu should surface an `Update` action when a newer app release is already available.

## Dependencies
- Reuse the existing app-state and refresh wiring from `T09`, `T10`, and `T12` in [PLAN.md](/Users/ipavlidakis/workspace/gh-orchestrator/PLAN.md).
- Keep all menu-command behavior in the app target; do not move any of this work into the local Swift package.

## Task Board

### T13: Settings Window App Menu Commands
- status: `done`
- owner: `codex-main`
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
  - 2026-04-14: `tuist generate --no-open` succeeded.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded.
  - 2026-04-14: `./script/build_and_run.sh --verify` succeeded.
  - 2026-04-14: an AppleScript/System Events inspection with the Settings window frontmost confirmed the top-level menu bar was reduced to `Apple`, `GHOrchestrator`, and `Help`, and the `GHOrchestrator` app menu showed `About GHOrchestrator`, `Refresh`, `Settings…`, standard visibility items, and `Quit GHOrchestrator`.
  - 2026-04-14: `GHOrchestratorTests.testAppMetadataHelpURLTargetsRepository` and `SettingsWindowCommandsTests` pin the Help-command target URL and command-routing seam in unit tests.
- notes:
  - The Settings window now drives menu pruning from `EnvironmentValues.appearsActive`, with a small AppKit helper hiding `Edit`, `View`, and `Window` only while the Settings scene is active.
  - The Help menu item was automation-clicked successfully, but the launched external browser did not expose a reliable URL readback path in this environment, so the exact destination is covered by the unit seam rather than browser-state automation.

### T14: Settings Window Dock Focus
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN.md:T12`, `PLAN-menu-bar.md:T13`
- goal: show GHOrchestrator in the Dock while the Settings window is open, even when the persistent Dock icon preference is hidden.
- scope:
  - track Settings window presentation from the Settings scene.
  - temporarily apply a visible Dock activation policy while Settings is open.
  - restore the user's persisted Dock icon preference after Settings closes.
  - update Settings copy if needed so the behavior is clear.
- deliverables:
  - app-target lifecycle wiring
  - focused controller tests for Dock icon state transitions
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after wiring Settings visibility into Dock icon policy.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-settings-dock -only-testing:GHOrchestratorTests/AppControllerTests` succeeded with Settings-window Dock override coverage.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app.
- notes:
  - Keep this in the app target; the core settings model should continue to store only the user's persistent preference.
  - Settings scene presentation now temporarily applies the visible Dock policy and restores the persisted preference on close.

### T15: Menu-Bar More Menu Update Action
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN.md:T47`
- goal: surface a direct update/install action in the menu-bar window’s trailing `More` menu whenever GHOrchestrator has already detected a newer release.
- scope:
  - keep the action in the app target menu-bar view layer.
  - reuse the existing `SoftwareUpdateModel` install path instead of adding new updater logic.
  - show the menu item only when an update is available or already installing.
  - keep the action disabled while no install can start.
- deliverables:
  - updated menu-bar `More` menu wiring
  - focused tests for the new menu action seam
- verification:
  - 2026-04-17: `tuist generate --no-open` succeeded.
  - 2026-04-17: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-menu-update -only-testing:GHOrchestratorTests/MenuBarMoreMenuTests -only-testing:GHOrchestratorTests/SoftwareUpdateModelTests -only-testing:GHOrchestratorTests/SettingsWindowCommandsTests` succeeded.
  - 2026-04-17: `./script/build_and_run.sh --verify` succeeded.
- notes:
  - The menu continues to show `Refresh`, `Settings`, and `Quit`; `Update` is inserted between `Refresh` and `Settings` only while `SoftwareUpdateModel` reports `.updateAvailable` or `.installing`, and it reuses the existing install request path.

### T16: AppKit-Owned Menu-Bar Window
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN.md:T10`, `PLAN-menu-bar.md:T15`
- goal: replace the SwiftUI `MenuBarExtra(.window)` dashboard host with an AppKit-owned status item and popover so menu-bar window sizing is explicit and stable.
- scope:
  - keep dashboard content in the existing SwiftUI view.
  - own menu-bar presentation from the app target with `NSStatusItem` and `NSPopover`.
  - pin the popover content size from a testable app-target configuration.
  - preserve Refresh, Update, Settings, Quit, filtering, and dashboard visibility lifecycle behavior.
- deliverables:
  - app-target menu-bar popover presenter
  - updated app scene wiring
  - focused tests for popover sizing configuration
- verification:
  - 2026-05-07: `tuist generate --no-open` succeeded.
  - 2026-05-07: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-popover -only-testing:GHOrchestratorTests/MenuBarPopoverPresenterTests -only-testing:GHOrchestratorTests/MenuBarMoreMenuTests` succeeded.
  - 2026-05-07: `./script/build_and_run.sh --verify` succeeded.
  - 2026-05-07: `git diff --check` succeeded.
- notes:
  - Settings opening must use app-target AppKit routing because the dashboard view is no longer hosted inside a SwiftUI scene with `openSettings` in the environment.
  - User-provided logs showed the old implementation creating `com.apple.controlcenter.statusitems` scenes, which matches the SwiftUI `MenuBarExtra` host path and supports moving sizing ownership into AppKit.

### T17: Dashboard Scrollbar Spacing
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN-menu-bar.md:T16`
- goal: keep loaded dashboard rows clear of the trailing scrollbar and flash the scrollbar instead of showing it continuously.
- scope:
  - add loaded-list trailing inset inside the menu-bar dashboard.
  - configure the menu-bar dashboard scroll view to use overlay autohiding scrollers and flash once on presentation.
- deliverables:
  - loaded-list trailing padding
  - app-target scroll-view configuration helper
- verification:
  - 2026-05-07: `tuist generate --no-open` succeeded.
  - 2026-05-07: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-popover -only-testing:GHOrchestratorTests/MenuBarPopoverPresenterTests -only-testing:GHOrchestratorTests/MenuBarMoreMenuTests` succeeded.
  - 2026-05-07: `./script/build_and_run.sh --verify` succeeded.
  - 2026-05-07: `git diff --check` succeeded.

### T18: Menu-Bar More Menu Settings Routing
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN-menu-bar.md:T16`
- goal: make the menu-bar dashboard More menu open Settings through the active SwiftUI app-menu command instead of relying only on responder-chain selectors.
- scope:
  - keep routing in the app-target menu-bar presenter.
  - preserve the existing `showSettingsWindow:` and `showPreferencesWindow:` fallback selectors.
  - add focused coverage for the app-menu Settings command route.
- deliverables:
  - updated menu-bar popover Settings routing
  - focused presenter tests
- verification:
  - 2026-05-12: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-settings-more-menu -only-testing:GHOrchestratorTests/MenuBarPopoverPresenterTests -only-testing:GHOrchestratorTests/MenuBarMoreMenuTests` succeeded.
  - 2026-05-12: `./script/build_and_run.sh --verify` succeeded.
  - 2026-05-12: `git diff --check` succeeded.

## Decision Log
- 2026-04-14: when the Settings window is active, GHOrchestrator must present its app menu in the macOS menu bar with `About`, `Refresh`, `Settings…`, `Quit`, and `Help`; `Refresh` belongs directly under `About`, the top-level `Edit`, `View`, and `Window` menus must be hidden, and `Help` opens `https://github.com/ipavlidakis/gh-orchestrator`.
- 2026-04-15: the persisted "Hide Dock icon" preference should be temporarily overridden while the Settings window is open so users can refocus the Settings window from the Dock after it loses focus.
- 2026-04-17: the menu-bar window’s trailing `More` menu should show an `Update` action only when the updater has already detected a newer release; selecting it should reuse the existing direct-DMG install flow.
- 2026-05-07: the menu-bar dashboard window should be AppKit-owned rather than hosted by `MenuBarExtra(.window)` so sizing is explicit instead of relying on SwiftUI scene intrinsic sizing.
