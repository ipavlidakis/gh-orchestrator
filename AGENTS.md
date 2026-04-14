# GH Orchestrator Repo Contract

## Purpose
- This repo builds `GHOrchestrator`, a Tuist-managed macOS 15+ menu-bar app.
- Keep the app target thin: UI, settings binding, polling lifecycle, and URL opening stay in the app; `gh` process execution, parsing, aggregation, fixtures, and tests live in the local Swift package.
- Use only Swift, Tuist, SwiftPM, Apple frameworks, and the installed `gh` CLI. Do not add third-party dependencies.

## Architecture Boundaries
- App target:
  - SwiftUI scenes, views, and observable UI state.
  - Settings UX and launch-time wiring.
  - Menu-bar presentation and user interaction.
- Local package:
  - Process runner and `gh` command wrapper.
  - CLI health checks, GraphQL/REST decoding, domain models, mappers, and fixtures.
  - Unit tests for core behavior.
- Cross-boundary rules:
  - Do not call `gh` directly from SwiftUI views.
  - Prefer value types, `Codable`, and explicit mappers over ad hoc dictionaries.
  - Keep failures visible and actionable, especially for missing or unauthenticated `gh`.

## Task Workflow
- `PLAN.md` is the shared program plan and registry for repo-wide history, cross-feature decisions, and active feature-plan pointers.
- Feature-specific work may live in dedicated `PLAN-*.md` files.
- Claim exactly one task at a time in the relevant plan file by setting its `owner` and moving `status` to `in_progress`.
- If you need to change product decisions, update the `Decision Log` in the relevant plan file first; if the change is cross-feature or repo-wide, reflect it in `PLAN.md` as well.
- When you finish a task, update the task entry in the same plan file before handing off:
  - set `status` to the finished state used by the plan,
  - add or update `verification`,
  - add any follow-on notes needed for the next agent.
- If you are blocked, mark the task accordingly and explain the blocker in that plan’s task notes instead of leaving partial work unexplained.

## Validation Expectations
- Follow the task-specific verification called out in the touched plan file.
- Baseline checks for this repo are:
  - `tuist generate`
  - `./script/build_and_run.sh --verify` once the app target exists
  - the relevant `swift test` / Xcode test commands for the touched package or target
- Treat verification as part of the task, not an optional cleanup step.

## Repo Rules
- Keep `AGENTS.md` aligned with `PLAN.md`, any active `PLAN-*.md` files, and the repo’s actual layout.
- Do not touch `PLAN.md`, any `PLAN-*.md`, or source/build/config files when you are only updating the collaboration contract.
- Keep changes small and local. Prefer one focused task per agent over broad cross-cutting edits.
- Preserve unrelated work in the tree; do not revert or overwrite changes you did not make.
