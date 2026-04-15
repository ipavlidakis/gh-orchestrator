# GH Orchestrator Plan

## Purpose
- This file is the shared execution plan and registry for building `GHOrchestrator`.
- Agents should claim one task at a time by setting its `owner` and moving `status` to `in_progress`.
- When a task is finished, the agent must update `status`, `verification`, and any follow-on notes before handing off.
- Do not change product decisions in this file silently. Add changes to the decision log first.

## Product Summary
- Build a Tuist-managed macOS app named `GHOrchestrator`.
- Use only Swift, Tuist, SwiftPM, Apple frameworks, and direct GitHub HTTP APIs; do not depend on the `gh` CLI.
- Ship a menu-bar-first app using `MenuBarExtra` plus a dedicated Settings window.
- Authenticate the user via GitHub OAuth device flow launched from the app.
- Observe only user-configured repositories, then list either the logged-in user's open PRs or all open PRs in those repositories.
- Group PRs by repository and sort repositories and PRs by most recent `updatedAt`.
- Show PR review state, checks state, unresolved review-thread count, and expandable Actions jobs plus steps.
- Keep dashboard polling on the configured interval whether the menu window is hidden or visible; opening or closing the menu must not force an immediate refresh.

## Fixed Decisions
- Platform target: macOS 15+.
- Authentication source: GitHub OAuth App device flow using a browser verification step plus direct API polling.
- Public builds require only the GitHub OAuth client ID; they must not embed the OAuth client secret.
- Access tokens are stored in Keychain, not in `AppSettings`.
- GitHub scope for v1: `repo`.
- Persistence: app settings live in an Application Support file (`plist` or `json`), not `UserDefaults`; no database or disk cache.
- Empty repository list means the app is not configured yet. It does not fall back to all repositories.
- Polling interval is configurable, defaults to `60` seconds, and must be clamped to `15...900`.
- Step links use `job.html_url#step:<stepNumber>:1` and fall back to `job.html_url`.
- Source builds without OAuth credentials show a not-configured state instead of crashing.
- No third-party libraries or GitHub SDKs.

## Architecture Outline
- App target: SwiftUI macOS app with `MenuBarExtra` and `Settings` scenes.
- Local package: core domain models, OAuth device-code request and token polling, Keychain credential storage, GitHub GraphQL/REST transport, mappers, fixtures, and tests.
- App layer owns UI state, settings binding, polling lifecycle, browser-login launch, device-flow polling lifecycle, and URL opening.
- Core layer owns auth request building, device-code/token polling, credential storage, GraphQL/REST parsing, PR aggregation, and validation helpers.

## Active Feature Plans
- [PLAN-menu-bar.md](/Users/ipavlidakis/workspace/gh-orchestrator/PLAN-menu-bar.md): settings-window app menu commands and top-level menu pruning.
- [PLAN-notifications.md](/Users/ipavlidakis/workspace/gh-orchestrator/PLAN-notifications.md): per-repository local notification triggers for PR and workflow events.
- [PLAN-actions-insights.md](/Users/ipavlidakis/workspace/gh-orchestrator/PLAN-actions-insights.md): Settings dashboard for GitHub Actions workflow success and duration trends.
- Add future independent feature tracks as `PLAN-<feature>.md` files and list them here.

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
  - This task is retained as historical `gh`-based implementation work and is superseded for future auth and transport work by `T14` and `T15`.

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
  - This task is retained as historical `gh`-based implementation work and is superseded for future GraphQL transport work by `T16`.

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
  - This task is retained as historical `gh`-based implementation work and is superseded for future REST transport work by `T16`.

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
  - Opening the menu originally stopped future background polling but did not cancel an already-running hidden refresh; `T48` supersedes that hidden-window-only polling behavior.

### T09: Menu Bar UI
- status: `done`
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
  - 2026-04-14: user manually confirmed the menu-bar presentation, disclosure affordances, and collapsed-by-default Actions step behavior after reviewing screenshots.
- notes:
  - The placeholder menu content has been replaced with a real repository/PR dashboard view on top of `MenuBarDashboardModel`.
  - Metadata bubbles are rendered horizontally.
  - The checks and unresolved-comment bubbles own their own expansion states and show an expanded/collapsed indicator.
  - Refresh shows a header `ProgressView` in place of the refresh button; the list keeps its previous content while loading.
  - Expanded Actions content now renders workflow rows, job rows, and nested step rows with browser links derived from the job step URLs.
  - Manual visual verification was completed by the user because this session does not have macOS assistive access to open and inspect the popup automatically.

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
  - This task is retained as historical `gh`-centric settings work and is superseded for future auth UI work by `T18`.

### T11: Fixtures, Tests, And Verification Pass
- status: `done`
- owner: `codex-main`
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
  - 2026-04-14: checked-in minimal fixtures verified under `Packages/GHOrchestratorCore/Tests/GHOrchestratorCoreTests/Fixtures/PullRequestSearch` and `Packages/GHOrchestratorCore/Tests/GHOrchestratorCoreTests/Fixtures/ActionsJobs`.
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded.
  - 2026-04-14: `tuist generate --no-open` succeeded.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded.
  - 2026-04-14: `./script/build_and_run.sh --verify` succeeded.
- notes:
  - Core GraphQL and Actions jobs fixtures are checked in as reduced, stable payloads that back the package-level snapshot and enrichment tests.
  - Remaining acceptable v1 limitation: menu-bar popup presentation and Dock icon visibility changes still rely on manual visual verification because this session does not have a reliable desktop automation path for those macOS surfaces.

### T12: Settings Window Enhancements
- status: `done`
- owner: `codex-main`
- depends_on: `T10`
- goal: add the requested settings-window controls and align the preferences UI more closely with macOS settings conventions.
- scope:
  - add a persisted setting that lets people hide or show the Dock icon while the app is running.
  - apply the Dock icon preference at launch and when the setting changes.
  - add a Quit action to the Settings window.
  - update the Settings UI to use more native macOS settings patterns and components where practical.
- implementation notes:
  - use AppKit activation policy changes from the app target, not the local package.
  - keep the Dock icon preference clearly explained because hiding the Dock icon changes how people reopen Settings and access the app menu.
  - prefer `Form`, `Section`, `LabeledContent`, and standard controls over custom card-like settings layout.
- deliverables:
  - persisted Dock icon preference
  - runtime Dock icon visibility controller
  - updated Settings window UI
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the persisted Dock icon preference to `AppSettings`.
  - 2026-04-14: `tuist generate --no-open` succeeded after adding the Dock icon visibility controller and settings-window updates.
  - 2026-04-14: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:GHOrchestratorTests/AppControllerTests -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/SettingsStoreTests` succeeded.
  - 2026-04-14: `./script/build_and_run.sh --verify` succeeded.
  - 2026-04-14: user manually validated the revised settings window structure and menu-bar controls during iterative UI review.
- notes:
  - The settings window now uses a sidebar/detail preferences layout with grouped settings content and a list-style repository editor.
  - Dock icon visibility is applied from the app target through `NSApplication.setActivationPolicy(_:)`, with changes triggered from persisted settings.
  - Changing the Dock icon preference no longer triggers an unnecessary dashboard refresh.
  - Repository addition now uses a native `NSAlert` with a single-line `owner/name` text field instead of a delayed SwiftUI sheet presentation.

### T13: OAuth Pivot And Repo Contract Alignment
- status: `todo`
- owner: `unassigned`
- depends_on: `none`
- goal: align plan, repo contract, and top-level architecture with the OAuth direction.
- scope:
  - update `PLAN.md` fixed decisions and decision log.
  - update `AGENTS.md` to remove `gh` CLI as a repo requirement and replace it with OAuth/direct API guidance.
  - mark old `gh`-specific tasks as superseded in notes where helpful, without deleting completion history.
- deliverables:
  - updated planning docs only
- verification:
  - pending
- notes:
  - This task is documentation-only and should not claim implementation work for the runtime OAuth migration.

### T14: Core OAuth And Credential Storage
- status: `done`
- owner: `codex-main`
- depends_on: `T13`
- goal: add the auth primitives needed for browser login.
- scope:
  - add `OAuthAppConfiguration`, PKCE helpers, callback parsing, token exchange DTOs, session models, and a `GitHubCredentialStore` abstraction with Keychain implementation.
  - add auth state modeling to replace `GitHubCLIHealth`.
- implementation notes:
  - access tokens and resolved user identity live in Keychain.
  - no tokens in `settings.json`.
- deliverables:
  - core OAuth models and helpers
  - credential storage abstraction and Keychain-backed implementation
- verification:
  - 2026-04-14: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the core OAuth configuration, PKCE/callback helpers, session models, and Keychain-backed credential store.
- notes:
  - Added a package-local `Auth/` area with `OAuthAppConfiguration`, `OAuthCodeVerifier`, `OAuthCodeChallenge`, `OAuthState`, `OAuthCallback`, `GitHubTokenExchangeRequest`, `GitHubTokenExchangeResponse`, `GitHubSession`, `GitHubAuthenticationState`, and `KeychainGitHubCredentialStore`.
  - `GitHubCLIHealth` and the current app/UI consumers were left in place intentionally; `T15` should build direct `URLSession` transport on top of `GitHubTokenExchangeRequest` / `GitHubTokenExchangeResponse` and resolve `/user` into `GitHubSession.username`, while `T17`/`T18` should migrate app state and views to `GitHubAuthenticationState`.

### T15: Direct GitHub API Transport
- status: `done`
- owner: `codex-main`
- depends_on: `T14`
- goal: replace the CLI transport abstraction with authenticated HTTP transport.
- scope:
  - replace `GHCLIClient` with a GitHub API transport abstraction backed by `URLSession`.
  - add GraphQL and REST request helpers, bearer auth headers, and normalized HTTP/API error formatting.
  - support `GET /user` for connected-account resolution.
- deliverables:
  - authenticated API transport layer
  - direct GitHub GraphQL and REST request helpers
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the direct `URLSession`-backed GitHub API client, OAuth token exchange flow, `/user` resolution, and transport-level tests.
- notes:
  - Added `URLSessionGitHubAPIClient`, `GitHubAPIClient`, `GitHubHTTPTransport`, `URLSessionGitHubHTTPTransport`, `GitHubAuthenticatedUser`, shared GitHub JSON coders, and request/error handling for REST, GraphQL, and OAuth token exchange.
  - `GitHubTokenExchangeRequest` now produces a URL-encoded POST body for the OAuth access-token exchange, and successful exchange resolves `/user` before persisting the enriched `GitHubSession` to the credential store.
  - Legacy `GHCLIClient`, `GHPullRequestSnapshotService`, and `ActionsJobsEnrichmentService` still exist for compatibility; `T16` should switch those services to `URLSessionGitHubAPIClient` and remove `gh`-specific request execution afterward.

### T16: Snapshot And Actions Pipeline Migration
- status: `done`
- owner: `codex-main`
- depends_on: `T15`
- goal: preserve existing dashboard data behavior while removing `gh`.
- scope:
  - migrate `PullRequestSnapshotService` to `https://api.github.com/graphql`.
  - migrate `ActionsJobsEnrichmentService` to direct REST calls for workflow jobs.
  - keep repository grouping, sorting, unresolved-comment mapping, and Actions enrichment behavior unchanged.
- deliverables:
  - migrated snapshot and Actions enrichment services
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after migrating the snapshot and Actions enrichment services from `gh` subprocess execution to the direct GitHub API client.
- notes:
  - `GHPullRequestSnapshotService` now posts the existing GraphQL query through `URLSessionGitHubAPIClient`, and `ActionsJobsEnrichmentService` now fetches workflow jobs from `/repos/{owner}/{repo}/actions/runs/{runID}/jobs` via authenticated REST.
  - Fixture-backed service tests were converted to transport-backed tests so request bodies, endpoints, and preserved error messages are verified at the HTTP seam.
  - App-side dashboard/auth coordination still lags behind the package migration: `DashboardDataSource` and UI health/state remain `gh`-oriented until `T17` and `T18` migrate them to `GitHubAuthenticationState` and the OAuth session flow.

### T17: App OAuth Flow And Shared State
- status: `done`
- owner: `codex-main`
- depends_on: `T14`, `T15`
- goal: wire browser login into the app target.
- scope:
  - register the custom URL scheme.
  - add callback handling in the app scene.
  - add an app-owned auth coordinator that starts sign-in, validates callback `state`, exchanges the code, persists the session, and updates dashboard/settings state.
  - add sign-out support.
- deliverables:
  - app-target OAuth coordination and callback wiring
  - shared authenticated app state updates
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after registering the OAuth callback URL scheme and wiring the app-side auth flow.
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded with the app-compatible auth/transport layer in place.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after adding the app-owned auth coordinator, callback URL handling, and auth-state propagation tests.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after the app OAuth wiring changes.
- notes:
  - Added an app-owned `GitHubAuthController` that reads source-build OAuth configuration, launches browser sign-in, validates callback state, exchanges the code through the core client, and supports sign-out.
  - Callback delivery uses a macOS Apple-event URL handler plus app-local notification bridging instead of SwiftUI scene-level `onOpenURL`, which kept the menu-bar app compatible with hosted unit tests.
  - `AppController` now shares auth state into both the dashboard and settings models and forwards callback URLs to the auth controller.

### T18: Settings And Menu-Bar UI Migration
- status: `done`
- owner: `codex-main`
- depends_on: `T17`
- goal: replace all `gh`-centric UI states and copy.
- scope:
  - rename the Settings `GitHub CLI` section to `GitHub`.
  - replace install/login command instructions with `Sign in with GitHub`, connected account, sign-out, and not-configured/auth-failed messaging.
  - update menu-bar loading/error states to use auth-oriented states instead of `ghMissing` and `loggedOut`.
- deliverables:
  - migrated settings and menu-bar auth UI
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after the app manifest and SwiftUI settings/menu scenes were updated for OAuth auth states.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded with updated dashboard, settings, and auth-controller tests.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after the auth-oriented settings and menu-bar UI migration.
- notes:
  - The Settings `GitHub` pane now shows sign-in/sign-out actions, connected-account state, source-build not-configured messaging, and auth-failure messaging without any `gh` CLI instructions.
  - The menu-bar dashboard now uses `GitHubAuthenticationState`-driven empty/error states (`notConfigured`, `signedOut`, `authorizing`, `authFailure`) instead of `ghMissing` / `loggedOut`.
  - `T19` should treat the new app-side auth and UI tests as the baseline and only add extra fixtures or mocks where coverage is still missing, rather than reworking the migrated state model again.

### T19: Verification And Fixture Refresh
- status: `done`
- owner: `codex-main`
- depends_on: `T16`, `T17`, `T18`
- goal: re-establish package/app verification under the new auth and transport model.
- scope:
  - add OAuth, token, and user fixtures plus HTTP transport mocks.
  - update snapshot and enrichment tests to use mocked HTTP responses instead of mocked `gh` output.
  - rerun the standard verification commands.
- deliverables:
  - refreshed fixtures and tests
  - verification notes for the OAuth migration phase
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after refreshing the package fixtures and transport-backed test coverage.
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded with the refreshed OAuth/token/user fixtures and shared HTTP transport mocks.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after the app-side OAuth migration and fixture refresh.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after the end-to-end OAuth migration verification pass.
- notes:
  - Added `Fixtures/GitHubAPI` payloads for authenticated user lookup, GraphQL viewer success/error, token exchange success, and REST auth failure coverage.
  - `GitHubAPIClientTests` now use the shared `StubGitHubHTTPTransport`, `StubGitHubCredentialStore`, and fixture loader from `GitHubTestSupport.swift` instead of inline JSON payloads.
  - Snapshot and Actions enrichment tests remain transport-backed from `T16`; `T19` keeps that seam and extends the fixture set instead of introducing another mock layer.

### T20: OAuth App Setup Link
- status: `done`
- owner: `codex-main`
- depends_on: `T17`, `T18`, `T19`
- goal: help source builders register the required GitHub OAuth app from Settings.
- scope:
  - add a Settings action that opens the browser to the GitHub OAuth app registration or setup docs flow.
  - keep the existing OAuth architecture unchanged; this is guidance and UX, not a transport/auth redesign.
- deliverables:
  - settings link(s) for OAuth app registration/setup
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after adding direct OAuth app registration/docs URLs to the app metadata and settings UI.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after adding the Settings browser links and metadata assertions.
- notes:
  - The Settings `GitHub` pane now links directly to the GitHub OAuth app registration page and the GitHub OAuth app setup docs when the build is not configured.
  - This is source-builder guidance only; it does not change the app’s OAuth architecture or runtime transport behavior.

### T21: Build-Time OAuth Client ID Injection
- status: `done`
- owner: `codex-main`
- depends_on: `T17`, `T20`
- goal: ensure shipped builds can sign in with one button and no runtime env var.
- scope:
  - inject `GitHubOAuthClientID` into the app Info.plist from the build/generation environment.
  - keep source builds without the env var in the existing not-configured state.
- deliverables:
  - build-time client ID injection
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after wiring `GitHubOAuthClientID` to the generation/build environment in `Project.swift`.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after the build-time client ID injection change and Settings setup-link follow-up.
- notes:
  - Shipped builds can now include the public OAuth client ID in the app Info.plist by generating/building with `GH_ORCHESTRATOR_GITHUB_CLIENT_ID` set once; end users do not need to provide the env var at runtime.
  - Source builds without the env var still surface the existing not-configured state and Settings registration/docs links.

### T22: Local OAuth Config File
- status: `done`
- owner: `codex-main`
- depends_on: `T21`
- goal: support a repo-local, untracked OAuth client ID config file instead of requiring env vars.
- scope:
  - add a local config file format and committed example.
  - have `Project.swift` prefer the local config file, then env vars, then empty/not-configured.
  - update builder-facing Settings copy to mention the local config file path.
- deliverables:
  - local OAuth config file support
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after adding `Config/GitHubOAuth.local.json` support to `Project.swift`.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after the local config-file fallback and Settings copy update.
- notes:
  - `Project.swift` now prefers `Config/GitHubOAuth.local.json`, then falls back to `GH_ORCHESTRATOR_GITHUB_CLIENT_ID`, then empty/not-configured.
  - `Config/GitHubOAuth.local.example.json` is committed as the template and `Config/GitHubOAuth.local.json` is gitignored.
  - Builder-facing Settings copy now points to the local config file first, with env vars only mentioned as an optional fallback.

### T23: OAuth Client Secret Support
- status: `blocked`
- owner: `codex-main`
- depends_on: `T21`, `T22`
- goal: complete the GitHub OAuth code exchange with the app credentials GitHub currently requires.
- scope:
  - add `clientSecret` support to the local config/build injection path.
  - require both client ID and client secret for the OAuth app configured state.
  - send `client_secret` during the OAuth token exchange and update tests accordingly.
- deliverables:
  - working OAuth token exchange with client secret
  - verification notes
- verification:
  - pending
- notes:
  - Blocked on 2026-04-15 because a downloadable public app cannot safely ship the GitHub OAuth client secret in its bundle. `T24` replaces this direction with device flow.

### T24: Public Build Auth Pivot To Device Flow
- status: `done`
- owner: `codex-main`
- depends_on: `T17`, `T18`, `T19`, `T22`
- goal: make downloadable public builds authenticate without shipping an OAuth client secret.
- scope:
  - replace the browser redirect plus code-exchange flow with GitHub OAuth device flow.
  - require only the OAuth client ID in app configuration.
  - add device-code request and polling models/transport, including GitHub’s polling and backoff rules.
  - update app auth state, settings/menu-bar UX, and builder-facing copy for device flow and device-flow enablement.
  - remove callback-specific app wiring that is no longer needed.
- deliverables:
  - device-flow auth implementation across the package and app targets
  - updated plan/contract notes for public-build-safe auth
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after switching the shipped auth path to GitHub device flow and removing callback-specific app wiring.
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding device-code request and polling coverage.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after migrating the app auth controller, settings/menu-bar UI, and tests to device flow.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after removing the bundled OAuth client secret and custom callback URL dependency from the app target.
- notes:
  - This task supersedes the public-binary direction implied by `T23`, because embedding a GitHub OAuth client secret in a downloadable app bundle is not acceptable for release distribution.
  - Public builds now require only `GitHubOAuthClientID`; builders must enable device flow for the corresponding GitHub OAuth app in GitHub settings before distributing the app.

### T25: Observed Repository Removal Fix
- status: `done`
- owner: `codex-main`
- depends_on: `T10`, `T12`
- goal: make repository removal from the Settings window behave reliably.
- scope:
  - tighten the repository-list selection wiring used by the plus/minus controls.
  - make the removal path tolerant of normalized versus display-cased repository IDs.
  - add or update focused tests for the removal behavior.
- deliverables:
  - settings removal bug fix
  - verification notes
- verification:
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData -only-testing:GHOrchestratorTests/SettingsModelTests` succeeded after tightening the removal path and adding mixed-case ID coverage.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after the settings list selection wiring change.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after the observed-repository removal fix.

### T26: GitHub Release DMG Automation
- status: `done`
- owner: `codex-main`
- depends_on: `T24`
- goal: produce a repeatable direct-distribution release workflow for a signed, notarized `.dmg` that can be attached to a GitHub Release.
- scope:
  - enable Hardened Runtime for Release builds.
  - add repo-owned release tooling to archive the app, create a DMG, notarize/staple it, and compute checksums.
  - add an optional GitHub Releases upload path using the GitHub REST API.
  - document the required local Apple signing and notary prerequisites for maintainers.
- deliverables:
  - release automation script(s)
  - release workflow documentation
  - verification notes
- verification:
  - 2026-04-15: `bash -n script/release_dmg.sh` succeeded after adding config-file loading and GitHub upload/notarization preflight support.
  - 2026-04-15: `./script/release_dmg.sh --dry-run --allow-dirty` succeeded using the default `Config/Release.local.json` file with no release flags.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the Release Hardened Runtime manifest settings.
  - 2026-04-15: `xcodebuild -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -configuration Release -destination 'platform=macOS' -showBuildSettings` reported `ENABLE_HARDENED_RUNTIME = YES`.
- notes:
  - Added `Config/Release.local.example.json` and a gitignored `Config/Release.local.json` starter file so maintainers can drive releases from local JSON instead of long environment-variable command lines.
  - `script/release_dmg.sh` now auto-loads `Config/Release.local.json` by default; a clean release run can be triggered with `./script/release_dmg.sh` once the local file contains real signing, notary, OAuth, and GitHub token values.

### T27: Actions Failed-Step Retry
- status: `done`
- owner: `codex-main`
- depends_on: `T16`, `T18`, `T19`
- goal: let the menu-bar dashboard request a GitHub Actions retry from failed step rows when GitHub permits it.
- scope:
  - add core transport support for GitHub's "re-run a job from a workflow run" endpoint.
  - keep retry requests out of SwiftUI views by routing them through app/model/data-source seams.
  - show a retry affordance next to failed Actions step rows and disable it while the request is in flight.
  - surface permission or API failures inline without replacing the rest of the dashboard content.
- deliverables:
  - Actions job retry transport and model wiring
  - menu-bar failed-step retry affordance
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the Actions job-rerun transport and failed-step retry UI wiring.
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the GitHub job-rerun client coverage.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData-T27` stalled twice in this session after target-graph construction and never launched an `xctest` child process, so no app-target XCTest result was emitted.
  - 2026-04-15: `./script/build_and_run.sh --verify` stalled on the underlying `xcodebuild ... build` step in the same environment after target-graph construction, so app launch verification did not complete here.
- notes:
  - Failed Actions step rows now show a `Retry job` control when the step conclusion is not successful, and the control reruns the containing GitHub Actions job rather than the individual step because GitHub does not expose a step-level rerun endpoint.
  - Retry requests flow through the app dashboard model and data-source seam into a core `ActionsJobRetryService`, preserving the app/package boundary and keeping GitHub HTTP calls out of SwiftUI views.
  - Inline retry failures stay attached to the affected job row, and successful retry requests trigger a dashboard refresh without clearing the current visible content first.

### T28: Verification Runner Stall Triage
- status: `done`
- owner: `codex-main`
- depends_on: `T27`
- goal: identify and reduce the `xcodebuild`/verify stalls seen during local repo verification.
- scope:
  - reproduce the stall in the smallest meaningful build and test commands.
  - determine whether the blocker is in the repo configuration, generated project, or stale local Xcode helper processes.
  - add a focused repo-side mitigation if one is justified by the findings.
- deliverables:
  - root-cause notes
  - any targeted verification helper/script fix if needed
  - updated verification notes
- verification:
  - 2026-04-15: direct toolchain probe `/Applications/Xcode-26.4.0.app/.../clang -v -E -dM ... -c /dev/null` succeeded outside `xcodebuild`, confirming the compiler itself was healthy.
  - 2026-04-15: after killing stale `xcodebuild` process trees tied to `GHOrchestrator.xcworkspace`, `xcodebuild -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-build build` succeeded.
  - 2026-04-15: after the same cleanup, `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-test` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after adding stale-workspace-`xcodebuild` cleanup to the script.
- notes:
  - The apparent stall was not a project-graph or compiler crash. Stale `xcodebuild`/`SWBBuildService` process trees for this workspace were leaving child `clang -v -E -dM ...` probes blocked, which made later verification commands look hung before compilation started.
  - `script/build_and_run.sh` now resolves the workspace/project and proactively kills stale `xcodebuild` trees for the same workspace before starting a new build.
  - Once the runner stall was removed, the remaining real failure was a normal compile-time regression: two app-target test doubles were missing the new retry methods introduced by `T27`; those conformances are now updated.

### T29: App Icon Integration
- status: `done`
- owner: `codex-main`
- depends_on: `T01`
- goal: add a real macOS app icon asset so built binaries and release artifacts use the provided branding.
- scope:
  - add an asset catalog under the app target resources.
  - generate the required `AppIcon.appiconset` PNG sizes from the provided source image.
  - wire the app target build settings to compile the `AppIcon` asset for macOS.
- deliverables:
  - asset catalog resources
  - app target resource/build-setting update
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the asset catalog resources and `AppIcon` build setting.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after generating the `AppIcon.appiconset` PNGs from `/Users/ipavlidakis/Downloads/icon.png`.
- notes:
  - Added `App/Resources/Assets.xcassets/AppIcon.appiconset` with generated macOS icon sizes from the provided source image.
  - Added a matching `AccentColor.colorset` so the new asset catalog does not emit an extra missing-accent warning during normal builds.

### T30: Codex Release Action
- status: `done`
- owner: `codex-main`
- depends_on: `T26`
- goal: expose the release workflow through the Codex environment actions UI.
- scope:
  - add a small release wrapper script that prompts for `version` and `build`.
  - wire `.codex/environments/environment.toml` to expose a dedicated Release action.
  - keep the action pointed at the existing release script rather than duplicating release logic.
- deliverables:
  - interactive release wrapper script
  - environment action entry
  - verification notes
- verification:
  - 2026-04-15: `bash -n script/release_prompt.sh` and `bash -n script/release_dmg.sh` both succeeded.
  - 2026-04-15: `printf '1.0.2\n102\n' | ./script/release_prompt.sh --dry-run --allow-dirty` succeeded, confirming the wrapper prompts for `version` / `build` and forwards the release flags correctly.
- notes:
  - Added a new Codex environment `Release` action in `.codex/environments/environment.toml` that points at `./script/release_prompt.sh`.
  - The wrapper keeps `version` and `build` as prompt-time inputs while reusing the existing release pipeline and local JSON configuration.

### T31: Release target_commitish Fix
- status: `todo`
- owner: `unassigned`
- depends_on: `T26`, `T30`
- goal: make GitHub release creation resilient when the local branch is ahead of origin.
- scope:
  - stop defaulting `target_commitish` to a local-only `HEAD` SHA.
  - prefer the current branch name for release creation, with detached-head fallback to the commit SHA.
  - verify the release preflight path after the change.
- deliverables:
  - release script fix
  - verification notes
- verification:
  - pending
- notes:
  - Returned to the queue on 2026-04-15 with no repo changes recorded under this task so a separate documentation task could be claimed cleanly.

### T32: Repository Documentation
- status: `done`
- owner: `codex-main`
- depends_on: `T24`, `T26`, `T30`
- goal: add top-level docs that explain what the repo builds and how to build and run it from source.
- scope:
  - create `README.md` with the product summary, architecture split, repo layout, and primary workflows.
  - create a separate source-build guide covering prerequisites, local OAuth config, generation, build/run, verification, and troubleshooting entry points.
  - link the new docs to the existing release documentation without duplicating the release workflow.
- deliverables:
  - `README.md`
  - source-build instructions document
  - verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after adding `README.md` and `BUILDING.md`.
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after the new documentation files were added.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS' -derivedDataPath DerivedData` succeeded after the repo docs were added.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after documenting the source-build workflow.
- notes:
  - Added `README.md` for repo orientation and `BUILDING.md` for source-build setup, local OAuth config, verification, and troubleshooting.
  - The new docs intentionally link to `RELEASING.md` instead of duplicating the release pipeline.

### T33: Dashboard PR Scope And Repository Focus
- status: `done`
- owner: `codex-main`
- depends_on: `T16`, `T18`, `T27`
- goal: let the menu-bar dashboard switch between the signed-in user's PRs and all PRs across configured repositories, focus a single configured repository, and manage expanded dashboard detail predictably.
- scope:
  - add a dashboard control for `My PRs` versus `All PRs`.
  - add a dashboard repository focus control with `All repositories` and each configured repository.
  - keep GitHub query construction and repository filtering out of SwiftUI views.
  - let repository sections collapse and expand without removing them from the loaded data.
  - make opening a PR detail bubble collapse other expanded checks/comment bubbles first.
- deliverables:
  - core query-scope support
  - app dashboard filter state and controls
  - repository section collapse state
  - focused tests and verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding query-scope support for `My PRs` versus `All PRs`.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T33 -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/AppControllerTests` succeeded after adding dashboard filter and expansion-state coverage.
  - 2026-04-15: `tuist generate --no-open` succeeded.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T33-full` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded.
- notes:
  - This task keeps the configured repository allowlist as the source of truth. `All repositories` means all configured repositories, not every repository the GitHub account can access.
  - Dashboard filters are app-state controls, not persisted settings: the current session can switch PR scope and focus a configured repository without changing the repository allowlist.
  - Opening a checks or unresolved-comments detail bubble now collapses all other checks/comments detail bubbles; repository section collapse state is independent.

### T34: Dashboard Filter Header And PR Author Display
- status: `done`
- owner: `codex-main`
- depends_on: `T33`
- goal: tighten the menu-bar filter placement and show pull request authors when viewing all PRs.
- scope:
  - move the PR scope and repository focus controls into the header row before refresh/settings actions.
  - carry PR author login from GraphQL snapshots into dashboard rows.
  - show the PR author's username in `All PRs` mode without adding noise to `My PRs` mode.
- deliverables:
  - updated menu-bar header layout
  - author-login mapping through core and app models
  - focused tests and verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding PR author mapping through snapshot and enrichment models.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T33 -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/AppControllerTests` succeeded after moving filters into the menu header row.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after the header and author-display changes.
- notes:
  - The author display is scoped to `All PRs` because `My PRs` is already implied by the selected query scope.
  - Filters are hidden until the dashboard is authenticated and repositories are configured, then render inline before the refresh and settings actions.

### T35: Dashboard Rate-Limit Failure Handling
- status: `done`
- owner: `codex-main`
- depends_on: `T08`, `T10`, `T33`
- goal: keep the dashboard useful when GitHub rate limits or other refresh failures occur after data has already loaded.
- scope:
  - preserve the last loaded dashboard content when a later refresh fails.
  - show a warning-style dashboard message for stale content and initial-load refresh failures.
  - disable dashboard filter controls while a refresh failure is visible.
  - surface Settings guidance when short polling intervals may increase GitHub API rate-limit failures.
  - avoid starting a new background polling refresh when the previous refresh is still in flight.
- deliverables:
  - dashboard model refresh-failure handling
  - menu-bar stale-data warning banner
  - polling interval guidance in Settings
  - focused tests and verification notes
- verification:
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T35 -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/SettingsModelTests` succeeded after adding stale-content refresh-failure coverage, polling overlap coverage, and polling interval advisory coverage.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T35b -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/SettingsModelTests` succeeded after extending initial-load failures to use warning styling and disable filters.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after the menu-bar warning banner and settings advisory changes.
- notes:
  - Initial-load failures cannot show a preserved PR list because no prior content exists in memory yet, but they now use the same warning visual treatment and disable filters.
  - Rate-limit-style failures also stop the current dashboard polling task so the app does not keep retrying while GitHub is already rejecting requests.

### T36: Settings GitHub Request Quota View
- status: `done`
- owner: `codex-main`
- depends_on: `T15`, `T18`, `T35`
- goal: make GitHub request usage visible from Settings so users can understand how app traffic maps to GitHub quota.
- scope:
  - record app-originated GitHub HTTP requests at the core API client boundary.
  - capture GitHub `x-ratelimit-*` response headers when present.
  - expose an in-memory current-run request log and latest quota snapshot to the app target.
  - add a Settings pane for latest quota and recent requests.
  - keep tokens, request bodies, and other credentials out of the log.
- deliverables:
  - core request metrics types and recording hook
  - app request log model
  - Settings request/quota view
  - focused tests and verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding core request metrics types, response-header parsing, and API-client recording coverage.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the app request log model and Settings requests pane.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T36 -only-testing:GHOrchestratorTests/AppControllerTests -only-testing:GHOrchestratorTests/GitHubRequestLogModelTests -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after wiring the request log into the launched app.
- notes:
  - This view is intentionally current-run only and does not persist request history because the fixed persistence decision still says no disk cache.
  - The request log records sanitized method/endpoint/status metadata plus quota headers, never request bodies or tokens.

### T37: Settings Quota Resource Buckets
- status: `done`
- owner: `codex-main`
- depends_on: `T36`
- goal: show GitHub quota resources side by side so GraphQL and REST/core limits do not overwrite each other in Settings.
- scope:
  - derive the latest quota header snapshot per `x-ratelimit-resource`.
  - update the Settings requests pane to show all observed quota resources.
  - clarify that GraphQL and REST/core are separate GitHub quota buckets.
  - add focused request-log tests for multi-resource quota snapshots.
- deliverables:
  - request log resource-bucket summary
  - Settings quota UI update
  - focused tests and verification notes
- verification:
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T37 -only-testing:GHOrchestratorTests/GitHubRequestLogModelTests -only-testing:GHOrchestratorTests/SettingsModelTests` succeeded after adding multi-resource quota aggregation and Settings UI coverage through compilation.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after updating the Settings requests pane to show all quota resources.
- notes:
  - GitHub documents separate rate-limit resources for REST and GraphQL; the app should not collapse them into one global remaining value.

### T38: GraphQL Dashboard Query Cost Reduction
- status: `done`
- owner: `codex-main`
- depends_on: `T16`, `T36`, `T37`
- goal: reduce per-refresh GraphQL point consumption while preserving the dashboard's primary PR, review, and checks signals.
- scope:
  - lower high-cardinality GraphQL connection limits used by the menu-bar dashboard query.
  - keep enough PR, review-thread, comment, and check context for the compact menu-bar UI.
  - add focused tests that lock the reduced query limits.
  - document the tradeoff that very large repositories may need pagination or lazy detail loading later.
- deliverables:
  - reduced-cost GraphQL query limits
  - focused query-shape tests
  - verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after reducing GraphQL dashboard query limits and adding bounded-query coverage.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and relaunching the app with the lower-cost query.
- notes:
  - The previous query requested up to 100 PRs, 100 review threads per PR, 20 comments per thread, and 100 check contexts per PR per repository. That can multiply into hundreds of GraphQL points for one refresh.
  - Initially reduced to 25 PRs, 20 review threads per PR, 3 comments per thread, and 50 check contexts per PR; `T39` supersedes the fixed values with persisted configurable limits.

### T39: Configurable GraphQL Dashboard Limits
- status: `done`
- owner: `codex-main`
- depends_on: `T38`
- goal: let users tune dashboard GraphQL limits from Settings with conservative defaults.
- scope:
  - add persisted settings for PR search results, review threads, review comments per thread, and check contexts per PR.
  - default those limits to 10 PRs, 10 review threads, 5 comments per thread, and 15 check contexts per PR.
  - clamp user-entered limits to documented GitHub GraphQL connection bounds.
  - pass the configured limits from the app settings into the snapshot GraphQL query builder.
  - expose the controls in Settings near the polling/rate-limit guidance.
- deliverables:
  - persisted limit settings
  - query builder limit injection
  - Settings controls and tests
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding persisted GraphQL dashboard limits, backward-compatible decoding, and custom query-limit coverage.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T39 -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/SettingsStoreTests -only-testing:GHOrchestratorTests/AppControllerTests` succeeded after adding Settings model persistence coverage for the new limits.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after adding the Settings query-limit controls and relaunching the app.
- notes:
  - Raising these limits increases GraphQL cost; the Settings UI should make that tradeoff clear.
  - Defaults are 10 PRs, 10 review threads per PR, 5 comments per thread, and 15 check contexts per PR.

### T40: Menu-Bar Overflow Actions
- status: `done`
- owner: `codex-main`
- depends_on: `T09`, `T12`
- goal: consolidate menu-bar popup actions behind one overflow menu and remove duplicate General settings actions.
- scope:
  - replace the separate menu-bar popup refresh and settings buttons with an ellipsis/more menu.
  - include Refresh, Settings, and Quit in the overflow menu.
  - remove the Actions section from Settings > General.
- deliverables:
  - updated menu-bar popup header actions
  - updated General settings pane
  - focused verification notes
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after replacing the menu-bar popup action buttons with an overflow menu.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T40 -only-testing:GHOrchestratorTests/AppControllerTests -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app.
- notes:
  - Requested during UI review on 2026-04-15.
  - Refresh, Settings, and Quit now live in the menu-bar popup overflow menu; Settings > General no longer shows a separate Actions section.

### T41: Actions Duration Display
- status: `done`
- owner: `codex-main`
- depends_on: `T09`, `T27`
- goal: show how long GitHub Actions workflows and jobs have been queued, running, or completed in the menu-bar dashboard.
- scope:
  - derive elapsed durations from existing GitHub Actions timestamps without adding extra GitHub requests.
  - show compact duration metadata for expanded workflow and job rows.
  - keep timestamp parsing and duration derivation out of SwiftUI views where possible.
- deliverables:
  - Actions duration model/formatting support
  - menu-bar workflow/job duration labels
  - focused tests and verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after mapping Actions job `created_at` and step timestamps.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the app-side Actions duration formatter.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T41 -only-testing:GHOrchestratorTests/ActionsDurationLabelFormatterTests -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app.
- notes:
  - Requested during UI review on 2026-04-15.
  - Expanded Actions workflow and job rows now show compact elapsed labels such as `queued for 5m`, `running for 2m`, and `completed in 2m`; labels refresh on a one-minute UI timeline while the menu is visible without issuing additional GitHub requests.

### T42: Start At Login
- status: `done`
- owner: `codex-main`
- depends_on: `T12`
- goal: let users launch GHOrchestrator automatically when they sign in to macOS.
- scope:
  - add a persisted start-at-login preference to app settings.
  - manage the main app login item from the app target using Apple ServiceManagement APIs.
  - expose a General settings toggle with user-visible registration status and approval guidance.
  - add focused persistence and app-controller tests.
- deliverables:
  - persisted start-at-login preference
  - app-target login item controller seam
  - Settings toggle and status messaging
  - verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the backward-compatible `startAtLogin` setting.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the app-target login item controller and Settings UI.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-start-login -only-testing:GHOrchestratorTests/AppControllerTests -only-testing:GHOrchestratorTests/SettingsModelTests -only-testing:GHOrchestratorTests/SettingsStoreTests` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with the start-at-login feature wired in.
- notes:
  - Use `SMAppService.mainApp`; do not add a helper app or third-party login item dependency.
  - Settings now surfaces ServiceManagement registration status, including the macOS approval-required state with a button that opens Login Items settings.
  - Launch-time reconciliation registers the app when the persisted preference is on; disabling is applied immediately when the user turns the setting off.

### T43: App Icon Refresh
- status: `done`
- owner: `codex-main`
- depends_on: `T29`
- goal: replace the current app icon with the newly provided GHOrchestrator branding asset.
- scope:
  - generate the macOS `AppIcon.appiconset` PNG sizes from the provided source image.
  - keep the existing app target resource wiring intact.
  - verify the updated asset catalog builds.
- deliverables:
  - refreshed `AppIcon.appiconset` PNGs
  - verification notes
- verification:
  - 2026-04-15: `python3 -m json.tool App/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` succeeded after restoring the standard macOS icon filename matrix.
  - 2026-04-15: `tuist generate --no-open` succeeded after regenerating the icon PNG sizes from the provided source image.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded, including asset catalog compilation to `AppIcon.icns` and app launch.
- notes:
  - Source image: `/Users/ipavlidakis/Downloads/ghorchestrator-icon Exports 2/ghorchestrator-icon-watchOS-Default-1088x1088@1x.png`.
  - Regenerated the standard macOS `AppIcon.appiconset` sizes from 16px through 1024px.

### T44: Menu Bar Monochrome Icon Refresh
- status: `done`
- owner: `codex-main`
- depends_on: `T43`
- goal: update the menu-bar status item icon to match the refreshed app icon using monochrome light/dark assets.
- scope:
  - verify macOS app icon appearance variants are not usable for the compiled app icon.
  - add a monochrome menu-bar icon asset from the provided black-and-white exports.
  - wire the `MenuBarExtra` label to use the monochrome asset.
  - verify the app builds and launches.
- deliverables:
  - menu-bar monochrome icon asset
  - menu-bar label wiring
  - verification notes
- verification:
  - 2026-04-15: scratch `xcrun actool` compilation of a macOS `AppIcon.appiconset` with dark appearance children warned that the dark entries were unassigned, confirming the compiled macOS app icon should remain single-variant.
  - 2026-04-15: `python3 -m json.tool App/Resources/Assets.xcassets/MenuBarIcon.imageset/Contents.json` succeeded after adding light/dark monochrome image variants.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the menu-bar image set and SwiftUI label wiring.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded, including asset catalog compilation and app launch.
- notes:
  - Xcode `actool` accepted a scratch macOS app-icon catalog with dark appearances but warned those entries were unassigned, so the app icon stays single-variant for macOS.
  - `MenuBarIcon.imageset` uses the `ClearLight` export for the default appearance and the `ClearDark` export for dark appearance at 18pt and 2x.

### T45: Invert Menu Bar Icon
- status: `done`
- owner: `codex-main`
- depends_on: `T44`
- goal: invert the monochrome menu-bar icon so it reads correctly against the menu bar background.
- scope:
  - regenerate the menu-bar image-set PNGs with inverted RGB channels.
  - keep the existing `MenuBarExtra` asset wiring intact.
  - verify the asset catalog builds and the app launches.
- deliverables:
  - inverted menu-bar PNGs
  - verification notes
- verification:
  - 2026-04-15: `python3 -m json.tool App/Resources/Assets.xcassets/MenuBarIcon.imageset/Contents.json` succeeded after regenerating the inverted menu-bar PNGs.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded, including asset catalog compilation and app launch.
- notes:
  - Requested after visual review of the menu-bar status item on 2026-04-15.
  - Regenerated all four `MenuBarIcon.imageset` PNGs with RGB inversion while preserving alpha.

### T46: Unified macOS Icon Redesign
- status: `blocked`
- owner: `codex-main`
- depends_on: `T43`, `T44`
- goal: replace the exported icon crops with a purpose-built macOS icon system that works for Dock, Finder, and menu-bar use.
- scope:
  - create original vector source artwork for the full-color app icon.
  - create original vector source artwork for a transparent monochrome menu-bar glyph.
  - regenerate the macOS `AppIcon.appiconset` PNG matrix from the new app icon artwork.
  - regenerate `MenuBarIcon.imageset` from the menu-bar glyph and make it template-rendered.
  - verify asset catalog compilation and app launch.
- deliverables:
  - icon source artwork
  - regenerated app icon PNGs
  - regenerated template menu-bar PNGs
  - verification notes
- verification:
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after removing the rejected scratch icon assets and restoring the native menu-bar symbol.
  - 2026-04-15: Image API generation was attempted with `gpt-image-1.5`, but the API returned `billing_hard_limit_reached` before any image was produced.
- notes:
  - Requested after visual review showed full-square menu-bar icon crops were not legible at status-item size.
  - Blocked on 2026-04-15 because `OPENAI_API_KEY` is not set, so the live Image API generator cannot run. The attempted local vector direction was abandoned after visual review and removed from the working tree.
  - Current fallback keeps the refreshed app icon and restores the menu-bar item to the native `arrow.triangle.branch` SF Symbol until a stronger generated/designed source is available.
  - Reopened after `OPENAI_API_KEY` was added to `~/.zshrc` and a throwaway image-generation virtualenv was prepared under `/tmp/ghorchestrator-imagegen-venv`.
  - Blocked again on 2026-04-15 because the OpenAI account has reached its billing hard limit.

### T47: Direct DMG Software Updates
- status: `done`
- owner: `codex-main`
- depends_on: `T26`, `T30`
- goal: let GHOrchestrator check GitHub Releases for newer signed DMG builds, surface available updates in Settings, and install downloaded updates without adding third-party updater dependencies.
- scope:
  - add a core release-update checker that reads the latest GitHub Release over direct HTTP, compares release versions, and selects the DMG plus checksum assets.
  - add app-owned update state, Settings controls, an app-menu check action, and automatic background checks.
  - add an app-owned DMG installer that downloads assets, validates the SHA-256 checksum, mounts the DMG, and hands replacement/relaunch to a short helper script after GHOrchestrator exits.
  - persist an automatic update-check preference in `AppSettings`.
- deliverables:
  - core update-check service and tests
  - app update model/installer and Settings/menu wiring
  - verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the release-update checker, version comparison, checksum-asset enforcement, and update preference persistence.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding app update files and switching the generated app Info.plist to a SwiftUI-compatible explicit dictionary.
  - 2026-04-15: `xcodebuild build-for-testing -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T47-build-for-testing` succeeded.
  - 2026-04-15: `xcodebuild test-without-building -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T47-build-for-testing -only-testing:GHOrchestratorTests/SoftwareUpdateModelTests -only-testing:GHOrchestratorTests/SettingsModelTests/testAutomaticUpdateCheckPreferencePersists -only-testing:GHOrchestratorTests/SettingsWindowCommandsTests` succeeded.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T47-full` succeeded after final installer-script hardening.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after final installer-script hardening, rebuilding, and launching the app with updater wiring.
- notes:
  - Keep this direct-distribution updater scoped to the existing signed/notarized DMG release pipeline. Do not add Sparkle or another third-party dependency.
  - The app target now uses an explicit Info.plist dictionary without `NSMainStoryboardFile`; the previous generated default pointed at a missing `Main.storyboard` and prevented hosted XCTest/app launch.

### T48: Visible Menu Dashboard Polling
- status: `done`
- owner: `codex-main`
- depends_on: `T08`, `T35`
- goal: keep automatic dashboard refreshes running on the configured interval while the menu-bar window is visible.
- scope:
  - remove menu visibility as a dashboard polling gate.
  - keep opening and closing the menu from forcing an immediate refresh.
  - update Settings/docs copy that describes the polling interval.
  - refresh tests that previously encoded hidden-window-only polling.
- deliverables:
  - dashboard polling lifecycle update
  - updated UI/docs copy
  - verification notes
- verification:
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T48 -only-testing:GHOrchestratorTests/MenuBarDashboardModelTests -only-testing:GHOrchestratorTests/RepositoryNotificationMonitorTests -only-testing:GHOrchestratorTests/AppControllerTests` succeeded after removing the menu-visible polling pause.
- notes:
  - Requested on 2026-04-15 to supersede the earlier hidden-window-only dashboard polling behavior.
  - Menu visibility is still tracked for dashboard state, but it no longer cancels, blocks, or restarts polling by itself.

### T49: Actions Step Duration Display
- status: `done`
- owner: `codex-main`
- depends_on: `T41`
- goal: show compact elapsed duration metadata for each expanded GitHub Actions step row.
- scope:
  - derive step durations from the existing `startedAt` and `completedAt` timestamps already mapped from GitHub Actions job steps.
  - show completed and running step durations in the expanded step metadata text without adding GitHub requests.
  - keep duration formatting in the existing app-side Actions duration formatter instead of SwiftUI view logic.
- deliverables:
  - step-duration formatter support
  - menu-bar step duration labels
  - focused tests and verification notes
- verification:
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-T49 -only-testing:GHOrchestratorTests/ActionsDurationLabelFormatterTests` succeeded after adding step-duration formatting and menu-bar step labels.
  - 2026-04-15: `tuist generate --no-open` succeeded.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with step-duration labels.
- notes:
  - Requested on 2026-04-15 as a follow-up to `T41`, which already added workflow and job duration labels.

## Suggested Parallel Pickup Order
### Historical v1 phase
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

### OAuth migration phase
- Agent 1: `PLAN.md:T13`
- Agent 2: `PLAN.md:T14` after `PLAN.md:T13`
- Agent 3: `PLAN.md:T15` after `PLAN.md:T14`
- Agent 4: `PLAN.md:T16` after `PLAN.md:T15`
- Agent 5: `PLAN.md:T17` after `PLAN.md:T14` and `PLAN.md:T15`
- Agent 6: `PLAN.md:T18` after `PLAN.md:T17`
- Agent 7: `PLAN.md:T19` after `PLAN.md:T16`, `PLAN.md:T17`, and `PLAN.md:T18`

## Cross-Task Rules
- Keep the app target thin. Process execution and payload parsing belong in the local package.
- Do not perform OAuth token exchange or GitHub HTTP calls directly from SwiftUI views.
- Do not add non-Apple dependencies.
- Favor `Codable`, value types, and explicit mappers over loosely typed dictionaries.
- Keep failures user-visible and actionable, especially around GitHub login, missing OAuth configuration, and API or auth errors.

## Decision Log
- 2026-04-14: v1 scope updated from “all open PRs for the user” to “open PRs for a user-configured repository allowlist”.
- 2026-04-14: polling changed from fixed cadence to a user-configurable interval with a Settings surface.
- 2026-04-14: dedicated Settings window added to show `gh` CLI health, connected account, and app configuration.
- 2026-04-14: app settings persistence changed from `UserDefaults` to a file-backed store in Application Support (`plist` or `json`).
- 2026-04-14: automatic refresh while the menu window is visible was disabled; polling now runs only while the window is hidden, and opening the menu must not trigger a reload.
- 2026-04-14: tapping the unresolved-comments badge should expand a list of unresolved review comments showing author, file path, and comment text, with comment rows linking to the browser.
- 2026-04-14: opening the menu must preserve an already-running hidden refresh rather than cancelling it, and loading feedback belongs in the header instead of replacing list content.
- 2026-04-14: the Settings window now needs a persisted Dock icon visibility preference, a Quit action, and more native macOS settings presentation.
- 2026-04-14: authentication and transport pivoted from the local `gh` CLI to GitHub OAuth App login with PKCE, Keychain-backed token storage, and direct GitHub GraphQL and REST requests because the app must work without per-repository GitHub App installation.
- 2026-04-15: downloadable public builds must not embed a GitHub OAuth client secret; GHOrchestrator will use GitHub OAuth device flow with a client ID only, and the OAuth app must have device flow enabled in GitHub settings.
- 2026-04-15: direct distribution will use a stapled Developer ID-signed `.dmg` attached to a GitHub Release, with release uploads performed through the GitHub REST API.
- 2026-04-15: failed GitHub Actions steps in the menu-bar dashboard should expose a retry affordance that reruns the containing job when GitHub allows it; step-level rerun is not available, so permission or API failures must stay inline with the existing dashboard content.
- 2026-04-15: the menu-bar dashboard can switch between the signed-in user's PRs and all open PRs in configured repositories, can focus one configured repository, and should collapse other expanded PR detail bubbles when a new checks/comments bubble opens.
- 2026-04-15: refresh failures after successful dashboard loads should preserve the last visible content, show a warning banner for stale data, and disable dashboard filter controls until a refresh succeeds.
- 2026-04-15: local macOS notifications are configured per observed repository, evaluate all open PRs independent of dashboard filters, and use first-load baselines to avoid notifying old events.
- 2026-04-15: the persisted Dock icon preference is overridden while the Settings window is open so the window remains reachable from the Dock after it loses focus.
- 2026-04-15: menu-bar popup actions should use one ellipsis/more menu containing Refresh, Settings, and Quit; duplicate Refresh/Quit actions should be removed from Settings > General.
- 2026-04-15: start-at-login is an app-owned preference backed by `SMAppService.mainApp`, with the desired state persisted in `AppSettings` and system registration status surfaced in Settings.
- 2026-04-15: software updates will use the existing GitHub Release DMG artifacts directly: core code checks release metadata and checksum assets, while the app target owns automatic checks, downloads, DMG mounting, replacement, and relaunch.
- 2026-04-15: dashboard polling should continue at the configured interval while the menu-bar window is visible; opening or closing the menu should not itself force a refresh.
- 2026-04-15: the Actions insights Settings dashboard will fetch selected-period GitHub Actions data live, aggregate it in memory, persist only selection preferences in the existing Application Support settings file, and avoid adding a metrics database or disk cache for the first implementation.
