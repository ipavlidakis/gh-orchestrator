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

### T19: Browser Link Dock Policy Restoration
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN-menu-bar.md:T14`, `PLAN-menu-bar.md:T16`
- goal: keep GHOrchestrator out of the Dock after a dashboard link opens in the browser when the persisted Dock icon preference is hidden.
- scope:
  - route dashboard browser links through the app controller that owns Dock visibility.
  - reapply the effective Dock icon preference after handing the URL to the browser.
  - add focused controller coverage for the browser-open path.
- deliverables:
  - app-target browser link routing
  - focused controller regression test
- verification:
  - 2026-07-16: `tuist generate --no-open` succeeded.
  - 2026-07-16: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-dock-link -only-testing:GHOrchestratorTests/AppControllerTests -only-testing:GHOrchestratorTests/MenuBarPopoverPresenterTests` succeeded.
  - 2026-07-16: `xcodebuild build -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData` succeeded.
  - 2026-07-16: the rebuilt app was launched in the background with the persisted hidden-Dock preference, and `lsappinfo` reported `type="UIElement"`.
  - 2026-07-16: `git diff --check` succeeded.
- notes:
  - Keep Settings-window Dock visibility behavior unchanged.
  - Dashboard links now route through `AppController`, which reapplies the effective Dock policy on the next main-actor turn after sending the URL to the browser.

### T20: Dashboard Status Icons And Contrast
- status: `done`
- owner: `codex-main`
- depends_on: `T16`
- goal: show skipped jobs and steps neutrally, improve contrast, and adopt native macOS controls and materials that adapt to Liquid Glass environments.
- scope:
  - use a gray minus-circle for skipped jobs and steps.
  - use regular material behind content, an opaque system background with Reduce Transparency, and primary text on tinted badges.
  - use native bordered menus, a regular-size segmented picker, stronger title hierarchy, and row separators.
- verification:
  - 2026-10-01: Tuist generation and build/launch verification succeeded using `/tmp/GHOrchestrator-DashboardFeedback`.
  - 2026-10-01: nine focused app tests passed, including native dashboard rendering in light/dark appearances and popover/menu behavior. The icon regression failed with the old red icon (64 red pixels in light mode) and passed after restoring the neutral icon.
  - 2026-10-01: inspected native-hosted light/dark screenshots; UI automation could not see the running app, so live popup interaction remains unverified.

### T21: Stable Alphabetical Pull Request Ordering
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN.md:T06`
- goal: order PRs by title within each repository so updates do not move rows.
- scope:
  - use case-insensitive natural title ordering and PR number for equal-title ties.
  - preserve repository ordering by its most recently updated PR.
- verification:
  - 2026-10-01: the title-order regression failed on the old update-time sorter, then all four aggregation tests passed after the change.
  - 2026-10-01: final app build succeeded with zero compiler warnings/errors. Earlier UI build/launch verification passed; no further launch followed the sorting edit to avoid repeated Keychain authorization prompts.
  - 2026-10-01: the full core suite passed 89 tests and failed the unchanged `testFetchRepositorySnapshotsReturnsSuccessfulResultsWhenSomeRepositoriesFail`; its FIFO success/failure mock assumes task-group requests arrive in repository input order.
- notes:
  - Development builds are ad-hoc signed with different hash-based designated requirements and read `GHOrchestrator.github.com` at startup, explaining repeated Keychain prompts after rebuilds. Stable development signing is a separate follow-up; no signing or Keychain permissions were changed.

### T22: Native Popover And Dashboard Controls
- status: `done`
- owner: `codex-main`
- depends_on: `T20`, `T21`
- goal: remove custom dashboard chrome and use native HIG components and system Liquid Glass controls.
- scope:
  - remove root material fills, capsule badges, and custom scrollbar/disclosure styling.
  - use native ScrollView, DisclosureGroup, Label, menu, and button styles with macOS 15 fallbacks.
- verification:
  - 2026-10-01: Tuist generation, build/launch verification, and all 26 focused app tests passed, including full dashboard rendering with expanded checks in light/dark appearances. Zero compiler warnings/errors.
  - 2026-10-01: inspected the signed live popup. Native List swallowed nested disclosure controls; replaced it with standard ScrollView, then the restored full-dashboard rendering regression passed.
- notes:
  - Final live pointer interaction could not be repeated because the UI inspector cannot access the hidden status item. Final build launch and native-hosted dashboard rendering were verified.

### T23: Stable Development Signing
- status: `done`
- owner: `codex-main`
- goal: preserve the app's Keychain identity across local rebuilds using the existing personal Apple Development certificate.
- verification:
  - 2026-10-01: Tuist generation and Debug build succeeded using the existing Apple Development: ILIAS PAVLIDAKIS (JG8762YVLT) certificate, team UBW6JB7T2F.
  - 2026-10-01: changed the build version via an Xcode command-line override and rebuilt; both builds had identical certificate-based designated requirements. Deep strict signature verification passed.
- notes:
  - Existing ad-hoc Keychain authorization may require one Always Allow approval for the new stable identity. Keychain access controls are unchanged.

### T24: Native Settings Components
- status: `done`
- owner: `codex-main`
- depends_on: `T22`, `T23`
- goal: adapt every Settings pane to native macOS components and system Liquid Glass styling.
- verification:
  - 2026-10-01: Tuist generation, signed build/launch verification, and all 25 focused Settings model/store/window-command tests passed with zero compiler warnings/errors. Strict deep signature verification passed.
  - 2026-10-01: checked every Settings source for custom backgrounds, overlays, and forced menu styles; none remain.
- notes:
  - All six panes use a grouped Form; shared group/row helpers now compose native Section and LabeledContent. Native menus, repository controls, and notification preview content replace painted chrome; macOS 26 uses system glass button styles with native macOS 15 fallbacks.
  - Live visual interaction remains unverified because native UI automation is not exposed in this turn.

### T25: Settings Layout Regressions And Visible Sorting
- status: `done`
- owner: `codex-main`
- depends_on: `T24`
- goal: fix the reported wrapped/duplicate control labels and expose persisted PR sorting.
- verification:
  - 2026-10-01: Tuist generation, signed build/launch verification, and strict deep signature verification passed with zero build warnings/errors.
  - 2026-10-01: 24 focused core and 48 focused app tests passed. After the final polling/query-limit controls edit, 21 dashboard/model/Settings-render tests passed; the final dashboard rendering test also passed with a visible Sort control in both appearances.
  - 2026-10-01: restoring the old nested-label behavior produced four rendering assertion failures (duplicate title/author labels in light/dark); restoring the fix passed. Inspected native-hosted General, Insights, notification-preview, and dashboard renders in light/dark. Polling units, query-limit values, long repository/workflow selections, and Sort remain readable.
- notes:
  - Dashboard Sort and Settings > General > Pull request order share the saved title/creation-date preference and update loaded content immediately without fetching. Creation sorting uses the actual GitHub createdAt timestamp; legacy missing dates sort last.
  - Settings rendering outside the app Scene emits the expected SceneStorage default-value warning. Native-hosted renders do not prove live pointer interaction or full-window glass composition; native UI automation is unavailable in this turn.
  - A bounded elapsed-time wait replaced a scheduler-turn-count wait in the existing command-failure test helper after rendering load exposed its race; production failure behavior and assertions remain unchanged.

### T26: Insights Control Alignment And Notification Preview Layout
- status: `done`
- owner: `codex-main`
- depends_on: `T25`
- goal: align native Insights pickers at the form trailing edge and show readable notification preview content.
- verification:
  - 2026-10-01: both native rendering regressions failed before the fix (four light/dark alignment failures), then passed after removing picker widths and moving preview text into its own native Section.
  - 2026-10-01: all 27 focused Settings rendering/model/store/window tests passed. Inspected light/dark Insights and notification-preview renders; CodeQL aligns with the other selected values and preview title/body use the section's leading edge with primary, body-sized text.
  - 2026-10-01: Tuist generation, signed build/launch verification, strict deep signature verification, and diff whitespace checks passed. Build had zero warnings/errors; the rendering harness retains its known SceneStorage warning outside an app Scene.
- notes:
  - Native-hosted renders verify layout but do not prove live pointer interaction/full-window glass composition. Existing fields, preview formatting, and delivery actions remain wired to the same models.

### T27: Dashboard And Settings Feedback Delivery
- status: `in_progress`
- owner: `codex-main`
- depends_on: `T20`, `T21`, `T22`, `T23`, `T24`, `T25`, `T26`
- goal: review and publish the accumulated feedback fixes as a feature-branch PR.
- verification:
  - 2026-10-01: OCR workspace preview and Swift rules resolved; host review covered all 15 delivered source/config files with no blocking findings. Manually reviewed the eight test/fixture files and two plan files excluded by OCR defaults. Local `.codex/config.toml` was skipped as unrelated workspace configuration; Finder metadata is excluded.
  - 2026-10-01: final candidate passed 24 focused core tests and 50 focused app tests. The only warning is the known SceneStorage default-value warning in the native rendering harness; diff whitespace checks passed.
  - pending: branch commit/push and PR creation.

## Decision Log
- 2026-10-01: remove fixed-width wrappers from Insights pickers so native Form alignment governs their placement. Show notification preview content in its own native Section with full-width leading-aligned title/body text, outside LabeledContent value styling.
- 2026-10-01: expose title A-Z, creation newest first, and creation oldest first in the dashboard and General Settings. Save the choice; re-sort loaded content immediately without a network refresh. Fetch the actual GitHub PR creation timestamp. Hide duplicate nested control labels while preserving accessible names and native Form layout.
- 2026-10-01: Settings follows the same native-system direction as the dashboard: grouped Forms and Sections, LabeledContent rows, standard controls, and no painted cards or custom panel fills. Keep the native sidebar and macOS 15 compatibility.
- 2026-10-01: user authorized stable Apple Development signing. Debug builds use personal team UBW6JB7T2F and an existing valid certificate; preserve Release signing and Keychain access controls.
- 2026-10-01: superseding T20's material/pill treatment after user feedback: let the native popover provide its background, replace painted badges and hand-built disclosures with standard Labels and DisclosureGroup, and use the system glass button style on macOS 26+. Use native ScrollView rather than List because List hides the nested disclosure controls. Remove the custom scrollbar configurator; use platform defaults.
- 2026-10-01: default PR ordering is title A-Z within each repository, with natural numeric ordering and PR-number ties; repository sections continue to use their latest PR update. This chooses the user's title option without adding a sort preference.
- 2026-10-01: skipped Actions jobs and steps use a neutral minus-circle. Following the HIG and Liquid Glass follow-up, use native controls for navigation, standard regular material for content, and an opaque system background when Reduce Transparency is enabled. Keep primary badge text over status tints; Ready/Draft use neutral styling.
- 2026-04-14: when the Settings window is active, GHOrchestrator must present its app menu in the macOS menu bar with `About`, `Refresh`, `Settings…`, `Quit`, and `Help`; `Refresh` belongs directly under `About`, the top-level `Edit`, `View`, and `Window` menus must be hidden, and `Help` opens `https://github.com/ipavlidakis/gh-orchestrator`.
- 2026-04-15: the persisted "Hide Dock icon" preference should be temporarily overridden while the Settings window is open so users can refocus the Settings window from the Dock after it loses focus.
- 2026-04-17: the menu-bar window’s trailing `More` menu should show an `Update` action only when the updater has already detected a newer release; selecting it should reuse the existing direct-DMG install flow.
- 2026-05-07: the menu-bar dashboard window should be AppKit-owned rather than hosted by `MenuBarExtra(.window)` so sizing is explicit instead of relying on SwiftUI scene intrinsic sizing.
