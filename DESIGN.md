# GH Orchestrator Design Guide

Rules and reference values for building UI in `GHOrchestrator`. Read this before adding or changing any SwiftUI view, icon, or window chrome. The visual source of truth is the design canvas (https://claude.ai/artifact/HBdoTyLTNmop4hromVFdAC); this file is the implementation contract that mirrors it.

## Principles
- **Native first.** Swift, SwiftUI, and AppKit only; no third-party UI libraries (see `AGENTS.md`). Use system controls (`Menu`, `Toggle`, `Picker`, `Button`, `ProgressView`, SF Symbols) and system colors. Custom drawing is limited to the pieces listed below.
- **macOS 15+.** Anything that needs macOS 26 (glass button style) goes behind `#available(macOS 26, *)` with a working fallback.
- **Calm by default.** One row of controls, quiet icon buttons, color only for status. Do not add banners, badges, or chrome that carry no information.
- **Status is never color alone.** Pair color with an SF Symbol and a text label (for example `checkmark` + "Ready").
- **UI stays in the app target.** Views, view state, settings binding, window chrome, and URL opening live in `App/Sources`. GitHub transport, models, sorting, and persistence live in `Packages/GHOrchestratorCore`. A view never performs a network call.

## Tokens

### Color
Use semantic system colors so light and dark work for free.

| Use | Value |
| --- | --- |
| Accent (selected segment, sidebar selection, links, active icon) | `Color.accentColor` (asset `AccentColor`, `#3B2F88`) |
| Primary / secondary text | `.primary` / `.secondary` |
| Card surface | `Color(nsColor: .textBackgroundColor)` |
| Sidebar rail | `Color.primary.opacity(0.05)` |
| Settings card fill / border | `Color.primary.opacity(0.04)` / `Color.primary.opacity(0.10)` at 0.5 pt |
| Pill / track fill | `Color.primary.opacity(0.08)` |

Status colors come from `StatusTint` in `MenuBarPlaceholderView.swift`. Use it, do not inline hex values.

| Tint | Light text | Dark text | Meaning |
| --- | --- | --- | --- |
| `.success` | `#1A7F37` | `#56D364` | passing, ready, approved |
| `.warning` | `#8A4A00` | `#F0A050` | pending, review required |
| `.danger` | `#B4202B` | `#FF7B72` | failing, changes requested |
| `.neutral` | `#5C5C63` | `#A0A0A8` | draft, skipped, none |

Chip background is the tint at 14% opacity. Status dots and progress segments use `.green`, `.orange`, `.red`, `.secondary`. A completed run with no conclusion is neutral, never red.

### Type
System font only (`.system(size:weight:)`). Sizes in points:

| Role | Size / weight |
| --- | --- |
| Page title (Settings) | 15 semibold |
| PR title | 14 semibold (link) |
| Row title, repo header | 13 / 12 semibold |
| Body, chips, segment labels | 12.5 / 11.5 medium |
| Secondary text, metadata, subtitles | 11.5 regular, `.secondary` |
| Section label | 12 semibold, uppercase, `.secondary` |

### Shape and spacing
- Corner radius: card 12, settings card 10, header icon button 8, segmented track 9 / segment 7, chip 6, pill = capsule.
- Card: 14 horizontal / 12 vertical padding, 0.5 pt `Color.primary.opacity(0.1)` border, shadow `black 6%`, radius 1, y 1. Gap between cards 8 to 12.
- Settings row: 14 horizontal / 9 vertical, hairline `Divider()` between rows.
- Hit targets for icon buttons: 28 x 28 minimum.

### Icons
SF Symbols only inside the UI. Used today: `line.3.horizontal.decrease` (filter), `arrow.up.arrow.down` (sort), `ellipsis.circle` (more), `bolt.fill` (workflow), `checkmark`, `xmark.circle`, `clock`, `chevron.right/down`. Never use emoji.

## Popover (menu bar dashboard)
Owner: `MenuBarPlaceholderView.swift` and `MenuBar/MenuBarPopoverPresenter.swift`.

- **Size.** Width 440. Height fits content up to a 620 maximum (`MenuBarPopoverConfiguration.dashboard`). The list shrinks to its content and scrolls only at the maximum. The SwiftUI view reports its natural height through `onPreferredHeightChange`; the presenter resizes `NSPopover` with `animates = false` for that change, because animated resizing relays out the whole list every frame.
- **Structure, top to bottom.**
  1. Header row (padding 14 / 14 top / 10 bottom): app mark (`AppMarkView`, 26), `ScopeSegmentedControl` (My PRs / All PRs, count on the selected scope only), spacer, optional refresh `ProgressView`, then three 28 pt icon menus: repository filter, Sort, More. The filter icon turns accent-tinted when a repository is selected and a "Filtered to X · Clear" line appears under the row.
  2. `Divider`, then the list (12 horizontal padding, 12 top).
  3. Footer bar (39 pt): "Updated 12s ago · 3 open · 1 failing · 1 ready" on the left, "N calls left" (GraphQL quota) on the right, 11.5 pt secondary.
- **Menus.** Sort holds two inline pickers under section headers (Pull requests, Repositories). More holds Refresh, Update (only when an update is available), Settings, Quit. Menus use `.menuStyle(.borderlessButton)` with `headerMenuStyle()` and carry an `accessibilityLabel`. Sort must keep the label "Sort"; a test checks it.
- **Repository section.** One full-width button row: chevron, repo name (12 semibold), count pill. Tapping anywhere on the row collapses or expands its PRs.
- **PR card.** Title link, metadata ("#1335 · opened by you · Updated 11 min ago"; "by @login" on All PRs), Ready or Draft chip plus a review chip, then the checks summary (status line, "x of y done", progress bar) which is always visible. A collapsed card expands on a click anywhere; an expanded card collapses from its header area (everything above the details). Details are workflow rows (bolt, name, status text, dot) with nested job rows (dot, name, duration, optional steps with Retry). Clicks inside the details never collapse the card. Cards with no workflow data do not toggle.
- **Retry.** Retry job is enabled only when the whole workflow run is `completed`; otherwise it is disabled with an explanatory help string.
- **Empty and error states** use `StateMessageView` and `RefreshWarningBanner`: a title (semibold) and one or two actionable sentences.

### Reusable popover components
`AppMarkView`, `StatusChip` (+ `StatusTint`), `ChecksProgressBar`, `ScopeSegmentedControl`, `DashboardFooterBar`, `ActionsStatusText` (compact status wording such as "passed in 32s", "queued 28m"). Reuse them; extend rather than duplicate.

## Menu bar glyph
Owner: `MenuBarPopoverPresenter.swift` and the `MenuBarIcon` asset.
- Monochrome template image of three commit nodes joined by a trunk and a merge branch.
- `MenuBarGlyphStatus` adds an orange (pending) or red (failing) badge, swapping to a pre-tinted image chosen from the button's current appearance. The attention count (`MenuBarDashboardModel.attentionCount`: failing checks or requested changes) sits right of the glyph and is hidden at zero.
- Badges must not be the only signal: the count and the accessibility value ("Checks pending", "Checks failing") carry it too.

## Settings window
Owner: `SettingsPlaceholderView.swift` and `Settings/`.
- **Window.** Fixed 820 x 620 content. The title bar is transparent and folded into the content (`SettingsWindowChromeConfigurator`), so the traffic lights sit on the sidebar. The configurator re-asserts its settings on key, update, and resize because SwiftUI resets them.
- **Layout.** `SettingsSidebar` (196 wide, 52 top padding to clear the traffic lights, accent-filled selected row, app mark at the bottom). On macOS 26 it floats as a Liquid Glass panel (`glassEffect(.regular, in:)`, 22 pt radius, 8 pt inset) over the system window background; earlier systems get a flat tinted rail. Do not paint opaque fills behind it, and keep the window background at `windowBackgroundColor` plus `SettingsDetailPage` (centered 15 pt title, scrolling content, 28 horizontal padding, 20 between groups).
- **Building a pane.** Use only the shared primitives, never a raw `Form` or `Section`:
  - `SettingsGroup(title:)`: uppercase label, rounded card, automatic dividers between children, optional footer.
  - `SettingsRow(title:subtitle:subtitleColor:)`: title left, control right. The control is fixed-size and trailing.
  - `SettingsTextBlock(title:bodyText:)`: padded explanatory text inside a card.
- **Controls.** Master switches use `.toggleStyle(.switch)`; sub-options use checkboxes. Numeric fields pair a text field with a `Stepper`. Icon-only buttons in a card use equal fixed frames (for example 22 x 16 for add and remove).
- **Notifications** use one `SettingsGroup` per repository, led by "Watch this repository", with indented trigger rows below it, disabled when the master switch is off.
- Section copy is short and states the effect ("Off keeps GHOrchestrator in the menu bar only").

## App and Dock icons
Generated, not hand-edited. Edit `script/generate_icon_assets.swift` and run it from the repo root:

```bash
swiftc script/generate_icon_assets.swift -o /tmp/genicon && /tmp/genicon
```

- It writes `AppIcon.appiconset` PNGs, `DockIconLight` and `DockIconDark` PDFs, and the `MenuBarIcon` PDF, plus a preview PNG in the temp directory. Open the preview and check light and dark before committing.
- Design: indigo squircle gradient with a white three-node branch graph, a green check dot, and an orange dot. The menu bar glyph is the same graph as a black template.
- **Do not use alpha gradients in drawing code.** PDF output turns them opaque white. Build highlights from opaque color stops.
- `ghorchestrator-icon.icon` (Icon Composer source) mirrors the artwork with `branch-graph.svg`; keep it in sync when the mark changes. It is not referenced by the build.

## Accessibility
- Every icon-only control has `accessibilityLabel` and `.help`.
- Selected segments and sidebar rows add `.isSelected`; collapsible rows expose "Collapsed" or "Expanded" through `accessibilityValue`.
- Text contrast follows `StatusTint`; do not put secondary text on tinted fills without checking both appearances.
- Respect Reduce Transparency and Dynamic appearance by using system materials and semantic colors.

## Verifying UI changes
1. `tuist generate --no-open` after adding or removing files.
2. `xcodebuild test -workspace GHOrchestrator.xcworkspace -scheme GHOrchestrator -destination 'platform=macOS,arch=arm64'`.
3. `Tests/GHOrchestratorTests/MenuBar/DesignParityRenderingTests.swift` renders the popover, the Settings window, and individual panes with fixture data to `/tmp/gho-shots/*.png`. Open the PNGs and compare them with the canvas. Add fixtures there when you add a component.
4. `./script/build_and_run.sh --verify` to build and launch.
5. Checks that guard behavior: `DashboardRenderingTests` (neutral skipped jobs, "Sort" present), `SettingsRenderingTests` (labels, alignment), `PopoverPerformanceTests` (repository toggle stays under 250 ms).

## Do and do not
- Do reuse `StatusChip`, `SettingsGroup`, `SettingsRow`, and the header icon helper instead of styling new ones.
- Do keep new sizes on the 4 pt grid and match the radii above.
- Do record visual decisions in the `Decision Log` of the relevant `PLAN-*.md` before changing them.
- Do not hardcode colors, add third-party packages, or call GitHub from a view.
- Do not make a status readable by color alone.
- Do not animate popover resizing or add per-frame work to list rows.
