# GH Orchestrator Notifications Plan

## Purpose
- Track implementation of local macOS notification triggers for configured repositories.
- Keep notification event detection in the core package and system notification delivery in the app target.
- Follow the repo-wide rules in `PLAN.md` and `AGENTS.md`.

## Task Board

### N01: Per-Repository Notification Triggers
- status: `done`
- owner: `codex-main`
- depends_on: `PLAN.md:T16`, `PLAN.md:T18`, `PLAN.md:T33`, `PLAN.md:T39`
- goal: notify users about selected PR and workflow events for configured repositories.
- scope:
  - add backward-compatible persisted per-repository notification settings.
  - add pure core event-baseline and diff evaluation for review approval, changes requested, new unresolved review comments, and PR-attached workflow-run completion.
  - add app-owned local macOS notification permission, delivery, click routing, and polling monitor.
  - add Settings controls for notification permission, per-repository enablement, trigger toggles, and workflow-name filters.
  - evaluate all open PRs in enabled repositories independent of dashboard filters.
- deliverables:
  - core notification settings and evaluator types
  - app notification monitor and UserNotifications delivery adapter
  - Settings notifications pane
  - focused core and app tests
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding notification settings normalization, backward-compatible settings decoding coverage, and pure event-diffing tests.
  - 2026-04-15: `tuist generate --no-open` succeeded after adding the app notification monitor, delivery adapter, and Settings pane.
  - 2026-04-15: `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-notifications` succeeded with core settings/evaluator tests plus app Settings model, monitor, and notification click-routing coverage.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with the notification feature wired in.
- notes:
  - First successful notification poll establishes baseline and does not notify existing data.
  - v1 workflow completion scope is PR-attached GitHub Actions workflow runs surfaced through PR check rollups.
  - Manual inspection of the real macOS notification permission prompt was not exercised in this session; permission state, event delivery gating, and click URL routing are covered with injected app tests.

### N02: Workflow Filter Picker
- status: `done`
- owner: `codex-main`
- depends_on: `N01`
- goal: replace free-form workflow-name filter entry with repository workflow lists fetched from GitHub.
- scope:
  - add a core REST service for listing GitHub Actions workflows in an observed repository.
  - expose workflow names to the Settings model through an injected app seam.
  - render workflow filters as selectable rows per repository instead of a text field.
  - retain empty selection as “all workflows” and keep selected names persisted in existing notification settings.
- deliverables:
  - workflow-listing core service and tests
  - Settings model load/select behavior
  - Settings notifications pane checklist UI
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the Actions workflow list service, fixture, and error formatting coverage.
  - 2026-04-15: `tuist generate --no-open` succeeded after wiring the Settings workflow picker UI.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-workflow-picker` succeeded after adding Settings model workflow loading and selection tests.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with workflow picker support.
- notes:
  - GitHub workflow names come from the repository Actions workflow list endpoint, not from the current PR check rollup.
  - Empty workflow selection still means all PR-attached workflow completions match.

### N03: Workflow Job Completion Notifications
- status: `done`
- owner: `codex-main`
- depends_on: `N01`, `N02`
- goal: notify users when jobs inside PR-attached GitHub Actions workflow runs complete.
- scope:
  - add a separate repository notification trigger for workflow job completion.
  - extend notification baselines to track Actions job status and conclusion by workflow run.
  - emit job completion events when a job transitions to completed or first appears completed on an already observed PR.
  - reuse repository workflow-name filters to scope job completion notifications to selected workflows.
  - update Settings trigger labels and notification delivery copy.
- deliverables:
  - core trigger/event/baseline support for job completions
  - Settings trigger row for workflow job completion
  - focused evaluator tests
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the `workflowJobCompleted` trigger, job baseline state, job event payload fields, and focused evaluator coverage.
  - 2026-04-15: `tuist generate --no-open` succeeded after updating Settings trigger labels and notification delivery copy.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-job-notifications` succeeded after the new trigger case was wired through app switches.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with workflow job notification support.
- notes:
  - This does not add separate job-name filters; job notifications are scoped by the selected workflow names.

### N04: Workflow Job Filter Picker
- status: `done`
- owner: `codex-main`
- depends_on: `N03`
- goal: let users choose specific job names inside each workflow for job-completion notifications.
- scope:
  - add persisted per-workflow job-name filters under repository notification settings.
  - add a core service that derives selectable job names from recent workflow runs.
  - update notification evaluation to apply job-name filters for workflow job completion events.
  - add Settings UI for selecting all jobs or specific jobs per workflow.
- deliverables:
  - workflow-job listing core service and tests
  - per-workflow job filter persistence and evaluator filtering
  - Settings job filter picker
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding workflow-run/job REST fixtures, job-list service tests, settings normalization coverage, and evaluator job-filter coverage.
  - 2026-04-15: `tuist generate --no-open` succeeded after wiring the Settings job filter picker.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-job-filter-picker` succeeded after adding Settings model job-loading and selection coverage.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with job filter picker support.
- notes:
  - GitHub does not expose static job definitions from a workflow metadata endpoint, so selectable job names are derived from recent runs of each workflow.
  - Empty job selection means all jobs match for that workflow.

### N05: Pull Request Created Notifications
- status: `done`
- owner: `codex-main`
- depends_on: `N01`
- goal: notify users when a new open pull request appears after notification baseline establishment.
- scope:
  - add a separate repository notification trigger for PR creation.
  - emit PR-created events for newly observed PRs only after the first successful notification baseline.
  - keep first-load behavior quiet so existing open PRs do not notify.
  - update Settings trigger labels and notification delivery copy.
- deliverables:
  - core trigger/evaluator support for PR-created events
  - Settings trigger row for PR created
  - focused evaluator tests
- verification:
  - 2026-04-15: `swift test --package-path Packages/GHOrchestratorCore` succeeded after adding the `pullRequestCreated` trigger and evaluator coverage for newly observed PRs after baseline.
  - 2026-04-15: `tuist generate --no-open` succeeded after wiring Settings labels and notification delivery copy.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-pr-created` succeeded after the new trigger case was wired through app switches.
  - 2026-04-15: `./script/build_and_run.sh --verify` succeeded after rebuilding and launching the app with PR-created notification support.
- notes:
  - Detection is polling-based: “created” means a PR first appears in the monitored open-PR snapshot after baseline, not a webhook-backed GitHub creation event.

### N06: Workflow Job Notification Copy
- status: `done`
- owner: `codex-main`
- depends_on: `N03`
- goal: update workflow job completion notification copy to show the repository name first, then the job result with a success or failure icon.
- scope:
  - change app-owned local notification formatting for workflow job completion events.
  - keep notification routing and core event evaluation unchanged.
  - add focused app coverage for the formatted title and body.
- deliverables:
  - workflow job notification title/body formatting update
  - focused notification delivery formatting test
- verification:
  - 2026-04-15: `tuist generate --no-open` succeeded after adding focused notification formatting coverage.
  - 2026-04-15: `xcodebuild test -quiet -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/GHOrchestrator-DerivedData-notification-copy -only-testing:GHOrchestratorTests/LocalNotificationContentFormatterTests` succeeded after updating workflow job notification copy.
- notes:
  - Requested format is title `Repo name`, body `✅/❌ {job name} succeed/fail`.
