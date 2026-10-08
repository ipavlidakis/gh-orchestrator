# GH Orchestrator Design Guide

Rules and reference values for building UI in `GHOrchestrator`. Read this before adding or changing any SwiftUI view, icon, or window chrome. The visual source of truth is the design canvas (https://claude.ai/artifact/HBdoTyLTNmop4hromVFdAC); this file is the implementation contract that mirrors it.

## Principles
- **Native first.** Swift, SwiftUI, AppKit and Apple WebKit only; no third-party UI libraries (see `AGENTS.md`). Use system controls (`Menu`, `Toggle`, `Picker`, `Button`, `ProgressView`, SF Symbols) and system colors. Custom drawing is limited to the pieces listed below.
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
  1. Header row (padding 14 / 14 top / 10 bottom): square app mark and `ScopeSegmentedControl` share a 28 pt height (`ScopeSegmentedControl.height`; My PRs / All PRs, count on the selected scope only), spacer, optional refresh `ProgressView`, then three 28 pt icon menus: repository filter, Sort, More. The filter icon turns accent-tinted when a repository is selected and a "Filtered to X · Clear" line appears under the row.
  2. `Divider`, then the list (12 horizontal padding, 12 top).
  3. Footer bar (39 pt): "Updated 12s ago · 3 open · 1 failing · 1 ready" on the left, "N calls left" (GraphQL quota) on the right, 11.5 pt secondary.
- **Menus.** Sort holds two inline pickers under section headers (Pull requests, Repositories). More holds Refresh, Update (only when an update is available), Settings, Quit. Menus use `.menuStyle(.borderlessButton)` with `headerMenuStyle()` and carry an `accessibilityLabel`. Sort must keep the label "Sort"; a test checks it.
- **Saved selections.** My PRs / All PRs, the repository filter, and both sort orders share the Application Support settings file. Restore them before the first fetch and retain them when the popover closes or app activation changes. Removing the focused repository clears that filter; older settings default to My PRs and all repositories.
- **Header focus.** Use native `focusEffectDisabled()` on the header to suppress its unwanted rectangular purple focus decoration. Preserve native keyboard focus and activation, accessible control labels, and the accent-filled scope selection.
- **Logo scaling.** The mark's square background uses the scope track's shared height. Its branch symbol is resizable and uses aspect-fit sizing within a centered square at 52% of that height.
- **Repository section.** One full-width button row: chevron, repo name (12 semibold), count pill. Tapping anywhere on the row collapses or expands its PRs.
- **PR card.** Title link, metadata ("#1335 · opened by you · Updated 11 min ago"; "by @login" on All PRs), Ready or Draft chip plus a review chip, then the checks summary (status line, "x of y done", progress bar) which is always visible. A collapsed card expands on a click anywhere; an expanded card collapses from its header area (everything above the details). Details are workflow rows (bolt, name, status text, dot) with nested job rows (dot, name, duration, optional steps with Retry). Clicks inside the details never collapse the card. Cards with no workflow data do not toggle.
- **Retry.** Retry job is enabled only when the whole workflow run is `completed`; otherwise it is disabled with an explanatory help string.
- **Merge conflicts.** Keep a third StatusChip beside draft/review status: danger Conflicts, success No conflicts, or neutral Checking conflicts. Missing status is unknown. The footer counts ready PRs only when non-draft, approved, passing and confirmed conflict-free; no conflicts alone does not mean all merge requirements passed.
- **Review comments.** GitHub-style compact comments use a 28 pt circular author avatar beside an 8 pt rounded card with a 0.5 pt semantic border. Native `AsyncImage` displays the API-provided public image; initials on the pill/track fill cover missing, loading, or failed images. The card header uses the sidebar rail fill, 12 pt semibold author text and 11.5 pt secondary relative time, with 8 pt padding. File context is an 11.5 pt secondary monospace line (middle truncation, full path in help); the body is 12.5 pt primary text, wraps without a line limit, and uses 8 pt padding. The card is a plain button opening the original GitHub comment, with a visible external-link symbol and an explicit accessibility label. No decorative reaction or membership controls. GitHub API transport remains in the core package.
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
- **Window.** Initially 820 x 620, with native NavigationSplitView chrome and window controls. Hide the sidebar toggle and visual toolbar title; retain the logical page title for window accessibility. Use hidden-title-bar styling and a native unified toolbar to avoid excess space above the sidebar list. SwiftUI Settings installs the taller Preferences toolbar regardless of scene styling; the existing visibility bridge selects `.unified` when the window appears. Compact unified styling moves the controls outside the sidebar glass. On macOS 26 a standard invisible ToolbarSpacer keeps the native toolbar alive so sidebar glass continues around the window controls even with no visible toolbar items. Let macOS own title-bar sizing and appearance; do not position the controls manually.
- **Dock lifecycle.** The same native window bridge observes `NSWindow.isVisible`; Settings temporarily shows the Dock icon only while its actual window is visible. Closing or ordering out a cached Settings window restores the saved Dock preference. Losing focus while the window remains visible preserves the override.
- **Layout.** `SettingsSidebar` is a native `.sidebar` List in NavigationSplitView (196–240 pt, ideally 212 pt), always visible. macOS supplies the inset glass, concentric corners, selection and integrated window controls; no custom sidebar radius, fill or traffic-light offsets. Earlier systems and Reduce Transparency use the system's own sidebar appearance. The app mark is a bottom safe-area inset. `SettingsDetailPage` retains a logical navigation title and scrolling content with 28 pt horizontal padding, 24 pt vertical padding and 20 pt between groups. Every `SettingsGroup` card uses `settingsCardSurface()` (macOS 26 glass at 16 pt, flat fallback at 10 pt). Clip child backgrounds to the card shape before applying its surface, keeping tinted content inside the corners. Card glass respects Reduce Transparency and `\.settingsGlassDisabled`; verify glass only in foreground captures, since offscreen renders omit it.
- **Building a pane.** Use only the shared primitives, never a raw `Form` or `Section`:
  - `SettingsGroup(title:)`: uppercase label, rounded card, automatic dividers between children, optional footer.
  - `SettingsRow(title:subtitle:subtitleColor:)`: title left, control right. The control is fixed-size and trailing.
  - `SettingsTextBlock(title:bodyText:)`: padded explanatory text inside a card.
- **Controls.** Master switches use `.toggleStyle(.switch)`; sub-options use checkboxes. Numeric fields pair a text field with a `Stepper`. Icon-only buttons in a card use equal fixed frames (for example 22 x 16 for add and remove).
- **Notifications** use one `SettingsGroup` per repository, led by "Watch this repository", with indented trigger rows below it, disabled when the master switch is off.
- Section copy is short and states the effect ("Off keeps GHOrchestrator in the menu bar only").

## PR viewer
- Merge conflict details stay in the existing Merge status inspector, visible while scrolling activity. Open conflicting PRs show a danger warning icon and semibold GitHub-style heading, secondary guidance naming the base branch and a native bordered Resolve conflicts action that opens GitHub's PR conflicts page directly in the browser. Conflict-free/calculating states retain the existing status line. Closed/merged PRs show their terminal state and no resolution action. Conflicting filenames are not available from the public API.
- Review headers own their nested conversations by GitHub review ID. Open comments/conversations and unfinished review containers start expanded; resolved/outdated conversations and fully completed reviews start collapsed. Completion changes update this default; other updates preserve manual choices. The complete title row toggles disclosure and shows an open/closed chevron. An expanded file conversation aligns the starter and replies within one continuous border, with Reply/Resolve and paging after the final loaded comment. Each comment remains independently virtualized. A check badge overlays resolved/outdated starter avatars; parent review badges require every child complete and the review comment count loaded.
- On macOS 26 use system toolbar/inspector chrome and glass buttons for viewer actions; custom floating control surfaces use one GlassEffectContainer with the Settings radii. Document cards retain semantic flat backgrounds. Reduce Transparency and macOS 15 use native flat controls. Verify glass in the running app, not an offscreen render.
- Reference: the three user-supplied 2026-10-08 screenshots. Use their two-column summary/activity composition and rounded conversation cards with the app's semantic colors and SF Symbols.
- Resizable window: 1180 x 820 initially, 860 x 600 minimum. Compact toolbar with Summary, change counts, Refresh, Copy Link and Open in Browser. The Summary item has 12 pt horizontal content padding. No inactive diff tab or simulated editing controls.
- Main conversation uses one Apple WebKit surface with a virtualized DOM: title/metadata, GitHub-rendered description, Activity heading and chronological comments/reviews/commits. Review conversations and replies nest under their owning review and starter. Sidebar is a native 280 pt inspector with merge status, loaded threads, reviews and checks; each column scrolls independently.
- Title is 24 pt semibold with a linked PR number. A status capsule distinguishes Draft, Ready for review, Closed and Merged. The linked author and commit count precede selectable monospace base/head branch chips, wrapping at compact widths. Conversation comments match the menu-bar tokens: 28 pt avatar beside an 8 pt rounded bordered card, tinted 8 pt padded author/time header, 12.5 pt body and monospace file context. Commit and status events are compact timeline lines with a rail, symbol, avatar, linked SHA and time, initially collapsed. Column padding is 24 pt, row gap 12 pt; PR descriptions stay complete. Direct comment links open the target and its ancestors; pagination preserves open conversations.
- Fetch GitHub bodyHTML in the existing core queries. App-bundled HTML/CSS/JavaScript performs browser layout and viewport virtualization without a parser dependency. Mount only visible cards plus overscan; cache measured heights until content or width changes and preserve the visible anchor during height updates. Semantic AppKit colors supply both themes. Public API avatar images load lazily at fixed dimensions with initials on loading/failure. Keep keyboard navigation, selectable content, read-only task checkboxes, expandable details, horizontal code/table scrolling and external links. Raw Markdown is a visible fallback if bodyHTML is unavailable; math/diagram enrichment is explicitly linked to GitHub for this trial.
- Leave comment and thread Reply open a standard native sheet with a focused 168 pt editor, placeholder and compact file context. Cancel and Submit use glass buttons at the top leading/trailing edges with the title between them; the Markdown hint stays below the editor. No dedicated emoji control appears in the composer or parent review container. Unicode and shortcode rendering uses GitHub bodyHTML. Preserve drafts on cancellation/error and disable duplicate submission. Individual-comment GitHub reaction pills show confirmed counts/selection, offer the eight supported types and respect viewerCanReact; failed actions preserve confirmed state. Thread resolution updates after success. All mutations and domain mapping live in the core package; validation never posts fixture content to a live PR.
- Sidebar section headings use 14 pt semibold primary text. Threads, Reviews and Checks use native disclosures expanded initially, with the entire 32 pt header row clickable, including trailing space and vertical padding. Keep the Checks title on one line. Check headers retain colored nonzero failed/succeeded/running/neutral counts while collapsed. Aggregate only loaded checks, identify incomplete pagination in help and keep load-more controls inside the expanded section.
- Open on GitHub is a 24 pt external-link icon in the author/header row with an accessible label and tooltip, rather than a separate content/footer line. Author timestamps retain their direct comment permalink.
- Load activity/threads/replies in bounded pages with visible retry and load-more actions; never silently truncate. Content links use the existing app router; explicit Open in Browser controls bypass it. Page content never receives OAuth credentials; a restrictive CSP and removal of active HTML prevent comment scripts or embedded documents from executing.
- Visible viewer windows temporarily keep the Dock icon available, using the existing saved preference when all viewer and Settings windows close.

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

## Product landing page
The static `docs/` presentation extends this product identity for the web. Its content is deliberately limited to the product description, introduction video, Homebrew installation, five native screenshots, GitHub and the creator's website. The native-app rules above continue to govern app UI.

- Audience: Mac developers checking PRs and Actions; the primary task is understanding the app and copying its installation commands.
- Direction: warm white document, dark indigo display type, lavender surfaces and the real app icon. The large video is the focal object; screenshots prove the product rather than decorate it. The video itself supplies the motion.
- Colors: page `#FBFAFF`, paper `#FFFFFF`, ink `#201A33`, muted `#62596F`, accent `#3B2F88`, hover `#2B2168`, soft `#F0EDF8`, line `#DFDAEA`, terminal `#201A33`, terminal ink `#F8F6FF`, terminal muted `#C4BBD9`, lavender `#BDA8FF`. Shadows use ink at 8% and 14% opacity.
- Typography: native system sans for display/body, system monospace for commands. Display fluid 44–80 px, section heading 32–48 px, body 18–20 px, small/body details 14–16 px. Display tracking -0.055em; body line-height 1.6.
- Layout: document owns scrolling; maximum content width 1120 px; page gutters 24 px mobile / 40 px desktop. Spacing on a 4 px grid: 4, 8, 12, 16, 24, 32, 40, 48, 64, 80, 96. Sections use 80–96 px desktop and 48–64 px mobile separation.
- Reusable primitives: pill links and copy button (default, hover, focus, pressed, success/failure text); eyebrow label; section heading; rounded media frame; screenshot figure with caption. Buttons have 44 px minimum targets, radius 12 px; media frames radius 24 px, inset screenshots radius 12 px. Neutral hairlines and soft shadows provide separation.
- Responsive behavior: two-column intro becomes one column below 1024 px; screenshot grid becomes one column below 640 px; commands wrap without truncating. Media retain explicit dimensions, video aspect ratio 16:9. Screenshots show full native views and can be opened directly for detail.
- Accessibility: semantic landmarks/headings, visible focus, descriptive image alternatives, native video controls with a text summary, no autoplay, no color-only status. Commands remain selectable when clipboard access is unavailable; copy results are announced in a polite live region. No decorative animation; hover color transitions are 160 ms and disabled for reduced motion.
- Notifications: one full-width gallery figure pairs the real Settings capture with success/failure job-alert copy and repository, event, workflow and job customization. Its image/caption columns stack below 640 px. The silent 25-second video uses the same capture in a dedicated notification scene.
- Accepted debt: none. Static HTML intentionally has no framework, analytics, external fonts or tracking.
