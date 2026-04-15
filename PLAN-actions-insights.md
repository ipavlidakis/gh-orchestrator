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
