# Focused Workspaces — UX Redesign Spec

**Date:** 2026-07-09
**Status:** Approved by Jesse (prototype reviewed at rev. 2)
**Prototype:** interactive HTML artifact, four-reviewer panel pass (culling pro, macOS HIG, IA minimalist, feature-loss skeptic); 55 findings, ~50 adopted.

## Problem

Every mode inherits all the chrome. The window always shows: a sidebar with up
to ten sections (Library routes, Review queues, Folders, Sources, AI, Sync,
Starred, Saved Sets, Recent Work, Starred Work), a top bar (catalog identity +
breadcrumb + search + view switcher + Import button), a window toolbar, a
9-picker filter bar, a footer, and a full-scroll inspector with a pinned
Activity panel. The minimum window width is 1520pt largely to fit it. Nothing
ever feels focused because culling, searching, and identifying faces all render
inside the same everything-at-once frame.

## Constraint

**Refactor, not cut.** Every existing capability keeps a usable home. The
relocation ledger (§9) is normative: an implementation that loses a ledger row
is wrong.

## 1. Structure: three workspaces

Top-level navigation is **intent**, not render style:

- **Cull** — "keep or toss?" (⌘1)
- **Library** — "where is it / what is it?" (⌘2)
- **People** — "who is this?" (⌘3)

The switcher is a **unified-toolbar principal item** (segmented control), not
titlebar decoration: real `ToolbarItem(placement: .principal)`, View-menu items
with ⌘1/2/3, accessibility tab group, auto-hides in full screen. Catalog
identity moves to the window title (proxy icon / `representedURL` where
possible).

One persistent `NavigationSplitView` hosts all three workspaces; each workspace
supplies its own sidebar content (Cull: source picker + stack rail; Library:
navigation; People: none — sidebar collapses). The standard sidebar toggle
works everywhere. View history (⇧⌘[ / ⇧⌘]) is global across workspaces.

`LibraryViewMode` collapses: grid/loupe/compare/abCompare become **sub-views**
(of Cull, and grid/loupe of Library); search/copilot/timeline/map/people
routes dissolve into the structures below.

## 2. Status is not navigation

The Sources, AI, and Sync sidebar sections, the pinned Activity panel, and
footer progress/errors all collapse into **one Activity toolbar item**
(Safari-downloads shape) at the trailing edge:

- **Silent when healthy** — icon only, no permanent spinner.
- Shows determinate progress while background work runs.
- A red badge appears **only for actionable problems** (XMP conflicts, offline
  sources, provider failures) with a count.
- Popover contents: background work list (pause/resume/cancel/star,
  stop-idle-workers), import progress + cancel + errors, per-source
  availability + reconnect, XMP conflict list.
- Conflict rows **deep-link to the affected photos in Library**; per-field
  resolution (Merge Missing / Use Catalog / Use XMP) lives in the inspector,
  not the popover.
- Mirrored by a Window ▸ Activity menu item.

## 3. Cull workspace

Full-bleed loupe stage. **No** search field, import control, filter bar, or
inspector.

**Sidebar (the real NavigationSplitView sidebar):** source picker on top
(Recent imports, Top Picks queue, Needs Eyes queue, any Library selection
handed off via "Cull these"), stack list below (thumb, frame count, decided
state). Collapsible with the standard toggle.

**HUD (single top row over the stage):** filename · current rating stars ·
color-label dot · progress bar · undecided count · picks pill · rejects pill ·
scope chip · provisional-read pill (✦ verdict, e.g. "Sharp · eyes open"). The
assist verdict lives in the HUD, never overlaid on the image.

**Filmstrip (bottom):** stack-aware — divider marks between stacks, current
stack expanded; per-thumb flag/✦ badges; "frame N / M · stack S / T" position
readout.

**Keyboard model (all also menu items in a Culling/View menu):**
- Existing: P/X/U flags, 0–5 ratings, 6/7/8/9/v/- labels, ←→ frames,
  ↑↓ stacks, Return accept, z 1:1 zoom.
- New: **Z zoom-to-face** (1:1 centered on nearest detected face; arrows cycle
  faces), **I** cycles EXIF overlay (off / exposure line / full), **⌥→ / ⌥←**
  next/previous stack, **Return** on a stack = promote current frame + reject
  siblings + advance to next stack, **S** cycles cull scope
  **unrated → picks → rejects → all**, **G/C/B** grid/compare/A-B sub-views,
  **?** full key map overlay.
- Every decision shows a transient toast ("✕ DSCF1023 rejected — U undoes").

**Sub-views:** Grid (survey of the cull set, keeps autopilot KEEP/CUT badges),
Compare (up to 8; **rejecting a frame refills from the stack**), A/B (existing
synced zoom + keep bar). Close-Ups panel toggles from the HUD.

**End-of-set state:** when undecided reaches 0, the stage is replaced by a
completion state: "0 undecided — N picks · **Export…** · **Move rejects…**"
plus the existing completion/autopilot-review banners.

**Engineering invariant:** advancing never blocks on preview rendering —
preload N frames ahead along cull order.

## 4. Library workspace

The only workspace with a navigation sidebar, cut to three sections:

- **Collections:** All Photographs, Recent Import, Starred, Recent Work
  (work-session history, incl. starred work).
- **Saved Sets:** context menus keep rename / duplicate / freeze-snapshot /
  delete.
- **Folders:** existing tree with counts.

**Header row:** token search field · sort control (persistent) · view toggle
**Grid / Loupe / Timeline / Map** · Import button (the single Import
affordance besides the File menu).

**One query surface.** The search field is a token field (`.searchable` with
tokens / NSSearchField-style): typed tokens (`person:`, `keyword:`, `folder:`,
`camera:`, `lens:`, `iso:`, `rating:`, `color:`, `from:`/`before:`/`date:`,
`source:`, `signal:`, `xmp:`), picked filters via autocomplete menu inside the
field, and free-text agentic asks all land as removable tokens. No separate
filter bar, Filter button, or chip row grammar. The search-tips popover stays.

**Result header line:** match count + **parsed interpretation** ("read as:
photos of Maya rated 3+ near sunset") + **Save ▾** menu with all three
semantics: dynamic saved search / frozen snapshot / manual set. Search-refine
suggestions (generated refinements, related filters) surface as suggested
tokens in the field's autocomplete; work history lives under Recent Work.

**Views:** Grid (badges: flag, stars, color dot, availability, autopilot
KEEP/CUT — one glyph vocabulary shared with filmstrip and inspector), Loupe
(Enter/Space on a cell; same loupe component as Cull **without** the cull
HUD), Timeline (existing workspace as a view of the current result set), Map
(existing Places workspace as a view of the current result set).

**Footer:** counts + selection · density control · zoom slider (with ⌘+/⌘-
menu equivalents). Paging is replaced by virtualized scrolling if feasible;
otherwise Load Previous/More stay in the footer.

**Inspector:** `.inspector(isPresented:)`, toggled ⌘I (works in every
workspace; in Cull it switches to Library with the selection). Resizable,
~260–320pt default. Three tabs (radio-group semantics, ⌥⌘1..3):
- **Info** — preview, identity, rating/flag state (display), EXIF, sync state
  (✓ sidecar / pending + retry / conflict with per-field resolver),
  preview-retry.
- **Describe** — keywords, caption, creator, copyright, with **suggested
  keywords and OCR caption suggestions inline next to their fields**
  (confidence shown, one click to accept). Multi-select shows "applies to all
  N selected".
- **AI** — read-only "What Teststrip Sees" verdicts, technical-details
  disclosure with raw scores + provider provenance, provider-failure retry,
  needs-eyes reasons / diagnostics.

Rating/flag/label **editing** stays keyboard + Cull; Info displays state.

## 5. People workspace

Sidebar collapsed. Content leads with the job:

- **"Needs a name" queue:** suggestion cards (confirm-existing / name-new),
  keyboard navigable (arrows move card focus, Return = the explicit confirm
  gesture). "Unnamed faces" and "face quality" review cards fold into this
  queue.
- **Everyone:** named-person cards (avatar, count, merge menu). Clicking a
  person opens **Library** with a `person:` token applied.
- Scanning is background work (Activity item + a People-menu command);
  no scan button on the canvas.

Confirm-before-write is unchanged: nothing writes to `people`/`person_assets`
before the confirming gesture.

## 6. Menu bar

Menus are the system of record; every single-key action has a menu item:

- **File:** Import Folder / From Card (+ dev Import Path in dev builds), Export.
- **Edit:** Undo/Redo metadata (existing).
- **View:** Cull ⌘1 / Library ⌘2 / People ⌘3; sub-view items (Grid/Loupe/
  Compare/A-B; Grid/Loupe/Timeline/Map); zoom ⌘+/⌘-; Show Inspector ⌘I.
- **Culling:** existing shortcut sections + Find Best Shots ⇧⌘B, Run
  Autopilot, Evaluate Photo/Visible/Scope ⇧⌘E, Auto-cull-after-import toggle,
  Move Rejects, scope cycle, stack navigation.
- **Metadata:** Batch Metadata ⌥⌘M.
- **Go:** Back ⇧⌘[ / Forward ⇧⌘] (global history).
- **Window:** Activity.
- **Support:** Copy Diagnostics (existing).

## 7. Window sizing

Each workspace declares its own minimum; the global 1520pt minimum is
replaced. Targets: Library usable at ~1000pt (sidebar collapses first, then
inspector), Cull at ~800pt (rail collapses), People at ~700pt. Exact minimums
settled during implementation; the requirement is that no workspace forces
another's chrome to fit.

## 8. Invariants (unchanged, restated)

- Machine labels stay provisional until an explicit user gesture (assist
  verdicts, KEEP/CUT badges, face suggestions).
- Original bytes never modified; sidecars written only after a user metadata
  gesture.
- Every user-facing flow gets an automated end-to-end scenario
  (test/scenarios); assert catalog ground truth.

## 9. Relocation ledger (normative)

| Today | New home |
|---|---|
| Sidebar Sources / reconnect / refresh-source | Activity popover; offline badge stays on thumbnails |
| Sidebar Sync (XMP pending/conflicts) | Activity badge → popover list → deep-link to photos; per-field resolver in Inspector ▸ Info |
| Sidebar AI signal rows | `signal:` tokens + Inspector ▸ AI |
| Sidebar Recent/Starred Work | Library ▸ Collections ▸ Recent Work |
| Activity panel (all controls incl. star, stop-idle) | Activity popover |
| Copilot route (Top Picks / Needs Eyes / diagnostics) | Queues → Cull source picker; reasons → HUD + Inspector ▸ AI; diagnostics → AI disclosure |
| Search workspace (interpretation, refine rail, 3 saves) | Library result state: interpretation line, suggested tokens, Save ▾ (dynamic/snapshot/manual) |
| Timeline / Places routes | Library view toggles |
| Loupe for browsing | Library view toggle (Enter/Space), loupe minus cull HUD |
| Filter bar (9 pickers) + sort | Token field (typed or picked); sort persistent in header |
| Inspector single scroll | ⌘I `.inspector()`, tabs Info/Describe/AI; suggestions inline in Describe |
| Save search / snapshot / set + set context menus | Save ▾ on result header; sidebar context menus unchanged |
| Catalog identity + breadcrumb | Window title + proxy icon; scope = sidebar selection + tokens |
| Import (button + menus + card + dev path) | Library toolbar button + File menu; card import intact; dev path dev-only |
| Grid/Loupe/Compare/A-B top-level switcher | Cull sub-views (G/C/B + View menu); Compare gains reject-and-refill |
| Keyboard culling model | Unchanged + Z/I/⌥→/Return-promote/scope-cycle/? additions |
| Stacks rail, Close-Ups, assist, ✦, banners | Kept in Cull; assist in HUD; Close-Ups toggles from HUD |
| Autopilot KEEP/CUT grid badges | Kept in Library grid and Cull grid sub-view |
| Find Best Shots, Run Autopilot, Cull, Evaluate ×3, auto-cull toggle | Culling menu; Find Best Shots also on Cull source picker |
| Export, Batch Metadata, Move Rejects | Menus + Library selection action + Cull end-of-set state |
| Footer (density, size, paging, errors) | Density+zoom stay in Library footer; errors/progress → Activity; paging → virtualized scroll or kept |
| Go back/forward | Kept, global across workspaces |
| Search tips popover | Kept on the search field |
| People features (scan, confirm/name, review, merge, name-selection) | Kept; scan → background + menu; review cards fold into queue |

## 10. Explicitly deferred (decided with Jesse)

- Two-vs-three workspace question (People merge) — revisit after dogfooding.
- Starred / Starred Work / Saved Sets concept triplication — separate
  naming/concept pass.
- Hiding pick/reject tallies mid-cull — rejected; remaining count is
  load-bearing for session pacing.

## 11. Testing

- Every relocated feature keeps (or gains) an end-to-end scenario driven via
  `script/ax_drive.sh`, asserting catalog ground truth.
- New scenarios required for: workspace switching (⌘1/2/3 + toolbar), quiet
  Activity item (badge appears only with a conflict; popover actions work),
  token field (typed token filters results; interpretation line renders),
  Cull scope cycle, Return promote-frame/reject-siblings, end-of-set handoff,
  Library Loupe (no cull HUD), inspector tabs incl. inline suggestion accept,
  People queue keyboard flow.
- Negative assertions preserved: no `people`/`person_assets` writes before
  confirm; no sidecar before a user gesture.
