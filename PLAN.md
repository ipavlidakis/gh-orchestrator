# GH Orchestrator Plan

## Purpose
- This file is the live execution plan for building `GHOrchestrator`.
- Agents should claim one task at a time by setting its `owner` and moving `status` to `in_progress`.
- When a task is finished, the agent must update `status`, `verification`, and any follow-on notes before handing off.
- Do not change product decisions in this file silently. Add changes to the decision log first.

## Product Summary
- Build a Tuist-managed macOS app named `GHOrchestrator`.
- Use only Swift, Tuist, SwiftPM, Apple frameworks, and the installed `gh` CLI.
- Ship a menu-bar-first app using `MenuBarExtra` plus a dedicated Settings window.
- Observe only user-configured repositories, then list the logged-in user's open PRs in those repositories.
- Group PRs by repository and sort repositories and PRs by most recent `updatedAt`.
- Show PR review state, checks state, unresolved review-thread count, and expandable Actions jobs plus steps.
- Do not auto-refresh when the menu window opens or while it is visible; background polling runs only while the menu window is hidden.

## Fixed Decisions
- Platform target: macOS 15+.
- Authentication source: current active `gh` account on `github.com`.
- Persistence: app settings live in an Application Support file (`plist` or `json`), not `UserDefaults`; no database or disk cache.
- Empty repository list means the app is not configured yet. It does not fall back to all repositories.
- Polling interval is configurable, defaults to `60` seconds, and must be clamped to `15...900`.
- Step links use `job.html_url#step:<stepNumber>:1` and fall back to `job.html_url`.
- No third-party libraries or GitHub SDKs.

## Architecture Outline
- App target: SwiftUI macOS app with `MenuBarExtra` and `Settings` scenes.
- Local package: core domain models, `gh` process client, mappers, fixtures, and tests.
- App layer owns UI state, settings binding, polling lifecycle, and URL opening.
- Core layer owns process execution, CLI health checks, GraphQL/REST parsing, PR aggregation, and validation helpers.

## Task Board

### T01: Repo Contract And Execution Bootstrap
- status: `done`
- owner: `codex-main`
- depends_on: `none`
- goal: create the repo-level collaboration and local run foundations so every later task has a stable workflow.
- scope:
  - create `AGENTS.md` with repo rules, architecture boundaries, validation expectations, and task-claim/progress workflow.
  - scaffold Tuist workspace manifests for a macOS app target, a unit-test target, and one local package dependency.
  - add `script/build_and_run.sh` for kill/build/run with optional `--debug`, `--logs`, `--telemetry`, and `--verify`.
  - add `.codex/environments/environment.toml` wired to `./script/build_and_run.sh`.
- implementation notes:
  - app name is `GHOrchestrator`.
  - keep the local package separate from the app target from the first commit.
  - do not add any dependency managers other than Tuist + SwiftPM.
- deliverables:
  - bootstrapped project structure
  - run script
  - environment config
  - `AGENTS.md`
- verification:
  - 2026-04-14: `tuist generate --no-open` succeeded.
  - 2026-04-14: `./script/build_and_run.sh --verify` succeeded.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded.
- notes:
  - Generated workspace and project files are intentionally gitignored; rerun `tuist generate --no-open` after manifest changes.

### T02: Core Domain Models And Settings Schema
- status: `done`
- owner: `codex-main`
- depends_on: `T01`
- goal: define stable data types used across parsing, aggregation, persistence, and UI.
- scope:
  - add models for `ObservedRepository`, `AppSettings`, `GitHubCLIHealth`, `RepositorySection`, `PullRequestItem`, `ReviewStatus`, `CheckRollupState`, `ExternalCheckItem`, `WorkflowRunItem`, `ActionJobItem`, and `ActionStepItem`.
  - add parsing and validation helpers for repository input and polling interval clamping.
  - keep model types value-based and `Sendable` where appropriate.
- implementation notes:
  - `ObservedRepository` should normalize whitespace and expose `owner`, `name`, and `fullName`.
  - `AppSettings` should be serializable to a file-backed settings store in Application Support without database infrastructure.
  - `GitHubCLIHealth` should model at least: `missing`, `loggedOut`, `authenticated(username:)`, and `commandFailure(message:)`.
- deliverables:
  - core model files in the local package
  - settings validation helpers
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after integrating the package models.
- notes:
  - Duplicate repositories are collapsed case-insensitively while preserving the first user-entered spelling.

### T03: Process Runner And GH CLI Health Checks
- status: `done`
- owner: `codex-main`
- depends_on: `T01`, `T02`
- goal: provide the low-level process execution surface and CLI availability/authentication checks.
- scope:
  - implement `ProcessRunner` abstraction and production `Process`-based runner.
  - implement `GHCLIClient` / `ProcessGHCLIClient` command execution utilities.
  - add CLI health checks using `gh --version` and `gh auth status`.
  - parse active username from authenticated status output.
- implementation notes:
  - process execution must capture exit code, stdout, and stderr.
  - missing binary should map to `GitHubCLIHealth.missing`, not a generic failure.
  - non-zero `gh auth status` with recognizable “not logged in” output should map to `loggedOut`.
- deliverables:
  - process-running service code
  - health-check service code
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded with mocked coverage for missing binary, logged out, authenticated, and generic command failure.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after integrating the process and `gh` health services.
- notes:
  - `gh auth status` is scoped to `--hostname github.com` so health mapping matches the fixed authentication decision.

### T04: GraphQL PR Fetch And Snapshot Mapping
- status: `done`
- owner: `codex-main`
- depends_on: `T02`, `T03`
- goal: fetch the logged-in user's open PRs for configured repositories and map them into view-ready snapshot inputs.
- scope:
  - for each configured repository, call `gh api graphql` with `repo:<owner/repo> is:pr is:open author:@me archived:false`.
  - request PR title, number, URL, draft state, `updatedAt`, `reviewDecision`, `reviewThreads`, and `statusCheckRollup`.
  - count unresolved review threads where `isResolved == false` and `isOutdated == false`.
  - capture unresolved review comment details needed by the UI, including comment text, author, file path, and comment URL.
  - normalize GraphQL payloads into intermediate core models.
- implementation notes:
  - aggregate results across repositories concurrently with Swift concurrency.
  - repository-level failures should surface enough context to debug which repo failed.
  - keep raw DTOs separate from final domain models.
- deliverables:
  - GraphQL query builder or query constant
  - DTO decoding
  - snapshot mapper for PR basics, review state, unresolved comments, and check rollup
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded with fixture-driven coverage for no PRs, approved PR, review-required PR, draft PR, repository-scoped query construction, and unresolved-thread counting.
  - 2026-04-14: `tuist generate --no-open` succeeded after adding the GraphQL snapshot layer.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after integrating the fetch layer.
- notes:
  - Snapshot inputs now preserve raw `CheckRun` and `StatusContext` data so T05 can enrich Actions jobs without re-fetching PR basics.
  - Unresolved review comment details are now captured from GraphQL with a bounded nested comment query to stay under GitHub's node-limit constraints.

### T05: Actions Jobs And Step Expansion Pipeline
- status: `done`
- owner: `codex-main`
- depends_on: `T04`
- goal: enrich PR check data with GitHub Actions jobs and steps while preserving non-Actions checks.
- scope:
  - detect Actions-backed checks from `statusCheckRollup` check runs.
  - collect unique workflow run identifiers per PR.
  - call `gh api repos/{owner}/{repo}/actions/runs/{runID}/jobs`.
  - decode jobs, steps, URLs, statuses, conclusions, and timestamps.
  - merge Actions jobs into `WorkflowRunItem` / `ActionJobItem` / `ActionStepItem`.
  - keep non-Actions checks as `ExternalCheckItem`.
- implementation notes:
  - if multiple check runs point to the same workflow run, fetch the jobs once.
  - queued jobs may have no steps; that is valid and should still render.
  - the UI contract is “show all checks; only Actions checks gain nested jobs/steps.”
- deliverables:
  - REST DTO decoding and merging logic
  - step-link helper
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded with coverage for completed jobs with steps, queued jobs without steps, mixed external checks, per-run fetch deduplication, and correct step URL generation.
  - 2026-04-14: `tuist generate --no-open` succeeded after adding the Actions jobs enrichment layer.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after integrating the enrichment layer.
- notes:
  - Actions-backed checks are grouped by workflow run using `checkSuite.workflowRun`, while non-Actions check runs and status contexts remain flat external checks.

### T06: Repository Section Aggregation And Sorting
- status: `done`
- owner: `codex-main`
- depends_on: `T04`, `T05`
- goal: produce the exact grouped and sorted structure consumed by the UI.
- scope:
  - group PRs into `RepositorySection`.
  - sort PRs descending by `updatedAt`.
  - sort repository sections descending by the newest PR in each section.
  - expose a final snapshot shape ready for the dashboard model.
- implementation notes:
  - sorting rules should be deterministic for ties; use repository name and PR number as secondary keys.
  - repository sections with zero PRs should not be emitted.
- deliverables:
  - aggregation service or mapper
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded with coverage for multi-repo ordering, same-timestamp tie behavior, and hidden empty observed repositories.
- notes:
  - Aggregation now accepts the observed repository list plus flat pull request items so empty configured repositories can be dropped explicitly.

### T07: Settings Persistence And Settings Model
- status: `done`
- owner: `codex-main`
- depends_on: `T02`, `T03`
- goal: persist app configuration and expose settings editing state to the SwiftUI settings scene.
- scope:
  - implement `SettingsStore` backed by an Application Support settings file (`plist` or `json`).
  - implement `SettingsModel` for repository editing, polling interval editing, validation messages, and live persistence.
  - wire CLI health into the settings state.
- implementation notes:
  - repository editing UX can use a multiline text field with one `owner/repo` per line.
  - invalid repository entries should be surfaced in settings instead of silently discarded.
  - settings writes should immediately update observers.
  - prefer the easiest reliable file format to work with (`plist` or `json`) under the app’s Application Support directory.
- deliverables:
  - settings store
  - settings model
- verification:
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:GHOrchestratorTests/SettingsStoreTests -only-testing:GHOrchestratorTests/SettingsModelTests` succeeded after migrating to an Application Support JSON store.
- notes:
  - Reopened on 2026-04-14 after the persistence decision changed from `UserDefaults` to an Application Support file-backed store.
  - Settings persistence now writes `settings.json` under the app’s Application Support directory.

### T08: Menu Bar Dashboard Model And Polling Lifecycle
- status: `done`
- owner: `codex-main`
- depends_on: `T03`, `T06`, `T07`
- goal: build the single observable owner for dashboard state, refresh logic, menu visibility handling, and expansion state.
- scope:
  - implement `MenuBarDashboardModel`.
  - add loading, empty, `gh missing`, `not logged in`, `no repositories configured`, and command-failure states.
  - do not auto-refresh on menu open.
  - poll only while the menu window is hidden using the configured interval.
  - cancel stale in-flight refreshes when a newer refresh starts.
  - preserve an in-flight hidden-window refresh when the menu opens so the first visible load can complete.
  - restart hidden-window polling immediately when settings change.
- implementation notes:
  - expansion state should be keyed by PR identity and preserved across refreshes where possible.
  - avoid overlapping refreshes.
  - inject clock/sleeper behavior if needed to make polling testable.
- deliverables:
  - dashboard observable model
  - refresh coordinator logic
- verification:
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/SettingsStoreTests` succeeded with coverage for initial load, configurable interval, cancellation on hide, restart on settings change, and error-state transitions.
- notes:
  - The app now has a shared `AppController` that keeps the settings store, dashboard model, and settings model on the same state graph.
  - Opening the menu stops future background polling but does not cancel an already-running hidden refresh.

### T09: Menu Bar UI
- status: `in_progress`
- owner: `codex-main`
- depends_on: `T08`
- goal: implement the menu bar dashboard experience.
- scope:
  - add the `MenuBarExtra` scene.
  - render a scrollable dashboard with repository sections and PR rows.
  - show title, number, draft state, relative last-updated text, review state, checks state, and unresolved-thread count.
  - implement split-action PR headers: title/open control opens the PR URL, checks badge toggles checks expansion, and unresolved-comments badge toggles unresolved comment expansion.
  - expanded content renders Actions workflow/job/step rows plus flat external check rows.
  - unresolved comment expansion renders comment rows with author, file path, and comment text, plus a trailing chevron to indicate browser navigation to the comment URL.
  - keep loading feedback in the header action area instead of replacing visible list content.
  - add top-level actions for opening Settings, manual refresh, and quitting the app.
- implementation notes:
  - keep the menu layout compact enough for menu-bar use, but allow richer detail in the expanded rows.
  - use native SwiftUI and AppKit URL opening only; no embedded web views.
- deliverables:
  - app scene and dashboard views
- verification:
  - 2026-04-14: `tuist generate --no-open` succeeded after the menu-bar dashboard view was extended to render Actions step rows.
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded after the menu-bar step-row changes.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:GHOrchestratorTests/AppControllerTests -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/SettingsStoreTests` succeeded.
  - 2026-04-14: `./script/build_and_run.sh --verify` succeeded.
- notes:
  - The placeholder menu content has been replaced with a real repository/PR dashboard view on top of `MenuBarDashboardModel`.
  - Metadata bubbles are rendered horizontally.
  - The checks and unresolved-comment bubbles own their own expansion states and show an expanded/collapsed indicator.
  - Refresh shows a header `ProgressView` in place of the refresh button; the list keeps its previous content while loading.
  - Expanded Actions content now renders workflow rows, job rows, and nested step rows with browser links derived from the job step URLs.
  - Manual visual verification of the menu-bar presentation is still pending because this session does not have macOS assistive access to open and inspect the popup automatically.

### T10: Settings Window UI
- status: `done`
- owner: `codex-t10`
- depends_on: `T07`
- goal: implement a dedicated Settings window with health and configuration controls.
- scope:
  - add a `Settings` scene.
  - show `gh` CLI installation/authentication status.
  - show setup instructions when `gh` is missing or logged out.
  - expose repository allowlist editing, polling interval controls, and a manual refresh action.
  - include any additional clearly useful v1 settings discovered during implementation, but keep scope tight.
- implementation notes:
  - settings copy should be operational and concise.
  - instructions should include the actual commands users need, for example `brew install gh` and `gh auth login`.
  - the manual refresh action should trigger the dashboard model, not duplicate fetch logic.
- deliverables:
  - settings views and supporting state wiring
- verification:
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded with the updated settings-window UI and `SettingsModelTests`.
- notes:
  - The settings window UI is implemented and verified against the Application Support-backed settings model/store layer.
  - The manual refresh hook and CLI health display are now wired through the shared app controller/dashboard model.

### T11: Fixtures, Tests, And Verification Pass
- status: `todo`
- owner: `unassigned`
- depends_on: `T04`, `T05`, `T06`, `T07`, `T08`
- goal: finish test coverage and end-to-end verification for the v1 scope.
- scope:
  - add checked-in GraphQL and Actions jobs fixtures.
  - complete all unit tests described in earlier tasks.
  - run `tuist generate`, build, and tests through the chosen local workflow.
  - capture any known limitations that remain acceptable for v1.
- implementation notes:
  - fixtures should be stable and minimal, not copied wholesale from large live payloads when a reduced sample is enough.
  - if one subsystem remains manually verified only, document exactly why.
- deliverables:
  - fixture files
  - test suite
  - verification notes
- verification:
  - all unit tests pass.
  - app builds successfully.

## Suggested Parallel Pickup Order
- Agent 1: `T01`
- Agent 2: `T02` after `T01` lands, then `T07`
- Agent 3: `T03` after `T01` and `T02`
- Agent 4: `T04` after `T02` and `T03`
- Agent 5: `T05` after `T04`
- Agent 6: `T06` after `T04` and `T05`
- Agent 7: `T08` after `T06` and `T07`
- Agent 8: `T09` after `T08`
- Agent 9: `T10` after `T07`
- Agent 10: `T11` after the core data and state tasks land

## Cross-Task Rules
- Keep the app target thin. Process execution and payload parsing belong in the local package.
- Do not call `gh` directly from SwiftUI views.
- Do not add non-Apple dependencies.
- Favor `Codable`, value types, and explicit mappers over loosely typed dictionaries.
- Keep failures user-visible and actionable, especially around `gh` installation and authentication.

## Decision Log
- 2026-04-14: v1 scope updated from “all open PRs for the user” to “open PRs for a user-configured repository allowlist”.
- 2026-04-14: polling changed from fixed cadence to a user-configurable interval with a Settings surface.
- 2026-04-14: dedicated Settings window added to show `gh` CLI health, connected account, and app configuration.
- 2026-04-14: app settings persistence changed from `UserDefaults` to a file-backed store in Application Support (`plist` or `json`).
- 2026-04-14: automatic refresh while the menu window is visible was disabled; polling now runs only while the window is hidden, and opening the menu must not trigger a reload.
- 2026-04-14: tapping the unresolved-comments badge should expand a list of unresolved review comments showing author, file path, and comment text, with comment rows linking to the browser.
- 2026-04-14: opening the menu must preserve an already-running hidden refresh rather than cancelling it, and loading feedback belongs in the header instead of replacing list content.
