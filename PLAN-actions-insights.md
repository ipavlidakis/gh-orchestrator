# Actions Insights Dashboard Plan

## Purpose
- Add a Settings dashboard for GitHub Actions workflow health and duration trends.
- Let the user choose a configured repository, workflow, job, and time period.
- Show success/failure rate, duration charts, average duration, and success rate.

## Decisions
- Fetch Actions data live from GitHub for the selected period.
- Aggregate fetched runs and jobs in memory.
- Persist only dashboard selection preferences in the existing Application Support `settings.json`.
- Do not add a database, disk metrics cache, or third-party charting dependency.
- 2026-10-01: live fetching proved slow (sequential per-run job requests, sequential run pages). Decision: fetch concurrently (bounded to 8 in flight) and keep an in-memory-only cache of completed-run job lists keyed by `(repo, run id, updated_at)`; no disk cache.
- Default the time period to the previous calendar month.
- Keep GitHub REST request construction, decoding, and aggregation in `GHOrchestratorCore`; keep SwiftUI views in the app target.

## Task Board

### A01: Settings Actions Insights Dashboard
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN.md:T15`, `PLAN.md:T24`
- goal: implement the first usable Actions insights dashboard in Settings.
- scope:
  - add persisted dashboard selection values for repository, workflow, job, and period.
  - add core Actions insights models, service, and aggregation helpers using direct GitHub REST APIs.
  - add Settings model state for loading workflows/jobs and loading dashboard metrics.
  - add a Settings pane with repository, workflow, job, and period controls.
  - render success/failure and duration trends with Swift Charts.
  - show summary metrics for run count, success rate, failure count, and average duration.
  - add focused package and app tests.
- deliverables:
  - core Actions insights service and tests
  - settings persistence and model tests
  - Settings dashboard UI
  - verification notes
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the Actions insights period model, REST service, aggregation, and package tests.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the Settings insights pane source file.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-actions-insights-full` succeeded after wiring app settings state and UI.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with the new Settings Insights pane.
- notes:
  - The first implementation should favor clear live results over background caching. Add a cache only after measuring slow real repositories and recording that decision.
  - The first dashboard computes workflow-level duration from `run_started_at` to `updated_at`; selected job duration uses each job’s `started_at` and `completed_at`.

### A02: Faster dashboard refresh and insights loading
- status: `done`
- owner: `claude`
- depends_on: `A01`
- goal: cut wall-clock time of popover refresh and Actions insights.
- scope:
  - `BoundedConcurrency.map` helper (order-preserving, 8 in flight).
  - Insights: load run pages 2…N concurrently once page 1 reports `total_count`; fetch per-run jobs concurrently; cache completed-run jobs in memory.
  - Popover refresh: fetch workflow-run jobs once per run across all PRs concurrently (was sequential per PR); cache completed-run jobs keyed by `(run id, check run completedAt)` so re-runs invalidate; add `completedAt` to the GraphQL CheckRun selection.
- verification:
  - 2026-10-01: `swift test --package-path Packages/GHOrchestratorCore` (96 tests) and `xcodebuild test` for the app scheme succeeded.
  - 2026-10-01: job insights now batch runs through GraphQL `nodes(ids:)` (50 runs/request, WorkflowRun `node_id` from the REST runs list; check runs map 1:1 to Actions jobs), REST per-run fallback when `node_id` is missing. Measured on GetStream/stream-video-swift Smoke Checks, 90 days: 518 runs = 518 REST job calls (~0.9 s each) vs ~11 GraphQL calls (~2 s each, cost 1 point each).
- notes:
  - Compare end-to-end time in the app before and after on a large repo.

### A03: Progressive Insights filters with auto-load
- status: `done`
- owner: `claude`
- depends_on: `A02`
- goal: reveal filters step by step and load the dashboard without a Refresh button.
- scope:
  - Repository always shown (defaults to the first observed repo); Workflow shown once a repo exists (defaults to the first workflow, else none); Job shown once a workflow is selected (defaults to the first job, else none; "All jobs" stays an explicit choice stored as `includesAllJobs`); Period shown once a job choice resolves.
  - Remove the Actions/Refresh row. Summary and Trends load when every filter resolves and reload on any change; in-flight loads are cancelled and stale results dropped.
  - Workflow/job list completions drive the cascade only while the Insights pane is visible.
- verification:
  - 2026-10-01: `xcodebuild test` for the app scheme succeeded; added `testInsightsFiltersPreselectFirstWorkflowAndJobAndLoadOnceComplete` and `testChangingJobOrPeriodReloadsInsightsWithoutManualRefresh`.
- notes:
  - `PullRequestSnapshotServiceTests.testFetchRepositorySnapshotsThrowsWhenAllRepositoriesFail` is flaky (order-based stub vs concurrent per-repo fetches); pre-existing, not addressed here.
