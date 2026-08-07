# Unified Shell (Sources × Lenses) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Dissolve the Cull|Library workspace split into one sidebar of **sources** (All Photos, imports, smart collections, sets, selection) viewed through six **lenses** (Cull, Grid, Loupe, Timeline, Map, People — ⌘1–⌘6), delete the post-import banner in favour of a thin toast plus an Activity-Center receipt, and make every lens honour the selected source.

**Architecture:** `Workspace` (a derived two-case enum) is replaced one-for-one by `LibraryLens` (a derived six-case enum) over the same stored `AppModel.selectedView: LibraryViewMode`; `.compare`/`.abCompare`/`.cullGrid` stay transient sub-modes of the Cull lens. `SidebarRowTarget` grows a title and becomes `LibrarySource` — the single stored answer to "what am I looking at" — so sidebar clicks, nav history, filter chips, session restore, and the scope line all read one type. Each smart source owns exactly one `SetQuery`, from which its count, its list, and its import-scoped variant are all derived. New pure presentation files (`LibraryLens.swift`, `LibrarySource.swift`, `UnifiedSidebarPresentation.swift`, `ScopeLinePresentation.swift`, `ImportCompletionToastPresentation.swift`) keep the shell out of the 14.6k/9.8k-line files except at call sites.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, SQLite (hand-rolled `CatalogDatabase`/`CatalogRepository`), XCTest.

**Spec:** `docs/superpowers/specs/2026-08-07-unified-shell-design.md` **as amended at `edf4dea8`** (decision 9 plus behaviour changes 10 and 11 — Jesse's plan-review rulings). Every decision in it is binding.

**Code map:** `.superpowers/sdd/2026-08-07-unified-shell/code-map.md`. Its numbered frictions **F1, F2, F3, F4, F6, F9, F10, F11, F12, F14, F15, F18** are binding engineering constraints; F5, F7, F8, F13, F16, F17 are already resolved into the amended spec.

---

## Global Constraints

Every task's requirements implicitly include this section.

### Invariants (verbatim from the spec, §"Invariants (unchanged, re-asserted in tests)")

> All SP-D0 invariants hold: ghosts are `origin = ai`, unconfirmed, never
> sidecar-written, never counted as decided, never driving destructive or
> committing operations; auto-apply with provenance; original bytes
> untouched. Import remains non-destructive and in-place. Nothing in this
> spec touches metadata semantics — it relocates chrome.

### Semantic constraints (verbatim from the spec's decisions)

- **No back-compat, anywhere.** "Nobody is using the tool yet. No migration shims, no legacy keybindings, no preserved UserDefaults for the old workspace selection." `SessionRestoreState` may change shape freely; `LibraryViewMode`'s legacy `"search"`/`"copilot"` Codable shim is deleted.
- **One sidebar, six lenses.** "Cull, Grid, Loupe, Timeline, Map, People are top-level views (⌘1–⌘6) over the selected source. The old Cull|Library Picker and its ⌘1/⌘2 bindings are deleted."
- **Orthogonality.** "Switching lenses never changes the selected source or selection; selecting a source never changes the lens (with one exception: a source the current lens disables on — see lens rules — falls back to Grid)."
- **Lens availability.** "Cull disables on diagnostic sources and empty sources; everything else works everywhere. A disabled lens is visibly disabled in the switcher with the reason on hover."
- **Sub-modes are not lenses.** "Compare, A/B Compare, and Cull-grid remain transient sub-modes inside the Cull lens, reached by `g`/`c`/`b` as today."
- **Analysis Failures survives** as the tenth Smart Collection; **the import "Keywords" child is dropped** (YAGNI — Toolbar ▸ Batch Metadata / ⌥⌘M already cover it once the import is the source).
- **Decision 9 (plan-review follow-ups, binding):** "Folders and Recent Work stay as sidebar sections; saved dynamic searches relocate into Smart Collections; the Map explicit-ID gap is fixed in this push; the code renames `.reviewQueue` → `.smartCollection` to follow the domain word." Plus the accepted engineering calls: "the lens switcher is a button row (a segmented Picker can't disable one segment), and bell-receipt retention is a display cap of 5."
- **Sets vs Smart Collections is a taxonomy, not a layout choice:** "live query = smart collection, frozen membership = set (existing dynamic-set rows relocate)."
- **Behaviour change 10:** "Reopening a culling session from Recent Work keeps the current lens (was: forced the loupe) — a consequence of source/lens orthogonality."
- **Behaviour change 11:** "Map becomes scoped for explicit-ID sources too (saved sets, the Selection); today it silently shows the whole catalog for those — a pre-existing gap, fixed in this push."
- **Handoff travels as `SetQuery`, never through the text serializer**, "which is lossy for `.likelyPick`, `.likelyIssue`, `.evaluationFailure`, `.withinGeoBounds`."
- **The badge stays problems-only — receipts never badge.** "The toast is the announcement, the bell is the archive."
- **The toast is session-scoped**, carrying forward `isCurrentSessionActivity`: "a relaunch never resurrects it (the app-006 zombie-panel lesson)."
- **One window minimum width: 1000pt.** The per-workspace 800/1000 split goes away.
- **Out of scope:** the SP-D run lifecycle (start card, exact resume, completion ceremonies, unifying `CullingSessionCompletionSummary` with `CullCompletionPresentation`); any change to import mechanics, preview generation, evaluation, or metadata handling; smart-collection editing UI beyond the existing save actions; multi-window.

### Design constraints (Jesse, binding — YAGNI and DRY)

- **The predicate collapse (F6) happens FIRST**, in Task 1, before any import-scoped variant exists. One `SetQuery` per smart source; count and list both derived from it. Never a third expression. The `ReviewQueue` → `SmartCollection` rename rides in the same task, so the domain word is spelled one way from the first commit.
- **Reuse, don't rebuild:** the result header's existing `Save ▾` actions (F5), the existing import-scope mechanic (F13), `workSessions(kind:statuses:)` and the `latestImportFlaggedReviewAssetCount` shape (F3, F6), `SidebarRow.depth`/`.disclosure` (already used by the Folders tree) for import children, `assetIDs(ids:matching:)` as the import-scoping primitive.
- **Build no capability the spec does not name.**
- **People scoping (F1) is its own task cluster** with new `ids:`-scoped repository overloads, not a lens-rules line item.
- **The toast and the receipt family (F2) are new construction — keep them minimal.**

### Process constraints

- TDD throughout: write the failing test, watch it fail for the right reason, then implement.
- **Adversarial split.** Tasks numbered **NA** author tests only and are **FORBIDDEN from touching any file under `Sources/`**. Tasks numbered **NB** implement and are **FORBIDDEN from modifying any file under `Tests/`**. If an NB implementer believes a test is wrong, they stop and report rather than editing it.
- **Falsification.** Any test in an NA task that would pass immediately against current behaviour must be proven sensitive by a **named break**: the exact file, function, and mutation to apply, the assertion expected to fail, and a `git checkout --` revert. A named break with no captured red transcript is an incomplete task.
- **Test output MUST BE PRISTINE to pass.** No stray prints, no unexpected error logs.
- Smallest reasonable change. Match the style and formatting of surrounding code.
- Tests assert against **catalog/sidecar ground truth**, not just view state.
- Never `git add -A`. Run `git status` first; stage only the files the task names.
- Never skip, evade, or disable a pre-commit hook.
- **Green-after-every-commit rule, stated precisely:** every **NB** commit and every un-split task's commit leaves `swift build` clean and `swift test` at 0 failures. **NA** commits are deliberately red (that is the point of the red proof) and are always immediately followed by their NB. No task *pair* boundary is ever red. See "Sequencing rationale" below for how the shell cutover avoids a red window.
- The headless gate is `make verify`; run it before the final commit of the branch.

---

## Frozen facts (re-verified at plan time)

Every anchor below was read directly at `main` @ `547a6abf` on 2026-08-07 (source is byte-identical to the code map's `11dbb278` — the only diff is the spec document). **Line numbers drift as tasks land; the symbol names and signatures are the contract.**

### FF1 — The workspace machinery being deleted

| Symbol | Anchor | Exact current shape |
|---|---|---|
| `Workspace` | `Sources/TeststripApp/AppModel.swift:50-78` | `public enum Workspace: String, CaseIterable, Sendable { case cull, library }` + `defaultSubView` (`:55`), `title` (`:63`), `keyEquivalent` (`:72`, cull→"1", library→"2") |
| `LibraryViewMode.workspace` | `AppModel.swift:80-89` | `.loupe/.compare/.abCompare/.cullGrid → .cull`; `.grid/.timeline/.map/.libraryLoupe/.people → .library` |
| `LibraryViewMode` Codable shim | `AppModel.swift:22-44` | decodes legacy `"search"`/`"copilot"` as `.grid` — **deletable under no-back-compat** |
| `AppModel.selectedWorkspace` | `AppModel.swift:2100-2102` | `selectedView.workspace` (computed) |
| `AppModel.selectedView` + `didSet` | `AppModel.swift:2054-2095` | six side effects; see FF2 |
| `AppModel.lastSubView` | `AppModel.swift:2139` | `private var lastSubView: [Workspace: LibraryViewMode] = [:]` |
| `AppModel.selectWorkspace(_:)` | `AppModel.swift:4955-4957` | `selectedView = lastSubView[workspace] ?? workspace.defaultSubView` |
| `AppModel.sidebarSections(for:)` | `AppModel.swift:2119-2136` | `.library` → `defaultSidebarSections(…)`; `.cull` → `[]` |
| `AppModel.isCullingMenuShortcutActive` | `AppModel.swift:2112-2114` | `CullingKeyCaptureGate.isActive(workspace: selectedWorkspace, selectedView: selectedView)` |
| `CullingKeyCaptureGate.isActive` | `Sources/TeststripApp/CullingKeyCaptureView.swift:11-15` | `workspace == .cull && selectedView != .cullGrid` |
| `WorkspaceChromePolicy` | `Sources/TeststripApp/LibraryGridView.swift:8357-8415` | twelve statics; base is `showsBrowseChrome = view.workspace == .library && view != .people` (`:8361-8363`); `showsLibraryViewToggle = view.workspace == .library` (`:8380-8382`); `showsInspector` returns `true` unconditionally (`:8390-8392`) |
| `workspaceSwitcher` | `LibraryGridView.swift:463-474` | `.segmented Picker("Workspace")`, 220pt, mounted `ToolbarItem(placement: .principal)` at `:234-236` |
| `librarySubViewToggle` | `LibraryGridView.swift:480-494` | `.segmented Picker("Library View")`, 340pt, `.accessibilityLabel("Library View")`, five tags `.grid/.libraryLoupe/.timeline/.map/.people`; rendered from `libraryTopBar` `:550-587` at `:552-554` |
| `WorkspaceCommands` | `Sources/TeststripApp/main.swift:185-220` | `CommandGroup(after: .toolbar)`; `ForEach(Workspace.allCases)` → `Button(workspace.title)` `.keyboardShortcut(workspace.keyEquivalent, modifiers: [.command])` (`:194`); then `Divider()` + `subViewButton(for:)` (`:209-219`) |
| `AppMenuCoveragePresentation.workspaceActionIDs` | `main.swift:108` | `Workspace.allCases.map(\.title)` |
| `AppMenuCoveragePresentation.subViewMenuModes` | `main.swift:113-116` | `[.loupe, .cullGrid, .compare, .abCompare, .grid, .libraryLoupe, .timeline, .map, .people]` |
| `AppWindowLayoutMetrics` | `main.swift:5-23` | `minimumWidth(for:)` `.library → 1_000`, `.cull → 800`; `defaultWidth = 1_520`, `minimumHeight = 720`, `defaultHeight = 820` |
| sidebar branch | `main.swift:43-48` | `if model.selectedWorkspace == .cull { CullSidebarView(model:) } else { SidebarView(model:) }` |
| window min width | `main.swift:58-61` | `.frame(minWidth: AppWindowLayoutMetrics.minimumWidth(for: model.selectedWorkspace), minHeight: …)` |
| `LoupeZoomView` inspector gate | `Sources/TeststripApp/LoupeZoomView.swift:273` | `WorkspaceChromePolicy.showsInspector(model.selectedView)` — survives verbatim |

### FF2 — `selectedView.didSet` side effects (all six inherited)

`AppModel.swift:2054-2095`, in order:

1. `:2063-2065` — records `lastSubView[selectedView.workspace] = selectedView` unless `.compare`/`.abCompare` (the ⌘1 dead-key fix, documented `:2056-2062`).
2. `:2066` — `updateCompareSetAfterViewChange(from: oldValue)`.
3. `:2067` — `persistSessionState()`.
4. `:2068-2070` — `rebuildSidebarSections()` **only when the workspace changes**.
5. `:2076-2078` — clears `lastCullingMetadataDecision` on leaving Cull.
6. `:2082-2093` — once-per-session "Press ? for keyboard shortcuts" hint on first entry to Cull, guarded by `hasShownCullKeyboardHint` (`:2098`).

### FF3 — Sidebar targets, rows, sections, and the apply path

| Symbol | Anchor | Shape |
|---|---|---|
| `SidebarRowTarget` | `AppModel.swift:990-1005` | 14 cases: `allPhotographs, search, timeline, people, places, placeholder, reviewQueue(ReviewQueue), folder(String), sourceAvailability(SourceAvailability), evaluationKind(EvaluationKind), metadataSyncPending, metadataSyncConflicts, assetSet(AssetSetID), workSession(WorkSessionID)` |
| `SidebarRow` | `AppModel.swift:1045-1085` | `id, title, detailText, countText, tone, target, liveMockupPlaceholder, depth, disclosure`; `isSelectable = target != .placeholder` (`:1082-1084`) |
| `SidebarRowDisclosure` | `AppModel.swift:1087-1091` | `.none/.collapsed/.expanded` |
| `SidebarRowTone` | `AppModel.swift:1115-1121` | `.neutral/.accent/.positive/.warning/.destructive` |
| `SidebarSection` | `AppModel.swift:1123-1145` | `title`, `rows: [SidebarRow]`, `rowTitles` |
| `SidebarRowContextActionKind` | `AppModel.swift:1007-1014` | six cases, all asset-set / work-session star-rename-delete |
| `selectSidebarRow(_:)` | `AppModel.swift:4932-4934` | → `selectSidebarTarget(row.target)` |
| `selectSidebarTarget(_:)` | `AppModel.swift:4948-4951` | `applySidebarTarget(target)` then `recordNavigation(to: target)` |
| `applySidebarTarget(_:)` | `AppModel.swift:5016-5076` | **sets `selectedView` in eight arms** — `.allPhotographs`→`.grid` `:5020`, `.search`→`.grid` `:5027`, `.timeline`→`.timeline` `:5030`, `.people`→`.people` `:5034`, `.places`→`.map` `:5039`, `.folder`→`.grid` `:5047`, `.sourceAvailability`→`.grid` `:5053`, `.metadataSync*`→`.grid` `:5061`/`:5067` |
| `applyReviewQueue(_:)` | `AppModel.swift:11062-11089` | clears, ten-arm filter-property switch, `selectedView = .grid` `:11087`, `reload()` |
| `applyWorkSession(id:)` | `AppModel.swift:5078-5092` | clears, sets `librarySearchText` to a `session:` token, `selectedView = session.kind == .culling ? .loupe : .grid` `:5089`, `reload()`, `statusMessage` |
| `applyAssetSet(id:)` | `AppModel.swift:5468-5482` | `selectedAssetSetID = id`, clears query filters, `selectedView = .grid` `:5480`, `reload()` |
| `applyEvaluationKindFilter(_:)` | `AppModel.swift:11031-11037` | clears, sets `evaluationKindFilter`, `.grid`, `reload()` |
| nav history | `AppModel.swift:2149-2151`, `4977-5014` | `[SidebarRowTarget]` back/forward stacks; ⌘⇧[ / ⌘⇧] at `main.swift:327-339` |
| `defaultSidebarSections(…)` | `AppModel.swift:14113-14182` | 22-param static; Collections (`:14140-14171`) + optional Saved Sets (`:14172-14174`) + optional Folders (`:14175-14180`) |
| `recentlyAddedSidebarRow(_:)` | `AppModel.swift:14328-14344` | the "Recent Import" row, `tone: .positive`, `target: .workSession(...)` |
| `mergedRecentWorkSidebarRows(…)` | `AppModel.swift:14187-14197` | `recentWork.prefix(5)` + up to 5 extra starred |
| `workSidebarRows(for:idPrefix:scopeCounts:)` | `AppModel.swift:14399-14415` | |
| `workSidebarTitle(for:)` | `AppModel.swift:14421-14428` | special-cases `title == "Import photos"` → uses `detail` |
| `visibleSavedAssetSets(_:)` | `AppModel.swift:14346-14352` | filters `work-output-`/`work-input-`/`work-stack-` prefixes |
| `sidebarRow(for assetSet:count:)` | `AppModel.swift:14354-14363` | `tone: assetSet.isDynamic ? .accent : .neutral` |
| `folderTreeSidebarRows(catalogFolders:expandedFolderPaths:)` | `AppModel.swift:14203-14210` + `:14212-14234` | expand-on-demand tree; sets `depth` and `disclosure` |
| `reviewQueueSidebarRows(reviewQueueCounts:)` | `AppModel.swift:14236-14249` | drops zero-count rows |
| `sidebarCountText(_:)` | `AppModel.swift:14417-14419` | `count.formatted(.number.notation(.compactName))` |
| `rebuildSidebarSections()` | `AppModel.swift:13167-13169` | `sidebarSections = sidebarSections(for: selectedWorkspace)` |
| `refreshCatalogSidebarCounts()` | `AppModel.swift:13210-13217` | reviewQueueCounts → ghost IDs → assetSetCounts → `refreshLatestImportPresentation()` → `rebuildSidebarSections()` |
| `toggleFolderExpansion(path:)` | `AppModel.swift:4939-4946` | mutates `expandedFolderPaths`, `rebuildSidebarSections()`, never reloads |
| `SidebarView` | `Sources/TeststripApp/SidebarView.swift` (533 lines) | `List` over `model.sidebarSections` `:25-43`; `.frame(minWidth: 220)` `:44`; `savedSetsSectionHeader` `:86-108`; `sidebarRowContent` `:189-200` (depth/disclosure); `folderDisclosureControl` `:215-233`; `toggleFolderExpansion(_:)` `:176-179` (guarded `case .folder`); `iconName(for:)` `:346-377` (exhaustive over all 14 targets) |
| `CullSidebarView` | `Sources/TeststripApp/CullSidebarView.swift` (125 lines) | `Section("Cull From")` `:15`, `Section("Stacks · Auto-Grouped")` `:30`, `sourceRow` `:53-66`, `stackRow` `:76-124`, `.frame(minWidth: 220)` `:37` |

### FF4 — Smart-source predicates (the F6 collapse targets)

| Symbol | Anchor | Shape |
|---|---|---|
| `ReviewQueue` | `AppModel.swift:665-676` | `public enum ReviewQueue: String, CaseIterable, Equatable, Hashable, Sendable` — ten cases: `picks, potentialPicks, rejects, fiveStars, needsKeywords, needsEvaluation, facesFound, ocrFound, likelyIssues, providerFailures`. **Not `Codable` today.** |
| `ReviewQueue.presentation` | `AppModel.swift:688-713` | title + systemImage per case; `.providerFailures` → `"Analysis Failures"` / `"bolt.horizontal.circle"` |
| `reviewQueueSidebarOrder` | `AppModel.swift:14251-14262` | picks, potentialPicks, rejects, fiveStars, needsKeywords, needsEvaluation, facesFound, ocrFound, likelyIssues, providerFailures |
| `reviewQueueQuery(_:)` | `AppModel.swift:14272-14295` | **count-side expression** — the ten `SetQuery`s |
| `reviewQueueCounts(repository:)` | `AppModel.swift:14264-14270` | loops `reviewQueueSidebarOrder`, `repository.assetCount(matching: reviewQueueQuery(queue))` |
| `applyReviewQueue(_:)` | `AppModel.swift:11062-11089` | **list-side expression** — the duplicate |
| `detachedLibraryFilterPredicates` | `AppModel.swift:2363` (`private var … : [SetQuery.Predicate]`), read `:3275`, `:11668`, written `:11604`, `:11617-11628`, cleared `:11767`, `:4399` | already folded into `currentLibraryQuery()` (`:11668-11670`) **and** into the chips (`activeLibraryFilterRows` `:3275-3278`) |
| `activeLibraryFilterRow(for:)` | `AppModel.swift:11338-11389` | every predicate already has a chip title and a target |
| `sidebarTarget(for predicate:)` | `AppModel.swift:11413-11446` | predicate → `SidebarRowTarget?` |
| `currentLibraryQuery()` | `AppModel.swift:11663-11743` | assembles from `selectedDynamicSetQuery` + detached predicates + `librarySearchText` + ~20 filter properties |
| `clearLibraryQueryFilters()` | `AppModel.swift:11745-11769` | resets them all, including `detachedLibraryFilterPredicates = []` |
| `reload()` | `AppModel.swift:10870-10913` | the single funnel; explicit-ID short-circuit `:10885-10894`; query branch `:10897-10903`; Map refresh `:10890`/`:10910` |
| `currentAssetScopeIDs(repository:includeBondedSecondaries:)` | `AppModel.swift:12542-12559` | explicit IDs → `assetIDs(matching:)` → whole catalog |
| `currentLibraryAssetCount(repository:)` | `AppModel.swift:11965-11973` | same three-way branch, counts |

### FF5 — Import completion (deleted) and what survives

| Symbol | Anchor | Disposition |
|---|---|---|
| `ImportCompletionPresentation` | `LibraryGridView.swift:8916-9246` | **Deleted** (Task 9B) |
| `ImportCompletionMetricRow` | `LibraryGridView.swift:9248-9275` | **Deleted** |
| `ImportCompletionActionPresentation` | `LibraryGridView.swift:9277-9301` | **Deleted** (nine `Kind` cases at `:9278-9288`) |
| `importCompletionSummary(_:)` / `importCompletionMetric(_:)` / `importCompletionAction(_:)` / `importCompletionActionLabel(_:)` / `performImportCompletionAction(_:)` | `LibraryGridView.swift:1420-1469`, `1471-1499`, `1501-1520`, `1522-1546`, `1548-1569` | **Deleted** |
| `LibraryGridChromePolicy.shouldShowImportCompletionSummary` | `LibraryGridView.swift:8463-8476` | **Deleted**; its session-scope guard moves into the toast presentation |
| `dismissedImportCompletionSummaryID` | `LibraryGridView.swift:45` (`@State`), written `:1445`, read `:746` | **Deleted** |
| `visibleImportCompletionSummary` | `LibraryGridView.swift:741-752` | **Deleted** |
| `topInsetContent` banner mount | `LibraryGridView.swift:735-737` | **Deleted** |
| view-local wrappers | `LibraryGridView.swift:3138-3213` | `openLatestImportCompletion` `:3138`, `beginCullingFromLatestImportCompletion` `:3146`, `beginStackCullingFromLatestImportCompletion` `:3155`, `reviewLatestImportInCompare` `:3164`, `reviewLatestImportFlagged` `:3173`, `reviewImportIssuesFromCompletion` `:3181`, `reviewLatestImportKeywordSuggestions` `:3186`, `requestLatestImportEvaluations` `:3198`, `reviewFaceQueueFromImportCompletion` `:3207` — **all deleted except** `beginCullingFromLatestImportCompletion` and `beginStackCullingFromLatestImportCompletion`, which move to the toast / import-row context menu |
| `ImportIssueReview` | `LibraryGridView.swift:9303-9308` | **Survives** — reused by the "⚠ Skipped files" child (F12) |
| `importIssueReview` sheet | `LibraryGridView.swift:46`, `:190-192` | **Survives** |
| `ImportCompletionSummary` | `AppModel.swift:1426-1443` | **Survives** — the toast/receipt data source |
| `AppModel.latestImportCompletionSummary` | `AppModel.swift:3383-3391` | **Survives** |
| `latestImportFlaggedReviewAssetCount(summary:)` | `AppModel.swift:3499-3511` | **The shape to copy** for every import-scoped count: `assetCount(matching: SetQuery([.importBatch(id), .likelyIssue]))` |
| `latestImportFaceReviewAssetCount(assetIDs:)` | `AppModel.swift:3487-3497` | `assetIDs(ids:matching: reviewQueueQuery(.facesFound))` |
| `isCurrentSessionActivity(id:)` | `AppModel.swift:13869-13871` | **Survives** — the toast's session guard |
| `isImportCompletionActivity(_:)` | `AppModel.swift:13838-13840` | `kind == .ingest && status == .completed` |
| `recordCompletedImportActivity(…)` | `AppModel.swift:13667-13698` | writes `title: "Import photos"`, `detail:` from `importCompletionDetail(result:sourceDescription:)`, `issues:` from `workSessionIssues(for:)`; sets `activeWork = nil` `:13694` before `recordRecentActivity` `:13696` |
| `recordRecentActivity(_:intent:inputSetIDs:outputSetIDs:)` | `AppModel.swift:13873-13905` | inserts into `recentWork`, `currentSessionActivityIDs.insert` `:13882`, persists the `WorkSession` `:13891` |
| `beginStackCullingFromLatestImportCompletion()` | `AppModel.swift:5110-5164` | **Survives** — F10: its only affordance today is the banner's "Cull stacks"; it becomes the import row's **Stacks** child |
| `reviewLatestImportInCompare()` | `AppModel.swift:5166-5169` | **Survives** — becomes the import row's context-menu "Manual Compare over the import" |
| `reviewLatestImportFlagged()` | `AppModel.swift:5171-5181` | **Deleted** — replaced by the "⚠ Likely issues" child (F10) |

### FF6 — Activity Center

| Symbol | Anchor | Shape |
|---|---|---|
| `ActivityCenterPresentation` | `Sources/TeststripApp/ActivityCenterPresentation.swift:146-185` | `badge, isWorking, kindRows, importProgress, importError, sources, xmpConflicts`; init `(kindRows:importActivity:importError:sources:xmpConflicts:providerFailureCount:)` `:160-167`; badge math `:174-176` = `xmpConflicts.count + unavailableSourceCount + providerFailureCount` |
| `ActivityCenterPresentation.Badge` | `:147-150` | `case none; case problems(Int)` |
| `ActivityKindRow` | `:72-140` | one row per `WorkSessionKind`; `rows(from:canPause:canResume:)` `:108` |
| `AppModel.activityCenterPresentation` | `AppModel.swift:2995-3037` | the single producer; reads `activeWorkKindRows` (`:2984-2987`), `visibleImportActivity` (`:2918-2926`), source rows, conflicts, `reviewQueueCounts[.providerFailures]` (`:3035`) |
| `ActivityCenterView` | `Sources/TeststripApp/ActivityCenterView.swift:9-266` | sections at `:22` kindRows, `:30` idle worker, `:33` sources, `:36` conflicts, `:39-43` "No active work" gated by `isQuiet(_:)` `:56-60` |
| bell button | `LibraryGridView.swift:414-432` | popover width 340 `:430`; icon `:435-454`; badge circle `:445-452`; help `:456-461`; ⇧⌘0 at `main.swift:598-610` |
| **no receipt today** | — | `recentWork` is never referenced by `activityCenterPresentation` or `ActivityCenterView` |
| **no reusable toast today** | `LibraryGridView.swift:4534-4565` | the only auto-dismissing overlay is `LoupeView.decisionToast`, hardcoded to `model.lastCullingMetadataDecision` |

### FF7 — Work sessions and imports (F3)

| Symbol | Anchor | Shape |
|---|---|---|
| `WorkSession` | `Sources/TeststripCore/Work/WorkSession.swift:52-101` | **carries `createdAt: Date` and `updatedAt: Date`** (`:66-67`), plus `kind, intent, title, detail, status, inputSetIDs, outputSetIDs, completedUnitCount, totalUnitCount, failureCount, issues, starred` |
| `WorkSessionIssue` | `WorkSession.swift:36-50` | `enum Kind { case skippedSourceFile }`, `sourceURL: URL?`, `message: String` |
| `WorkSessionKind` | `WorkSession.swift:11-25` | 13 cases, `.ingest` at `:12` |
| `workSessions(kind:statuses:)` | `Sources/TeststripCore/Catalog/CatalogRepository.swift:2120-2133` | `ORDER BY updated_at DESC`, **no limit** — the query the Imports section uses |
| `workSessions(limit:starredOnly:)` | `CatalogRepository.swift:2082-2097` | every caller passes `limit: 10` |
| `session(id:)` | `CatalogRepository.swift:2074-2080` | throws `CatalogError.notFound` |
| `AppWorkActivity` | `AppModel.swift:1349-1424` | **has no date field**; `init(workSession:)` `:1408-1423` drops `createdAt`/`updatedAt` |
| `refreshWorkSessions()` | `AppModel.swift:5493-5505` | fills `recentWork`, `starredWork`, `workSessionScopeCounts`, then `refreshLatestImportPresentation()` + `rebuildSidebarSections()` |
| import literals | `AppModel.swift:13677-13678` | `title = "Import photos"` (constant), `detail` = the only distinguishing text |
| `.importBatch(String)` predicate | `SetQuery.swift:41`; SQL `CatalogRepository.swift:3220-3236` | joins `work_sessions.output_set_ids_json` → `asset_sets` membership |
| `.workSession(String)` predicate | `SetQuery.swift:42` | joins both input and output sets |

### FF8 — People (F1)

Every people/face read in `CatalogRepository.swift` is catalog-wide or per-asset. The three the People lens needs scoped:

| Symbol | Anchor | Current signature |
|---|---|---|
| `people()` | `CatalogRepository.swift:1238-1255` | `public func people() throws -> [CatalogPerson]` — `LEFT JOIN person_assets`/`assets`, `GROUP BY people.id`, `ORDER BY people.name COLLATE NOCASE ASC`, excludes bonded secondaries via `assets.bonded_to_asset_id IS NULL` |
| `unassignedFaceObservations(provenance:limit:)` | `CatalogRepository.swift:1423-1462` | five `NOT EXISTS` guards, `ORDER BY created_at DESC, asset_id ASC, face_index ASC`, `LIMIT ?` |
| `faceObservationAssetCount(provenance:)` | `CatalogRepository.swift:1690-1700` | `SELECT COUNT(DISTINCT asset_id) FROM face_observations WHERE provider/model/version/settings_hash` |
| chunking helper | `CatalogRepository.swift:424` (usage) | `Self.chunks(_:size:)`, size 500 |
| `AppModel.refreshPeopleFaceSuggestions()` | `AppModel.swift:3833-3861` | pulls `unassignedFaceObservations(provenance:limit: Self.maximumFaceSuggestionInputCount)` (`:3837-3840`, constant `= 2000` at `:3811`), unions confirmed+contact embeddings `:3841`, `FaceSuggestionBuilder().suggestions(…)` `:3842`, maps via `peopleFaceSuggestions(from:…)` `:3851`, then `peopleFaceObservationAssetCount = try …faceObservationAssetCount(provenance:)` `:3857` |
| `AppModel.loadCatalogPeople()` | `AppModel.swift:3735-3739` | `catalogPeople = try …people()`; `personKeyFaces = try …keyFacesByPerson(provenance:)` |
| `AppModel.catalogPeople` | `AppModel.swift:2379` | `public var catalogPeople: [CatalogPerson]` |
| `AppModel.peopleFaceObservationAssetCount` | `AppModel.swift:2392` | `public private(set) var … = 0` |
| `PeoplePresentation` | `Sources/TeststripApp/PeopleView.swift:601-…` | built in `PeopleView.presentation` `:18-29` from `totalAssetCount`, `catalogPeople`, `catalogEvaluationKindSummaries`, `canRequestPeopleFaceScan`, `peopleFaceSuggestions`, `peopleFaceObservationAssetCount`, `hasUnavailableSourceRoots`, `personKeyFaces` |
| `AppleVisionEvaluationProvider.faceProvenance` | used `AppModel.swift:3836` | the provenance every people read passes |

### FF9 — Preview failures (F12)

| Symbol | Anchor | Shape |
|---|---|---|
| `previewGenerationFailureAssetCount(assetIDs:)` | `CatalogRepository.swift:2618-2641` | chunked at 500; `SELECT COUNT(DISTINCT asset_id) FROM preview_generation_queue WHERE asset_id IN (…) AND attempt_count > 0 AND COALESCE(last_error, '') != ''` |
| `previewGenerationPendingAssetCount(assetIDs:)` | `CatalogRepository.swift:2643-2664` | the sibling |
| `latestImportPreviewFailureCount(activity:assetIDs:)` | `AppModel.swift:3571-…` | `max(activity.failureCount, repository.previewGenerationFailureAssetCount(assetIDs:))` |

### FF10 — Stacks over an import (F10)

| Symbol | Anchor | Shape |
|---|---|---|
| `latestImportOutputAssetIDs(activityID:repository:includeBondedSecondaries:)` | `AppModel.swift:13007-13023` | reads `session.outputSetIDs.first`, expands manual/snapshot/dynamic membership |
| `latestImportStackGroups(activityID:repository:)` | `AppModel.swift:13072-13084` | `LatestImportStackGroups { multiFrameStacks, singleAssetIDs }` (`:13067-13070`) |
| `latestImportStacks(activityID:repository:)` | `AppModel.swift:13086-13088` | multi-frame stacks only |
| `stackBuilder()` | `AppModel.swift:13029-13031` | "the single source of truth every live stack-building path shares" |
| `beginStackCullingFromLatestImportCompletion()` | `AppModel.swift:5110-5164` | mints per-stack `AssetSet`s, records `stackCullingImportActivityIDBySessionID`, lands on `recommendedStackLandingAssetID(for:)`, `selectedView = .loupe` |

### FF11 — Timeline and Map (F11)

| | Timeline | Map |
|---|---|---|
| Presentation | `Sources/TeststripApp/TimelinePresentation.swift:4-57` | `Sources/TeststripApp/PlacesPresentation.swift:30` |
| The unused init | `init(assets:totalAssetCount:calendar:)` `:10-17` — self-derives the histogram via `Self.timelineDays(from:calendar:)`; **exercised only by `Tests/TeststripAppTests/TimelinePresentationTests.swift`** | `init(clusters:topLocations:coverage:)` |
| Render site | `TimelineWorkspaceView` `LibraryGridView.swift:7833-7845` — feeds `timelineDays: model.catalogTimelineDays` (**whole catalog**) + `loadedAssets: model.assets` (filtered) | `PlacesWorkspaceView` `LibraryGridView.swift:7674-7685` |
| Aggregate source | `AppModel.catalogTimelineDays` (`:2372`), filled by `CatalogRepository.timelineDays()` (`:639`) which takes **no query** | `AppModel.refreshPlaceData(bounds:cellSize:)` `:11017-1026`, already query-scoped |

**The Map's three reads and the gap (F11's second half).** All three take the same optional `matching query: SetQuery?` and build their WHERE from it:
`placeClusters(bounds:cellSize:matching:)` (`CatalogRepository.swift:678-…`), `topLocations(limit:matching:)` (`:942-…`, with a SQL `LIMIT`), `geotaggedCoverage(matching:)` (`:737-…`). `refreshPlaceData` passes `currentLibraryQuery()` (`:11022`), which is **nil for a manual/snapshot `AssetSet`** — that scope lives only in `AppModel.selectedExplicitAssetIDs` (private computed; returns the set's ids for `.manual`/`.snapshot`, nil for `.dynamic`), which none of the three reads can see. Result shapes: `CatalogPlaceCluster { latitude, longitude, assetCount }`, `CatalogTopLocation { displayName, assetCount, latitude, longitude }`, `CatalogGeotaggedCoverage { geotaggedCount, totalCount }` (`Sources/TeststripCore/Catalog/CatalogPlaceCluster.swift`, `CatalogTopLocation.swift`). `AppModel.catalogPlaceClusters` / `catalogTopLocations` / `geotaggedCoverage` are `public private(set)` at `:2373-2375`.

**The set-membership SQL idiom to copy:** `workSessionAssetMembershipSelector(setIDColumnName:membershipPath:)` (`CatalogRepository.swift:3328-3336`) resolves set membership with `JOIN json_each(asset_sets.membership_json, '$.manual._0' | '$.snapshot._0')` and `json_extract(session_assets.value, '$.rawValue')`. `json_each` on a path that does not exist yields zero rows, which is what makes a `.dynamic` set match nothing. Five exhaustive switches over `SetQuery.Predicate` must gain an arm when a case is added: `CatalogRepository.compileClauses` (`:3209` area), `AppModel.activeLibraryFilterRow(for:)` (`:11382`), `AppModel.sidebarTarget(for:)` (`:11441`), `AppModel.searchTextToken(for:)` (`:11936`), `LibraryQueryTokenField` (`:359`).

### FF12 — Session restore (F17)

| Symbol | Anchor | Shape |
|---|---|---|
| `SessionRestoreState` | `Sources/TeststripApp/SessionRestoreState.swift:8-36` | `currentVersion = 1`; persists `version, selectedView, selectedAssetSetID, selectedAssetID, sortOption, librarySearchText` + 18 filter properties |
| `SessionRestoreStore` | `SessionRestoreState.swift:44-70` | key `"SessionRestoreState.\(catalogRoot.standardizedFileURL.path)"` `:53-55`; `load()` `:62-69` returns nil on decode failure **or version mismatch** |
| `persistSessionState()` | `AppModel.swift:11781-11785` | |
| `currentSessionRestoreState()` | `AppModel.swift:11787-11814` | |
| `restoreSessionStateIfAvailable()` | `AppModel.swift:11816-11822` | |
| `applyRestoredSessionState(_:catalog:)` | `AppModel.swift:11827-11875` | `selectedView = Self.isRestorableSessionRoute(state.selectedView) ? state.selectedView : .grid` `:11856` |
| `isRestorableSessionRoute(_:)` | `AppModel.swift:11878-11885` | allows only `.grid/.timeline/.people/.map` |

### FF13 — Tests that pin what this plan changes

| Test file | Lines | What it pins |
|---|---|---|
| `Tests/TeststripAppTests/WorkspacePresentationTests.swift` | 65 | `Workspace.allCases == [.cull, .library]`, titles, ⌘1/⌘2, `workspace` mapping for all nine modes, `selectWorkspace` restore, the compare/abCompare trap fix |
| `Tests/TeststripAppTests/WorkspaceChromePolicyTests.swift` | 74 | `browseViews = [.grid, .timeline, .map, .libraryLoupe]`, `nonBrowseViews = [.people, .loupe, .compare, .abCompare, .cullGrid]`, the toolbar matrix |
| `Tests/TeststripAppTests/AppWindowLayoutTests.swift` | 28 | `minimumWidth(for:)` per workspace; Library wider than Cull; default ≥ every minimum |
| `Tests/TeststripAppTests/MenuCoveragePresentationTests.swift` | 100 | `workspaceActionIDs == Workspace.allCases.map(\.title)` (`:20`); `subViewMenuModes` covers every `LibraryViewMode` rawValue (`:26-29`) — **F14: must land in the same commit** |
| `Tests/TeststripAppTests/CullingKeyCaptureTests.swift` | `:216-222`, `:261-266` | `CullingKeyCaptureGate.isActive(workspace:selectedView:)` matrix |
| `Tests/TeststripAppTests/SidebarSectionsTests.swift` | 119 | `sidebarSections(for: .library) == ["Collections","Saved Sets","Folders"]`; `sidebarSections(for: .cull) == []`; workspace tracking |
| `Tests/TeststripAppTests/CullSourcePresentationTests.swift` | 218 | `cullSourcePresentation` groups, zero-count omission, `cullCurrentSelection` (`:134`, `:148` assert `selectedWorkspace == .cull`) |
| `Tests/TeststripAppTests/InspectorTabsPresentationTests.swift` | 13 refs | `selectWorkspace`/`selectedWorkspace` at `:68,73,87,95,100,112,117,123,128,159,170,184,198` |
| `Tests/TeststripAppTests/AppModelFilterPersistenceTests.swift` | 5 refs | `selectWorkspace` at `:37,40,55,183,212` |
| `Tests/TeststripAppTests/CullSubViewSwitchingTests.swift` | `:17,23,62` | cull sub-view switching stays in the cull workspace |
| `Tests/TeststripAppTests/AppModelTests.swift` | `:342-390` nav history via `.people/.timeline/.search`; `:796-812` ⌘1 trap; `:2666-2692` workspace switching; `:6538-6557` `selectSidebarTarget(.reviewQueue(.needsEvaluation))` asserts `needsEvaluationFilter == true`; `:6559-…` `activeLibraryFilterRows` target equality; `:19939` `selectSidebarTarget(.places)` | |
| `Tests/TeststripAppTests/SessionRestoreStateTests.swift` | `:7-37` round-trip lists every field | |
| `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift` | `:13,223,268` `selectSidebarTarget(.search)`; `:290-312` a full `SessionRestoreState(...)` literal | |
| `Tests/TeststripAppTests/PlaceholderTests.swift` | `:98-107` | pins the 4b `currentImplementation` prose — **must change in the same commit as the 4b rewrite** |
| `Tests/TeststripAppTests/ImportCompletionPresentationTests.swift` | 282 | entirely about the deleted banner presentation |
| `Tests/TeststripAppTests/LibraryGridChromeTests.swift` | 524 | includes `shouldShowImportCompletionSummary` cases and `windowSubtitle(for:)` |

### FF14 — Test fixture patterns to copy

- **AppModel + real catalog:** `Tests/TeststripAppTests/CullSourcePresentationTests.swift:187-217` (`makeModelWithCatalogAssets(named:assets:configureRepository:)` + `makeTemporaryDirectory(named:)` + `makeAsset(id:path:rating:flag:technicalMetadata:)`). `SidebarSectionsTests.swift:77-118` is the same pattern without `configureRepository`.
- **Session restore:** `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift:314-360` (`makeTemporaryDirectory`, `makePaths`, `makeCatalog`, `makeIsolatedDefaults`, `seedAssets`, `makeAsset`).
- **Bare AppModel:** `AppModel(sidebarSections: [], selectedView: .grid, assets: [])` (used throughout `AppModelTests`), and `AppModel.demo()` (`AppModel.swift:4538-4552`).
- **Core repository:** `Tests/TeststripCoreTests/CatalogDatabaseTests.swift` uses `@testable import TeststripCore` and `TestDirectories.makeTemporaryDirectory(named:)`.

### FF15 — Scenario-card corpus

131 `.md` files in `test/scenarios/` (flat) plus `README.md` and `LEDGER.md`. **75 cards mention ⌘1 or ⌘2; 14 mention ⌘3** (already stale). Next free numbers: **`app-019`**, **`import-011`**, `cull-030`, `lib-022`, `activity-008`, `people-027`. The LEDGER is a markdown table, one row per card, with a house-style `Reconciled — NOT re-run` status and a `supersedes prior status: …` note (see the `cull-015`/`cull-016`/`cull-017` rows).

---

## File structure

**Created (Sources):**

- `Sources/TeststripApp/LibraryLens.swift` — `LibraryLens`, `LibraryViewMode.lens`, `LensAvailability`, `LensRules`. Replaces `Workspace`.
- `Sources/TeststripApp/LibrarySource.swift` — `LibrarySourceKind`, `LibrarySource`, `ImportChildKind`. Replaces `SidebarRowTarget`.
- `Sources/TeststripApp/UnifiedSidebarPresentation.swift` — the one sidebar's section/row composition + `ImportSourceSummary` + `ImportChildCounts`. Replaces `AppModel.defaultSidebarSections` and `CullSidebarView`'s source list.
- `Sources/TeststripApp/ScopeLinePresentation.swift` — the persistent scope line under the toolbar.
- `Sources/TeststripApp/ImportCompletionToastPresentation.swift` — the toast + the bell receipt row. Replaces `ImportCompletionPresentation`.

**Created (Tests):**

- `Tests/TeststripAppTests/LibraryLensTests.swift`
- `Tests/TeststripAppTests/LibrarySourceTests.swift`
- `Tests/TeststripAppTests/UnifiedSidebarPresentationTests.swift`
- `Tests/TeststripAppTests/ScopeLinePresentationTests.swift`
- `Tests/TeststripAppTests/ImportCompletionToastPresentationTests.swift`
- `Tests/TeststripAppTests/ImportSourceScopingTests.swift`
- `Tests/TeststripAppTests/PeopleSourceScopingTests.swift`
- `Tests/TeststripAppTests/MapSourceScopingTests.swift`
- `Tests/TeststripCoreTests/ScopedPeopleQueryTests.swift`
- `Tests/TeststripCoreTests/PreviewFailureAssetIDsTests.swift`
- `Tests/TeststripCoreTests/AssetSetPredicateTests.swift`

**Created (scenarios):**

- `test/scenarios/app-019-lens-shell.md`
- `test/scenarios/import-011-completion-toast-and-import-rows.md`

**Deleted:**

- `Sources/TeststripApp/CullSidebarView.swift` (125 lines — folded into the one sidebar; the Stacks section moves into `UnifiedSidebarPresentation`)
- `Tests/TeststripAppTests/WorkspacePresentationTests.swift` (replaced by `LibraryLensTests.swift`)
- `Tests/TeststripAppTests/ImportCompletionPresentationTests.swift` (replaced by `ImportCompletionToastPresentationTests.swift`)

**Renamed:**

- `Tests/TeststripAppTests/WorkspaceChromePolicyTests.swift` → `Tests/TeststripAppTests/LensChromePolicyTests.swift` (Task 5A)

**Modified (Sources):** `AppModel.swift`, `LibraryGridView.swift`, `main.swift`, `SidebarView.swift`, `CullingKeyCaptureView.swift`, `SessionRestoreState.swift`, `ActivityCenterPresentation.swift`, `ActivityCenterView.swift`, `PeopleView.swift`, `LibraryQueryTokenField.swift`, `LibraryResultHeaderPresentation.swift`, `LoupeZoomView.swift`, `LiveMockupPlaceholder.swift`, `Sources/TeststripCore/Search/SetQuery.swift`, `Sources/TeststripCore/Catalog/CatalogRepository.swift`.

**Modified (Tests):** `AppModelTests.swift`, `AppModelSessionRestoreTests.swift`, `SessionRestoreStateTests.swift`, `SidebarSectionsTests.swift`, `CullSourcePresentationTests.swift`, `AppWindowLayoutTests.swift`, `MenuCoveragePresentationTests.swift`, `CullingKeyCaptureTests.swift`, `InspectorTabsPresentationTests.swift`, `AppModelFilterPersistenceTests.swift`, `CullSubViewSwitchingTests.swift`, `LibraryGridChromeTests.swift`, `PlaceholderTests.swift`, `TimelinePresentationTests.swift`, `ActivityCenterPresentationTests.swift`, `PeoplePresentationTests.swift`.

---

## Sequencing rationale

The hard problem is that `Workspace` is load-bearing in five files and pinned by nine test files, so it cannot be deleted incrementally: the moment `LibraryViewMode.workspace` disappears, `WorkspaceChromePolicy`, `CullingKeyCaptureGate`, `AppWindowLayoutMetrics`, `sidebarSections(for:)`, the sidebar branch in `main.swift`, the ⌘1/⌘2 `Commands`, and `AppMenuCoveragePresentation` all stop compiling at once. **F14 makes this mandatory, not merely convenient:** `MenuCoveragePresentationTests` asserts `workspaceActionIDs == Workspace.allCases.map(\.title)`, so a lens enum that does not land in `AppMenuCoveragePresentation` in the *same* commit turns the suite red.

The plan therefore does **not** try to make the old and new worlds coexist. Instead:

1. **Tasks 1–4 land entirely inside the old world.** They are additive or internal, so each is a green commit that shrinks the cutover:
   - **Task 1** collapses the predicate and renames `ReviewQueue` → `SmartCollection`. The rename spans the `Sources/`–`Tests/` line, so it is the one place the NA/NB split is *forced* to leave the test target uncompilable between the two commits — 1A owns the test half, 1B owns the source half and closes the red in the same pair. Doing it here, first, means every later task's verbatim code spells the domain word one way.
   - **Task 2** adds a repository method and an `AppModel` accessor nothing calls yet except its own tests.
   - **Task 3** adds an optional `assetIDs:` parameter that defaults to today's catalog-wide behaviour and wires `AppModel` to the *already-existing* `currentAssetScopeIDs` scope — no lens or source type is required.
   - **Task 4** adds one `SetQuery` predicate and points `refreshPlaceData` at it. Structurally parallel to Task 3 (additive, nil/absent = today's behaviour), and it must precede the cutover for a concrete reason: Task 7's Selection source and preview-failed import child both mint saved `AssetSet`s, so the moment those exist the Map would silently show the whole catalog for them. Fixing the class before creating new members of it keeps the bug from ever shipping.
2. **Task 5 is one atomic cutover pair (5A tests, 5B implementation).** Its blast-radius checklist is F15, reproduced verbatim in the task: the sidebar branch, `sidebarSections(for:)`, `selectWorkspace`/`lastSubView`, `CullingKeyCaptureGate`, `WorkspaceChromePolicy`, `AppWindowLayoutMetrics.minimumWidth(for:)`, and the `requestFocusSearch`/`requestExport` bounces. `AppMenuCoveragePresentation.lensActionIDs` and the `MenuCoveragePresentationTests` change ride in the same pair (F14). 5A leaves the tree red because it references types that do not exist yet; 5B closes it. No other pair is permitted to interleave.
3. **The bare-key/menu double-dispatch landmine (F14.2) is a hard constraint on Task 5B.** ⌘1–⌘6 are modifier-bearing and safe; `CullingShortcutKey.menuKeyboardShortcut` keeps returning `nil` (`main.swift:569-571`); no lens shortcut may be bare. ⌥⌘1/⌥⌘2/⌥⌘3 stay the inspector-section scrolls (`main.swift:625-630`) — the plan touches neither their bindings nor `InspectorTab.keyEquivalent`.
4. **Tasks 6–10 depend on Task 5's types but not on each other's behaviour**, so each is its own green commit: the sidebar (6), Cull-these + the scope line (7), session restore (8), toast + receipts + banner deletion (9), Timeline scoping (10).
5. **Task 9 must follow Task 5** because "Start culling" is `selectSource(importSession) + selectLens(.cull)` — expressible only once the lens/source API exists. It must also follow Task 6, because the receipt's "the new import row appears in the sidebar with a brief pulse" needs the Imports section to exist.
6. **Tasks 11–14 are documentation and card work.** Task 11 (the LiveMockup 4b rewrite) touches a pinned unit test (`PlaceholderTests.swift:98-107`) and therefore must change source and test in one commit — that is why it is not split. Task 14 (the citation sweep) is the final commit before whole-branch review, as required.
7. **The green rule holds at every pair boundary, with one stated exception inside Task 1**: because a type rename cannot be half-applied, `swift test` does not compile between commits 1A and 1B. Every other NA commit is red only in the ordinary TDD sense (new symbols missing), and every NB commit restores a fully green tree.

---

## Task 1A: One `SetQuery` per smart source, and one word for it — tests (test author)

**Files:**
- Test: **every** file under `Tests/` that names `ReviewQueue`/`reviewQueue` (Step 1's sweep — 119 occurrences at HEAD)
- Test: `Tests/TeststripAppTests/AppModelTests.swift` (add one test region; modify `testSelectingSidebarTargetAppliesReviewQueueWithoutConstructingSidebarRow` at `:6538-6557`, which Step 1 renames)
- Test: `Tests/TeststripAppTests/SessionRestoreStateTests.swift` (`:7-37`, `:120-140`)
- Test: `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift` (`:290-312`)

**Interfaces (what Task 1B must produce — write your tests against exactly these names):**
- `ReviewQueue` is renamed **`SmartCollection`** throughout `Sources/`, and every `reviewQueue…` spelling becomes `smartCollection…`: `ReviewQueuePresentation` → `SmartCollectionPresentation`, `AppModel.reviewQueueCounts` → `smartCollectionCounts`, `applyReviewQueue(_:)` → `applySmartCollection(_:)`, `reviewQueue(forEvaluationKind:)` → `smartCollection(forEvaluationKind:)`, `SidebarRowTarget.reviewQueue(_:)` → `.smartCollection(_:)`. (Spec decision 9: the domain word is "smart collection"; leaving the type called `ReviewQueue` would mean two words for one concept — the same DRY-of-names problem this task exists to fix.)
- `SmartCollection.query: SetQuery` — a computed property on the renamed enum in `TeststripApp`. The **only** expression of each smart source's predicate.
- `SmartCollection` gains `Codable` conformance (needed by Task 5's `LibrarySourceKind`).
- `AppModel.reviewQueueQuery(_:)` is **deleted**; `Self.reviewQueueQuery(.facesFound)` at `AppModel.swift:3492` becomes `SmartCollection.facesFound.query`.
- `AppModel.applySmartCollection(_:)` keeps its signature but sets `detachedLibraryFilterPredicates = collection.query.predicates` instead of the ten-arm filter-property switch.
- `SessionRestoreState` gains `var detachedFilterPredicates: [SetQuery.Predicate]` as its **last** stored property.

**You are the test author. Do not write any file under `Sources/`.** The rename spans both sides of the `Sources/`–`Tests/` line, so you own the test half and Task 1B owns the source half; between the two commits the test target does not compile, which is this task's red.

- [ ] **Step 1: Rename the test half**

Run the two-rule sweep over the test tree, then read the diff before staging it:

```bash
grep -rl "ReviewQueue\|reviewQueue" Tests/
grep -rc "ReviewQueue\|reviewQueue" Tests/ | grep -v ":0"
find Tests -name '*.swift' -print0 | xargs -0 sed -i '' -e 's/ReviewQueue/SmartCollection/g' -e 's/reviewQueue/smartCollection/g'
git diff --stat -- Tests/
```

Expected at HEAD: 119 occurrences across the test tree, concentrated in `AppModelTests.swift`, `CullSourcePresentationTests.swift`, `LibraryResultHeaderTests.swift`, `LibraryQueryTokenTests.swift`, and `SidebarSectionsTests.swift`. Read every hunk: the sweep also renames test *function* names (e.g. `testSelectingSidebarTargetAppliesReviewQueueWithoutConstructingSidebarRow` → `…AppliesSmartCollection…`), which is intended. If any hunk renames something that is not this enum or a name derived from it, revert that hunk by hand and report it.

- [ ] **Step 2: Add the agreement test**

Append to `Tests/TeststripAppTests/AppModelTests.swift`, immediately after `testSelectingSidebarTargetAppliesSmartCollectionWithoutConstructingSidebarRow` (ends `:6557`):

```swift
    // MARK: - Unified shell: one SetQuery per smart source

    // The count shown beside a smart-collection row and the list you get when
    // you click it must come from the SAME expression. They agreed by hand
    // before this change (two switches kept in sync); after it there is only
    // one switch, and this test is what stops a third one appearing.
    func testSmartCollectionCountAndListComeFromTheSamePredicate() throws {
        let pick = makeAsset(id: "smart-pick", path: "/Photos/Smart/pick.jpg", rating: 0, flag: .pick)
        let reject = makeAsset(id: "smart-reject", path: "/Photos/Smart/reject.jpg", rating: 0, flag: .reject)
        let fiveStar = makeAsset(id: "smart-five", path: "/Photos/Smart/five.jpg", rating: 5)
        let plain = makeAsset(id: "smart-plain", path: "/Photos/Smart/plain.jpg", rating: 1)
        let (model, _) = try makeModelWithCatalogAssets(
            named: "smart-source-agreement",
            assets: [pick, reject, fiveStar, plain]
        )

        for queue in SmartCollection.allCases {
            try model.selectSidebarTarget(.smartCollection(queue))
            XCTAssertEqual(
                model.totalAssetCount,
                model.smartCollectionCounts[queue] ?? -1,
                "\(queue) list size disagrees with its sidebar count"
            )
        }
    }

    // Every smart source's predicate is written exactly once, and the click
    // path reaches the catalog through it — not through a parallel set of
    // filter-property mutations.
    func testApplyingASmartCollectionInstallsItsQueryPredicates() throws {
        let flagged = makeAsset(id: "detached-pick", path: "/Photos/Detached/pick.jpg", rating: 0, flag: .pick)
        let (model, _) = try makeModelWithCatalogAssets(named: "smart-source-detached", assets: [flagged])

        try model.selectSidebarTarget(.smartCollection(.likelyIssues))

        XCTAssertEqual(model.selectedView, .grid)
        XCTAssertNil(model.selectedAssetSetID)
        XCTAssertEqual(model.activeLibraryFilterChips, ["Likely Issues"])
    }

    func testEverySmartCollectionHasExactlyOneQuery() {
        XCTAssertEqual(SmartCollection.picks.query, SetQuery(predicates: [.flag(.pick)]))
        XCTAssertEqual(SmartCollection.potentialPicks.query, SetQuery(predicates: [.likelyPick]))
        XCTAssertEqual(SmartCollection.rejects.query, SetQuery(predicates: [.flag(.reject)]))
        XCTAssertEqual(SmartCollection.fiveStars.query, SetQuery(predicates: [.ratingAtLeast(5)]))
        XCTAssertEqual(SmartCollection.needsKeywords.query, SetQuery(predicates: [.missingKeywords]))
        XCTAssertEqual(SmartCollection.needsEvaluation.query, SetQuery(predicates: [.unevaluated]))
        XCTAssertEqual(SmartCollection.facesFound.query, SetQuery(predicates: [.evaluationKind(.faceCount)]))
        XCTAssertEqual(SmartCollection.ocrFound.query, SetQuery(predicates: [.evaluationKind(.ocrText)]))
        XCTAssertEqual(SmartCollection.likelyIssues.query, SetQuery(predicates: [.likelyIssue]))
        XCTAssertEqual(SmartCollection.providerFailures.query, SetQuery(predicates: [.evaluationFailure]))
    }

    // Analysis Failures survives as the tenth Smart Collection (spec decision
    // 8) and keeps feeding the Activity Center's problems badge.
    func testAnalysisFailuresIsASmartCollectionAndStillFeedsTheProblemBadge() throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "smart-source-analysis-failures", assets: [])
        model.smartCollectionCounts = [.providerFailures: 3]

        XCTAssertEqual(SmartCollection.providerFailures.presentation.title, "Analysis Failures")
        XCTAssertEqual(model.activityCenterPresentation.badge, .problems(3))
    }
```

- [ ] **Step 3: Rewrite the one existing test that asserts the duplicate expression**

In `Tests/TeststripAppTests/AppModelTests.swift`, in `testSelectingSidebarTargetAppliesSmartCollectionWithoutConstructingSidebarRow` (`:6538-6557`, renamed by Step 1), replace the line

```swift
        XCTAssertTrue(model.needsEvaluationFilter)
```

with

```swift
        XCTAssertEqual(model.activeLibraryFilterChips, ["Not analyzed yet"])
```

The property is no longer how a smart collection expresses itself; the chip is the user-visible contract and is produced from the predicate.

- [ ] **Step 4: Extend the session-restore round trip**

In `Tests/TeststripAppTests/SessionRestoreStateTests.swift`, add `detachedFilterPredicates:` as the last argument of the `SessionRestoreState(...)` literal in `testRoundTripPreservesAllFields` (`:7-31`):

```swift
            metadataSyncConflictFilter: true,
            detachedFilterPredicates: [.likelyIssue, .importBatch("import-9")]
```

and add the same argument, as `detachedFilterPredicates: []`, to the `minimalState(...)` helper's literal (`:120-140`).

In `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`, add `detachedFilterPredicates: []` as the last argument of the `SessionRestoreState(...)` literal at `:290-312`.

Then add this test to `SessionRestoreStateTests`:

```swift
    // A smart collection is now a set of predicates rather than a bag of
    // boolean filter properties, so the predicates are what has to survive a
    // relaunch — otherwise reopening the app drops you out of the collection.
    func testDetachedPredicatesSurviveTheStoreRoundTrip() throws {
        let defaults = try makeIsolatedDefaults()
        let store = SessionRestoreStore(
            defaults: defaults,
            catalogRoot: URL(fileURLWithPath: "/tmp/catalog-detached", isDirectory: true)
        )
        var state = Self.minimalState(selectedView: .grid, searchText: "")
        state.detachedFilterPredicates = [.evaluationFailure]

        store.save(state)

        XCTAssertEqual(store.load()?.detachedFilterPredicates, [.evaluationFailure])
    }
```

- [ ] **Step 5: Run the tests and verify they fail for the right reason**

Run: `swift test 2>&1 | tail -40`

Expected: **compile failure of the test target** — `cannot find type 'SmartCollection' in scope` (the rename's source half has not landed), plus `value of type 'AppModel' has no member 'smartCollectionCounts'` and `extra argument 'detachedFilterPredicates' in call`. Genuine red.

- [ ] **Step 6: Record the two falsification breaks for Task 1B to execute**

`testSmartCollectionCountAndListComeFromTheSamePredicate` and `testAnalysisFailuresIsASmartCollectionAndStillFeedsTheProblemBadge` would pass against current behaviour — the two predicate expressions agree today, by hand, which is exactly the fragility this task removes. **Their red proofs cannot run in this commit** (the whole test target is uncompilable until the rename's source half lands), so they are executed by Task 1B, whose steps carry them verbatim. Your report must state that, name both breaks, and say which task runs them — a falsification you hand off is still your obligation to specify.

- [ ] **Step 7: Capture the red transcript into your task report**

- [ ] **Step 8: Commit**

```bash
git status
git add Tests/
git commit -m "test: pin one SetQuery per smart collection, and rename the test half (red)"
```

---

## Task 1B: One `SetQuery` per smart source, and one word for it — implementation

**Files:**
- Modify: **every** file under `Sources/` that names `ReviewQueue`/`reviewQueue` (Step 1's sweep — 160 occurrences at HEAD across `AppModel.swift`, `LibraryGridView.swift`, `LibraryResultHeaderPresentation.swift`, `LibraryQueryTokenField.swift`, `SidebarView.swift`, `PeopleView.swift`)
- Modify: `Sources/TeststripApp/AppModel.swift` (`SmartCollection` at `:665-676`, add `query`; delete `reviewQueueQuery(_:)` at `:14272-14295`; `smartCollectionCounts(repository:)` at `:14264-14270`; `applySmartCollection(_:)` at `:11062-11089`; `latestImportFaceReviewAssetCount` at `:3487-3497`; `currentSessionRestoreState()` at `:11787-11814`; `applyRestoredSessionState(_:catalog:)` at `:11827-11875`)
- Modify: `Sources/TeststripApp/SessionRestoreState.swift`

**Interfaces:**
- Consumes: `SetQuery` (`Sources/TeststripCore/Search/SetQuery.swift:17`), `detachedLibraryFilterPredicates` (`AppModel.swift:2363`).
- Produces: `SmartCollection` (the renamed `ReviewQueue`) and every `smartCollection…` spelling; `SmartCollection.query: SetQuery`; `SmartCollection: Codable`; `SessionRestoreState.detachedFilterPredicates: [SetQuery.Predicate]`. Task 2B builds import-scoped queries on `SmartCollection.query`; Task 5B makes `SmartCollection` a `LibrarySourceKind` payload (needs `Codable`); every task after this one spells the domain word one way.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.** Task 1A already renamed the test half; this commit renames the source half and closes the red.

- [ ] **Step 1: Rename the source half**

Spec decision 9: the domain word is "smart collection". `ReviewQueue` is a Copilot-era name for the same ten live queries, and leaving it would mean `LibrarySourceKind.smartCollection(ReviewQueue)` — two words for one concept, which is the same DRY-of-names problem the rest of this task exists to fix. The rename is mechanical and compiler-verified; do it first so every edit below reads in the new vocabulary.

```bash
grep -rc "ReviewQueue\|reviewQueue" --include="*.swift" Sources/ | grep -v ":0"
find Sources -name '*.swift' -print0 | xargs -0 sed -i '' -e 's/ReviewQueue/SmartCollection/g' -e 's/reviewQueue/smartCollection/g'
swift build 2>&1 | tail -20
git diff --stat -- Sources/
```

Expected: 160 occurrences renamed; the build succeeds; `git diff --stat` names exactly the six files above. Read every hunk — if the sweep renamed something that is not this enum or a name derived from it, revert that hunk by hand and report it. Note that the enum's doc comment and `presentation` titles are unaffected: the user-facing strings ("Picks", "Analysis Failures") do not contain the word.

Run `swift test 2>&1 | tail -20`. Expected: **green** — Task 1A already renamed the test half, so this single commit is where both halves meet. The remaining failures are the genuinely-red new tests from Task 1A, which Steps 2–5 close.

- [ ] **Step 2: Add `Codable` and the single query expression to `SmartCollection`**

In `Sources/TeststripApp/AppModel.swift`, change the declaration at `:665`:

```swift
public enum SmartCollection: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
```

Then insert this extension immediately after the `SmartCollection.presentation` extension (which ends at `:713`):

```swift
public extension SmartCollection {
    /// The one and only expression of a smart collection's membership. The
    /// sidebar count, the list you get when you click the row, and every
    /// import-scoped variant are all derived from this — never re-expressed.
    /// A second expression is how the count and the list drift apart.
    var query: SetQuery {
        switch self {
        case .picks:
            return SetQuery(predicates: [.flag(.pick)])
        case .potentialPicks:
            return SetQuery(predicates: [.likelyPick])
        case .rejects:
            return SetQuery(predicates: [.flag(.reject)])
        case .fiveStars:
            return SetQuery(predicates: [.ratingAtLeast(5)])
        case .needsKeywords:
            return SetQuery(predicates: [.missingKeywords])
        case .needsEvaluation:
            return SetQuery(predicates: [.unevaluated])
        case .facesFound:
            return SetQuery(predicates: [.evaluationKind(.faceCount)])
        case .ocrFound:
            return SetQuery(predicates: [.evaluationKind(.ocrText)])
        case .likelyIssues:
            return SetQuery(predicates: [.likelyIssue])
        case .providerFailures:
            return SetQuery(predicates: [.evaluationFailure])
        }
    }
}
```

- [ ] **Step 3: Delete the count-side duplicate and point its caller at `query`**

Delete `private static func smartCollectionQuery(_ collection: SmartCollection) -> SetQuery` in full (`AppModel.swift:14272-14295` — Step 1 renamed it from `reviewQueueQuery`).

In `smartCollectionCounts(repository:)` (`:14264-14270`), change

```swift
            counts[collection] = try repository.assetCount(matching: smartCollectionQuery(collection))
```

to

```swift
            counts[collection] = try repository.assetCount(matching: collection.query)
```

(Step 1's sweep renames the loop's `queue` binding only if it was spelled `reviewQueue`; rename the local to `collection` by hand so the loop reads in the new vocabulary.)

In `latestImportFaceReviewAssetCount(assetIDs:)` (`:3487-3497`), change

```swift
                matching: Self.smartCollectionQuery(.facesFound)
```

to

```swift
                matching: SmartCollection.facesFound.query
```

- [ ] **Step 4: Replace the list-side duplicate**

Replace `applySmartCollection(_:)` (`AppModel.swift:11062-11089`) in full with:

```swift
    private func applySmartCollection(_ collection: SmartCollection) throws {
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        // The smart collection's own predicates, installed as detached filter
        // predicates: `currentLibraryQuery()` folds them into the SQL and
        // `activeLibraryFilterRows` renders them as removable chips, so the
        // list and the sidebar count are two readings of one expression.
        detachedLibraryFilterPredicates = collection.query.predicates
        selectedView = .grid
        try reload()
    }
```

- [ ] **Step 5: Persist the predicates**

In `Sources/TeststripApp/SessionRestoreState.swift`, add as the last stored property of `SessionRestoreState` (after `metadataSyncConflictFilter` at `:35`):

```swift
    /// Predicates installed by a smart-collection selection. Without these a
    /// relaunch drops the user out of the collection they were in, because a
    /// smart collection is no longer expressible as the boolean filter
    /// properties above.
    var detachedFilterPredicates: [SetQuery.Predicate]
```

In `AppModel.currentSessionRestoreState()` (`:11787-11814`), add as the last argument:

```swift
            metadataSyncConflictFilter: metadataSyncConflictFilter,
            detachedFilterPredicates: detachedLibraryFilterPredicates
```

In `AppModel.applyRestoredSessionState(_:catalog:)` (`:11827-11875`), add immediately after the `metadataSyncConflictFilter` assignment (`:11848`):

```swift
        detachedLibraryFilterPredicates = state.detachedFilterPredicates
```

- [ ] **Step 6: Run the new tests and verify they pass**

Run: `swift test --filter TeststripAppTests.AppModelTests 2>&1 | tail -20`
Expected: 0 failures, including the four new tests.

Run: `swift test --filter TeststripAppTests.SessionRestoreStateTests`
Expected: 0 failures.

- [ ] **Step 7: Execute Task 1A's two falsification breaks**

Two of Task 1A's tests pass against behaviour that was already correct-by-hand, so they need a named break to count. Task 1A could not run them — the test target did not compile until Step 1 of this task — so they are yours. **Break `Sources/` only; never touch `Tests/`.**

**(a) Drift between the count and the list.** In `Sources/TeststripApp/AppModel.swift`, inside the `applySmartCollection(_:)` you just wrote, replace

```swift
        detachedLibraryFilterPredicates = collection.query.predicates
```

with

```swift
        detachedLibraryFilterPredicates = SmartCollection.potentialPicks.query.predicates
```

Run `swift test --filter TeststripAppTests.AppModelTests/testSmartCollectionCountAndListComeFromTheSamePredicate`. Expected: the first non-`potentialPicks` iteration fails — the list size disagrees with the sidebar count, which is exactly the drift a second expression of the predicate would cause. Capture the output. Then `git checkout -- Sources/TeststripApp/AppModel.swift`.

**(b) Badge drift.** In `Sources/TeststripApp/AppModel.swift`, in `activityCenterPresentation` (`:3029-3036`), change

```swift
            providerFailureCount: smartCollectionCounts[.providerFailures] ?? 0
```

to

```swift
            providerFailureCount: 0
```

Run `swift test --filter TeststripAppTests.AppModelTests/testAnalysisFailuresIsASmartCollectionAndStillFeedsTheProblemBadge`. Expected: `XCTAssertEqual(model.activityCenterPresentation.badge, .problems(3))` fails with `.none`. Capture the output. Then `git checkout -- Sources/TeststripApp/AppModel.swift`.

Confirm `git diff --stat -- Sources/` shows only your intended Step 1–5 edits before moving on. Both transcripts go in your task report.

- [ ] **Step 8: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds; 0 failures.

- [ ] **Step 9: Commit**

```bash
git status
git add Sources/
git commit -m "refactor: one SetQuery per smart collection, and one domain word for it"
```

---

## Task 2A: Import-scoped child counts — tests (test author)

**Files:**
- Test: `Tests/TeststripCoreTests/PreviewFailureAssetIDsTests.swift` (create)
- Test: `Tests/TeststripAppTests/ImportSourceScopingTests.swift` (create)

**Interfaces (what Task 2B must produce):**
- `CatalogRepository.previewGenerationFailureAssetIDs(assetIDs: [AssetID]) throws -> [AssetID]` — the `SELECT DISTINCT asset_id` twin of `previewGenerationFailureAssetCount(assetIDs:)`, chunked at 500, ordered by `asset_id ASC`.
- `AppModel.importChildCounts(sessionID: WorkSessionID) throws -> ImportChildCounts`
- `public struct ImportChildCounts: Equatable, Sendable { public var stacks: Int; public var skippedFiles: Int; public var previewFailed: Int; public var likelyIssues: Int; public var facesFound: Int; public var isEmpty: Bool }` — declared in `Sources/TeststripApp/UnifiedSidebarPresentation.swift`.
- `AppModel.importSourceSummaries: [ImportSourceSummary]` — `public private(set)`, newest first, filled from `workSessions(kind: .ingest, statuses: [.completed])`.
- `public struct ImportSourceSummary: Equatable, Sendable { public var sessionID: WorkSessionID; public var createdAt: Date; public var detail: String; public var assetCount: Int; public var issues: [WorkSessionIssue]; public var title: String }` — also in `UnifiedSidebarPresentation.swift`; `title` is `"<MMM d> · <detail>"` from `createdAt` + `detail` (F3: `title` and `intent` are both the constant `"Import photos"`).

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the repository test file**

Create `Tests/TeststripCoreTests/PreviewFailureAssetIDsTests.swift`:

```swift
import XCTest
@testable import TeststripCore

// The unified shell's "⚠ Preview failed" import child needs asset identity,
// not just a count: clicking it opens those photos in Grid. The count query
// already exists; this is its DISTINCT-id twin, and the agreement test is what
// keeps the badge number and the list from disagreeing.
final class PreviewFailureAssetIDsTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func recordFailure(_ repository: CatalogRepository, assetID: AssetID, message: String) throws {
        try repository.recordPreviewGenerationFailure(assetID: assetID, level: .grid, errorMessage: message)
    }

    func testReturnsOnlyAssetsWithARecordedPreviewError() throws {
        let repository = try makeRepository(named: "preview-failure-ids")
        let failed = asset(path: "/Photos/failed.cr2")
        let queuedOnly = asset(path: "/Photos/queued.cr2")
        let untouched = asset(path: "/Photos/untouched.cr2")
        try repository.upsert([failed, queuedOnly, untouched])
        try recordFailure(repository, assetID: failed.id, message: "decode failed")
        try repository.recordPreviewGenerationPending(PreviewGenerationItem(assetID: queuedOnly.id, level: .grid))

        let ids = try repository.previewGenerationFailureAssetIDs(
            assetIDs: [failed.id, queuedOnly.id, untouched.id]
        )

        XCTAssertEqual(ids, [failed.id])
    }

    func testEmptyScopeYieldsNoIDs() throws {
        let repository = try makeRepository(named: "preview-failure-ids-empty")

        XCTAssertEqual(try repository.previewGenerationFailureAssetIDs(assetIDs: []), [])
    }

    // The child row's count and the child row's contents must be the same
    // fact read two ways.
    func testIDCountAgreesWithTheExistingFailureCount() throws {
        let repository = try makeRepository(named: "preview-failure-ids-agreement")
        let first = asset(path: "/Photos/a.cr2")
        let second = asset(path: "/Photos/b.cr2")
        let clean = asset(path: "/Photos/c.cr2")
        try repository.upsert([first, second, clean])
        try recordFailure(repository, assetID: first.id, message: "boom")
        try recordFailure(repository, assetID: second.id, message: "boom")
        let scope = [first.id, second.id, clean.id]

        XCTAssertEqual(
            try repository.previewGenerationFailureAssetIDs(assetIDs: scope).count,
            try repository.previewGenerationFailureAssetCount(assetIDs: scope)
        )
    }
}
```

The two seeding APIs used above are verified at HEAD: `recordPreviewGenerationPending(_ item: PreviewGenerationItem)` (`Sources/TeststripCore/Catalog/CatalogRepository.swift:2472`) and `recordPreviewGenerationFailure(assetID:level:errorMessage:)` (`:2498`). `PreviewGenerationItem(assetID:level:)` is at `Sources/TeststripCore/Preview/PreviewGenerationItem.swift:3-11`.

- [ ] **Step 2: Write the import-scoping test file**

Create `Tests/TeststripAppTests/ImportSourceScopingTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// The Imports sidebar section is backed by the existing unbounded
// `workSessions(kind: .ingest, statuses: [.completed])` query — not the
// mixed-kind, limit-10 `recentWork` cache, which cannot promise three imports.
// The row label derives from the session's createdAt plus its `detail`,
// because an import's `title` and `intent` are both the constant
// "Import photos".
final class ImportSourceScopingTests: XCTestCase {
    func testImportSummariesComeFromEveryCompletedIngestSessionNewestFirst() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-summaries", assets: [])
        for index in 0..<12 {
            try repository.save(makeImportSession(
                id: "import-\(index)",
                detail: "Imported from /Cards/CARD-\(index)",
                createdAt: Date(timeIntervalSince1970: TimeInterval(1_000 + index * 100))
            ))
        }
        // A culling session must not appear among the imports.
        try repository.save(WorkSession(
            id: WorkSessionID(rawValue: "cull-1"),
            kind: .culling,
            intent: "Cull the shoot",
            title: "Cull the shoot",
            detail: "Cull the shoot",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            createdAt: Date(timeIntervalSince1970: 9_000),
            updatedAt: Date(timeIntervalSince1970: 9_000)
        ))

        try model.refreshImportSourceSummaries()

        XCTAssertEqual(model.importSourceSummaries.count, 12, "recentWork's limit-10 cache cannot back this section")
        XCTAssertEqual(model.importSourceSummaries.first?.sessionID.rawValue, "import-11")
        XCTAssertFalse(model.importSourceSummaries.contains { $0.sessionID.rawValue == "cull-1" })
    }

    func testImportRowTitleUsesTheSessionDateAndItsFolderDetail() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-title", assets: [])
        try repository.save(makeImportSession(
            id: "import-titled",
            detail: "Imported from /Cards/CARD-A",
            createdAt: Date(timeIntervalSince1970: 1_754_000_000)
        ))

        try model.refreshImportSourceSummaries()

        let summary = try XCTUnwrap(model.importSourceSummaries.first)
        XCTAssertTrue(summary.title.hasSuffix("Imported from /Cards/CARD-A"), summary.title)
        XCTAssertTrue(summary.title.contains(" · "), summary.title)
        XCTAssertNotEqual(summary.title, "Import photos")
    }

    // Import-scoped counts are the smart source's own SetQuery ANDed with
    // `.importBatch(sessionID)` — the shape latestImportFlaggedReviewAssetCount
    // already uses. Never a third expression of the same predicate.
    func testImportChildCountsAreScopedToTheImport() throws {
        let inside = makeAsset(id: "inside", path: "/Photos/Import/inside.jpg", rating: 0)
        let outside = makeAsset(id: "outside", path: "/Photos/Other/outside.jpg", rating: 0)
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "import-child-counts",
            assets: [inside, outside]
        )
        let provenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
        try repository.recordEvaluationSignals([
            EvaluationSignal(assetID: inside.id, kind: .faceCount, value: .score(2), confidence: 0.9, provenance: provenance),
            EvaluationSignal(assetID: outside.id, kind: .faceCount, value: .score(2), confidence: 0.9, provenance: provenance)
        ])
        let sessionID = WorkSessionID(rawValue: "import-scoped")
        let outputSetID = AssetSetID(rawValue: "work-output-import-scoped")
        try repository.upsert(AssetSet.manual(id: outputSetID, name: "Imported", assetIDs: [inside.id]))
        try repository.save(WorkSession(
            id: sessionID,
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: "Imported from /Cards/CARD-A",
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [outputSetID],
            issues: [WorkSessionIssue(kind: .skippedSourceFile, sourceURL: URL(fileURLWithPath: "/Cards/CARD-A/bad.raf"), message: "unsupported")],
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        ))

        let counts = try model.importChildCounts(sessionID: sessionID)

        XCTAssertEqual(counts.facesFound, 1, "the other import's face asset must not count")
        XCTAssertEqual(counts.skippedFiles, 1)
        XCTAssertEqual(counts.previewFailed, 0)
        XCTAssertEqual(counts.likelyIssues, 0)
        XCTAssertFalse(counts.isEmpty)
    }

    func testImportChildCountsAreAllZeroForAnEmptyImport() throws {
        let (model, repository) = try makeModelWithCatalogAssets(named: "import-child-empty", assets: [])
        let sessionID = WorkSessionID(rawValue: "import-empty")
        try repository.save(makeImportSession(
            id: sessionID.rawValue,
            detail: "Imported from /Cards/EMPTY",
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))

        let counts = try model.importChildCounts(sessionID: sessionID)

        XCTAssertTrue(counts.isEmpty)
    }

    // MARK: - Fixtures

    private func makeImportSession(id: String, detail: String, createdAt: Date) -> WorkSession {
        WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: .ingest,
            intent: "Import photos",
            title: "Import photos",
            detail: detail,
            status: .completed,
            inputSetIDs: [],
            outputSetIDs: [],
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    private func makeAsset(id: String, path: String, rating: Int) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(rating + 1), modificationDate: Date(timeIntervalSince1970: TimeInterval(rating + 1))),
            availability: .online,
            metadata: AssetMetadata(rating: rating)
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-import-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
```

- [ ] **Step 3: Run and verify the reds**

Run: `swift test --filter PreviewFailureAssetIDsTests 2>&1 | tail -30`
Expected: **compile failure**, `value of type 'CatalogRepository' has no member 'previewGenerationFailureAssetIDs'`.

Run: `swift test --filter ImportSourceScopingTests 2>&1 | tail -30`
Expected: **compile failure** naming `refreshImportSourceSummaries`, `importSourceSummaries`, and `importChildCounts(sessionID:)` as unknown members.

Both are genuine reds — none of these symbols exists. No falsification step is needed.

- [ ] **Step 4: Capture the red transcripts into your task report**

- [ ] **Step 5: Commit**

```bash
git status
git add Tests/TeststripCoreTests/PreviewFailureAssetIDsTests.swift Tests/TeststripAppTests/ImportSourceScopingTests.swift
git commit -m "test: pin import-scoped child counts and preview-failure identity (red)"
```

---

## Task 2B: Import-scoped child counts — implementation

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (insert after `previewGenerationFailureAssetCount(assetIDs:)`, which ends at `:2641`)
- Create: `Sources/TeststripApp/UnifiedSidebarPresentation.swift`
- Modify: `Sources/TeststripApp/AppModel.swift` (new stored property + two methods; hook into `refreshWorkSessions()` at `:5493-5505`)

**Interfaces:**
- Consumes: `SmartCollection.query` (Task 1B), `Self.chunks(_:size:)` (`CatalogRepository.swift`, used at `:424`, `:2623`), `assetCount(matching:)` (`:1050`), `latestImportOutputAssetIDs(activityID:repository:)` (`AppModel.swift:13007`), `latestImportStacks(activityID:repository:)` (`AppModel.swift:13086`), `workSessions(kind:statuses:)` (`CatalogRepository.swift:2120`).
- Produces: `previewGenerationFailureAssetIDs(assetIDs:)`, `ImportChildCounts`, `ImportSourceSummary`, `AppModel.importSourceSummaries`, `AppModel.refreshImportSourceSummaries()`, `AppModel.importChildCounts(sessionID:)`. Task 6B renders all of them.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Add the DISTINCT-id query**

Insert immediately after `previewGenerationFailureAssetCount(assetIDs:)` in `Sources/TeststripCore/Catalog/CatalogRepository.swift`:

```swift
    /// The assets in `assetIDs` whose preview generation recorded an error —
    /// the identity twin of `previewGenerationFailureAssetCount(assetIDs:)`,
    /// which the unified shell's "⚠ Preview failed" import child needs so it
    /// can open those photos in Grid rather than just badge a number.
    public func previewGenerationFailureAssetIDs(assetIDs: [AssetID]) throws -> [AssetID] {
        guard !assetIDs.isEmpty else { return [] }
        var seenAssetIDs = Set<AssetID>()
        let uniqueAssetIDs = assetIDs.filter { seenAssetIDs.insert($0).inserted }
        var failedAssetIDs: [AssetID] = []
        for chunk in Self.chunks(uniqueAssetIDs, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                """
                SELECT DISTINCT asset_id
                FROM preview_generation_queue
                WHERE asset_id IN (\(placeholders))
                    AND attempt_count > 0
                    AND COALESCE(last_error, '') != ''
                ORDER BY asset_id ASC
                """,
                bindings: chunk.map(\.rawValue)
            )
            for row in rows {
                guard let id = row["asset_id"] else {
                    throw CatalogError.sqlite("preview generation failure row is missing asset_id")
                }
                failedAssetIDs.append(AssetID(rawValue: id))
            }
        }
        return failedAssetIDs
    }
```

- [ ] **Step 2: Create the presentation file with the two value types**

Create `Sources/TeststripApp/UnifiedSidebarPresentation.swift`:

```swift
import Foundation
import TeststripCore

/// One completed import, as the sidebar's Imports section sees it. Built from
/// the persisted `WorkSession` rather than `AppWorkActivity`, which drops both
/// dates — and from the unbounded `workSessions(kind:statuses:)` query rather
/// than the mixed-kind, limit-10 `recentWork` cache, which cannot promise
/// three imports.
public struct ImportSourceSummary: Equatable, Sendable {
    public var sessionID: WorkSessionID
    public var createdAt: Date
    public var detail: String
    public var assetCount: Int
    public var issues: [WorkSessionIssue]

    public init(
        sessionID: WorkSessionID,
        createdAt: Date,
        detail: String,
        assetCount: Int,
        issues: [WorkSessionIssue]
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.detail = detail
        self.assetCount = assetCount
        self.issues = issues
    }

    /// An import's `title` and `intent` are both the constant "Import photos",
    /// so the row label is the session's date plus the source-folder text its
    /// `detail` carries — the only distinguishing field.
    public var title: String {
        let dateText = createdAt.formatted(.dateTime.month(.abbreviated).day())
        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedDetail.isEmpty ? dateText : "\(dateText) · \(trimmedDetail)"
    }
}

/// The counts behind an import row's disclosure children. Each is the smart
/// source's own `SetQuery` ANDed with `.importBatch(sessionID)` — the shape
/// `latestImportFlaggedReviewAssetCount` already uses — so no predicate is
/// ever written a second time.
public struct ImportChildCounts: Equatable, Sendable {
    public var stacks: Int
    public var skippedFiles: Int
    public var previewFailed: Int
    public var likelyIssues: Int
    public var facesFound: Int

    public init(
        stacks: Int = 0,
        skippedFiles: Int = 0,
        previewFailed: Int = 0,
        likelyIssues: Int = 0,
        facesFound: Int = 0
    ) {
        self.stacks = stacks
        self.skippedFiles = skippedFiles
        self.previewFailed = previewFailed
        self.likelyIssues = likelyIssues
        self.facesFound = facesFound
    }

    /// Children render only with nonzero counts, so an all-zero import row
    /// simply has no disclosure triangle.
    public var isEmpty: Bool {
        stacks == 0 && skippedFiles == 0 && previewFailed == 0 && likelyIssues == 0 && facesFound == 0
    }
}
```

- [ ] **Step 3: Add the model accessors**

In `Sources/TeststripApp/AppModel.swift`, add the stored property immediately after `public var starredWork: [AppWorkActivity]` (`:2239`):

```swift
    /// Every completed import, newest first — the Imports sidebar section's
    /// source of truth. Refreshed alongside `recentWork`.
    public private(set) var importSourceSummaries: [ImportSourceSummary] = []
```

Add these two methods immediately after `refreshWorkSessions()` (which ends at `:5505`):

```swift
    /// Rebuilds the Imports section from the unbounded completed-ingest query.
    /// `recentWork` is limit-10 across all thirteen work kinds, so it cannot
    /// promise even the three most recent imports.
    public func refreshImportSourceSummaries() throws {
        guard let catalog else { return }
        let sessions = try catalog.repository.workSessions(kind: .ingest, statuses: [.completed])
        importSourceSummaries = sessions.map { session in
            ImportSourceSummary(
                sessionID: session.id,
                createdAt: session.createdAt,
                detail: session.detail,
                assetCount: session.totalUnitCount ?? session.completedUnitCount,
                issues: session.issues
            )
        }
    }

    /// The counts behind one import row's children. Every query here is a
    /// smart source's own predicate scoped by `.importBatch`, so an
    /// import-scoped count can never drift from its catalog-wide sibling.
    public func importChildCounts(sessionID: WorkSessionID) throws -> ImportChildCounts {
        guard let catalog else { return ImportChildCounts() }
        let repository = catalog.repository
        let session = try repository.session(id: sessionID)
        let assetIDs = try latestImportOutputAssetIDs(activityID: sessionID.rawValue, repository: repository)
        return ImportChildCounts(
            stacks: try latestImportStacks(activityID: sessionID.rawValue, repository: repository).count,
            skippedFiles: session.issues.filter { $0.kind == .skippedSourceFile }.count,
            previewFailed: try repository.previewGenerationFailureAssetIDs(assetIDs: assetIDs).count,
            likelyIssues: try repository.assetCount(
                matching: SetQuery(predicates: [.importBatch(sessionID.rawValue)] + SmartCollection.likelyIssues.query.predicates)
            ),
            facesFound: try repository.assetCount(
                matching: SetQuery(predicates: [.importBatch(sessionID.rawValue)] + SmartCollection.facesFound.query.predicates)
            )
        )
    }
```

- [ ] **Step 4: Keep the summaries fresh**

In `refreshWorkSessions()` (`:5493-5505`), add immediately before `refreshLatestImportPresentation()`:

```swift
        try refreshImportSourceSummaries()
```

- [ ] **Step 5: Run the new tests and verify they pass**

Run: `swift test --filter PreviewFailureAssetIDsTests && swift test --filter ImportSourceScopingTests`
Expected: 0 failures in both.

- [ ] **Step 6: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds; 0 failures.

- [ ] **Step 7: Commit**

```bash
git status
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripApp/UnifiedSidebarPresentation.swift Sources/TeststripApp/AppModel.swift
git commit -m "feat: import-scoped child counts derived from each smart source's query"
```

---

## Task 3A: People respects the source — tests (test author)

**Files:**
- Test: `Tests/TeststripCoreTests/ScopedPeopleQueryTests.swift` (create)
- Test: `Tests/TeststripAppTests/PeopleSourceScopingTests.swift` (create)

**Interfaces (what Task 3B must produce):**
- `CatalogRepository.people(assetIDs: [AssetID]? = nil) throws -> [CatalogPerson]` — `nil` keeps today's catalog-wide behaviour; a non-nil scope returns only people with at least one asset in the scope, with `assetCount` counted **within** the scope.
- `CatalogRepository.unassignedFaceObservations(provenance: ProviderProvenance, limit: Int, assetIDs: [AssetID]? = nil) throws -> [CatalogFaceObservation]`
- `CatalogRepository.faceObservationAssetCount(provenance: ProviderProvenance, assetIDs: [AssetID]? = nil) throws -> Int`
- `AppModel.peopleScopeAssetIDs() throws -> [AssetID]?` — `nil` when the source is All Photos (no set, no query); otherwise `currentAssetScopeIDs(repository:)`.
- `AppModel.peopleInCurrentSource: [CatalogPerson]` — `public private(set)`, refreshed by `refreshPeopleFaceSuggestions()`. **`catalogPeople` stays catalog-wide** — it backs naming, merging, and autocomplete, which must reach people outside the current source.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the repository test file**

Create `Tests/TeststripCoreTests/ScopedPeopleQueryTests.swift`:

```swift
import XCTest
@testable import TeststripCore

// "People over an import is who's in this shoot; People × All Photos is the
// global queue." Not one of the sixteen people/face reads accepted an asset
// scope before this change — these three now do, with nil meaning
// catalog-wide so every existing caller is unchanged.
final class ScopedPeopleQueryTests: XCTestCase {
    private let provenance = ProviderProvenance(
        provider: "face-recognition",
        model: "auraface-v1",
        version: "1",
        settingsHash: "default"
    )

    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func seedFace(_ repository: CatalogRepository, assetID: AssetID, embedding: [Double]) throws {
        try repository.replaceFaceObservations(
            assetID: assetID,
            provenance: provenance,
            with: [
                CatalogFaceObservation(
                    assetID: assetID,
                    faceIndex: 0,
                    boundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    captureQuality: 0.9,
                    embedding: embedding,
                    provenance: provenance
                )
            ]
        )
    }

    func testPeopleScopedToASubsetOnlyReturnsPeoplePresentInIt() throws {
        let repository = try makeRepository(named: "scoped-people")
        let shootFrame = asset(path: "/Photos/Shoot/a.jpg")
        let otherFrame = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([shootFrame, otherFrame])
        try repository.upsertPerson(id: "person-shoot", name: "Ada")
        try repository.upsertPerson(id: "person-other", name: "Grace")
        try repository.assignAssets([shootFrame.id], toPersonID: "person-shoot")
        try repository.assignAssets([otherFrame.id], toPersonID: "person-other")

        let scoped = try repository.people(assetIDs: [shootFrame.id])

        XCTAssertEqual(scoped.map(\.id), ["person-shoot"])
        XCTAssertEqual(scoped.first?.assetCount, 1)
    }

    func testPeopleWithNilScopeIsUnchangedCatalogWideBehaviour() throws {
        let repository = try makeRepository(named: "scoped-people-nil")
        let first = asset(path: "/Photos/Shoot/a.jpg")
        let second = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([first, second])
        try repository.upsertPerson(id: "person-a", name: "Ada")
        try repository.assignAssets([first.id, second.id], toPersonID: "person-a")

        XCTAssertEqual(try repository.people(assetIDs: nil), try repository.people())
        XCTAssertEqual(try repository.people().first?.assetCount, 2)
    }

    func testPeopleScopedToAnEmptyScopeReturnsNobody() throws {
        let repository = try makeRepository(named: "scoped-people-empty")
        let frame = asset(path: "/Photos/Shoot/a.jpg")
        try repository.upsert(frame)
        try repository.upsertPerson(id: "person-a", name: "Ada")
        try repository.assignAssets([frame.id], toPersonID: "person-a")

        XCTAssertEqual(try repository.people(assetIDs: []), [])
    }

    func testUnassignedFaceObservationsHonourTheScope() throws {
        let repository = try makeRepository(named: "scoped-unassigned-faces")
        let shootFrame = asset(path: "/Photos/Shoot/a.jpg")
        let otherFrame = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([shootFrame, otherFrame])
        try seedFace(repository, assetID: shootFrame.id, embedding: [0.1, 0.2, 0.3])
        try seedFace(repository, assetID: otherFrame.id, embedding: [0.9, 0.8, 0.7])

        let scoped = try repository.unassignedFaceObservations(
            provenance: provenance,
            limit: 100,
            assetIDs: [shootFrame.id]
        )
        let global = try repository.unassignedFaceObservations(provenance: provenance, limit: 100)

        XCTAssertEqual(scoped.map(\.assetID), [shootFrame.id])
        XCTAssertEqual(Set(global.map(\.assetID)), Set([shootFrame.id, otherFrame.id]))
    }

    func testScopedUnassignedFaceObservationsStillRespectTheLimit() throws {
        let repository = try makeRepository(named: "scoped-unassigned-limit")
        var ids: [AssetID] = []
        for index in 0..<5 {
            let frame = asset(path: "/Photos/Shoot/\(index).jpg")
            try repository.upsert(frame)
            try seedFace(repository, assetID: frame.id, embedding: [Double(index), 0.2, 0.3])
            ids.append(frame.id)
        }

        let scoped = try repository.unassignedFaceObservations(provenance: provenance, limit: 2, assetIDs: ids)

        XCTAssertEqual(scoped.count, 2)
    }

    func testFaceObservationAssetCountHonoursTheScope() throws {
        let repository = try makeRepository(named: "scoped-face-count")
        let shootFrame = asset(path: "/Photos/Shoot/a.jpg")
        let otherFrame = asset(path: "/Photos/Other/b.jpg")
        try repository.upsert([shootFrame, otherFrame])
        try seedFace(repository, assetID: shootFrame.id, embedding: [0.1, 0.2, 0.3])
        try seedFace(repository, assetID: otherFrame.id, embedding: [0.9, 0.8, 0.7])

        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance, assetIDs: [shootFrame.id]), 1)
        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance), 2)
        XCTAssertEqual(try repository.faceObservationAssetCount(provenance: provenance, assetIDs: []), 0)
    }
}
```

- [ ] **Step 2: Write the model-level test file**

Create `Tests/TeststripAppTests/PeopleSourceScopingTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// No lens ignores the nouns: the People lens over a narrowed source shows that
// source's people and that source's grouping queue. All Photos is the global
// queue, and naming/merge identity stays catalog-wide so a photographer can
// still name someone who is not in the current shoot.
final class PeopleSourceScopingTests: XCTestCase {
    func testPeopleScopeIsNilForAnUnfilteredCatalog() throws {
        let first = makeAsset(id: "scope-a", path: "/Photos/A/a.jpg")
        let second = makeAsset(id: "scope-b", path: "/Photos/B/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "people-scope-nil", assets: [first, second])

        XCTAssertNil(try model.peopleScopeAssetIDs())
    }

    func testPeopleScopeNarrowsWithTheSelectedSource() throws {
        let inside = makeAsset(id: "scope-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "scope-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(
            named: "people-scope-folder",
            assets: [inside, outside]
        )

        try model.selectSidebarTarget(.folder("/Photos/Inside"))

        XCTAssertEqual(try model.peopleScopeAssetIDs(), [inside.id])
    }

    func testPeopleInCurrentSourceOnlyListsPeopleInThatSource() throws {
        let inside = makeAsset(id: "people-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "people-outside", path: "/Photos/Outside/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "people-in-source",
            assets: [inside, outside]
        )
        try repository.upsertPerson(id: "person-inside", name: "Ada")
        try repository.upsertPerson(id: "person-outside", name: "Grace")
        try repository.assignAssets([inside.id], toPersonID: "person-inside")
        try repository.assignAssets([outside.id], toPersonID: "person-outside")

        try model.selectSidebarTarget(.folder("/Photos/Inside"))
        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(model.peopleInCurrentSource.map(\.name), ["Ada"])
        // Identity stays catalog-wide: naming and merging must still see Grace.
        XCTAssertEqual(Set(model.catalogPeople.map(\.name)), Set(["Ada", "Grace"]))
    }

    func testPeopleOverAllPhotosIsTheGlobalQueue() throws {
        let inside = makeAsset(id: "global-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "global-outside", path: "/Photos/Outside/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "people-global",
            assets: [inside, outside]
        )
        try repository.upsertPerson(id: "person-inside", name: "Ada")
        try repository.upsertPerson(id: "person-outside", name: "Grace")
        try repository.assignAssets([inside.id], toPersonID: "person-inside")
        try repository.assignAssets([outside.id], toPersonID: "person-outside")

        try model.selectSidebarTarget(.folder("/Photos/Inside"))
        model.refreshPeopleFaceSuggestions()
        try model.selectSidebarTarget(.allPhotographs)
        model.refreshPeopleFaceSuggestions()

        XCTAssertEqual(Set(model.peopleInCurrentSource.map(\.name)), Set(["Ada", "Grace"]))
    }

    // MARK: - Fixtures

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-people-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
```

- [ ] **Step 3: Run and verify the reds**

Run: `swift test --filter ScopedPeopleQueryTests 2>&1 | tail -30`
Expected: **compile failure**, `extra argument 'assetIDs' in call` on `people(assetIDs:)`, `unassignedFaceObservations(provenance:limit:assetIDs:)`, and `faceObservationAssetCount(provenance:assetIDs:)`.

Run: `swift test --filter PeopleSourceScopingTests 2>&1 | tail -30`
Expected: **compile failure**, `value of type 'AppModel' has no member 'peopleScopeAssetIDs'` / `'peopleInCurrentSource'`.

Both genuine reds. No falsification step is needed.

- [ ] **Step 4: Capture the red transcripts into your task report**

- [ ] **Step 5: Commit**

```bash
git status
git add Tests/TeststripCoreTests/ScopedPeopleQueryTests.swift Tests/TeststripAppTests/PeopleSourceScopingTests.swift
git commit -m "test: pin source-scoped People reads (red)"
```

---

## Task 3B: People respects the source — implementation

**Files:**
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (`people()` `:1238-1255`, `unassignedFaceObservations(provenance:limit:)` `:1423-1462`, `faceObservationAssetCount(provenance:)` `:1690-1700`)
- Modify: `Sources/TeststripApp/AppModel.swift` (`refreshPeopleFaceSuggestions()` `:3833-3861`, `reload()` `:10870-10913`, new property + `peopleScopeAssetIDs()`)
- Modify: `Sources/TeststripApp/PeopleView.swift` (`presentation` `:18-29`)

**Interfaces:**
- Consumes: `currentAssetScopeIDs(repository:includeBondedSecondaries:)` (`AppModel.swift:12542`), `selectedExplicitAssetIDs`, `currentLibraryQuery()` (`:11663`), `Self.chunks(_:size:)`.
- Produces: the three scoped repository overloads, `AppModel.peopleScopeAssetIDs()`, `AppModel.peopleInCurrentSource`.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Scope `people()`**

Replace `people()` (`CatalogRepository.swift:1238-1255`) in full with:

```swift
    /// Confirmed people. `assetIDs == nil` is catalog-wide (the People lens
    /// over All Photos); a non-nil scope answers "who is in this shoot" — only
    /// people with at least one asset in the scope, counted within it.
    public func people(assetIDs: [AssetID]? = nil) throws -> [CatalogPerson] {
        guard let assetIDs else {
            return try decodePeople(try database.rows(Self.peopleSQL(scoped: false)))
        }
        guard !assetIDs.isEmpty else { return [] }
        var countsByPerson: [String: Int] = [:]
        var namesByPerson: [String: String] = [:]
        for chunk in Self.chunks(assetIDs, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                Self.peopleSQL(scoped: true, placeholders: placeholders),
                bindings: chunk.map(\.rawValue)
            )
            for person in try decodePeople(rows) {
                namesByPerson[person.id] = person.name
                countsByPerson[person.id, default: 0] += person.assetCount
            }
        }
        return countsByPerson
            .compactMap { id, count -> CatalogPerson? in
                guard count > 0, let name = namesByPerson[id] else { return nil }
                return CatalogPerson(id: id, name: name, assetCount: count)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Load-bearing, not merely defensive: evaluation's AI path
    // (insertAIFace) doesn't write a person_assets row for a bonded
    // secondary, but a user confirming a secondary's own face suggestion
    // (confirmFace) does — the bonded_to_asset_id guard is what keeps that
    // confirmed secondary from inflating a person's count, matching the
    // folder/timeline/place/coverage/source-root aggregates.
    private static func peopleSQL(scoped: Bool, placeholders: String = "") -> String {
        let scopeClause = scoped ? " AND person_assets.asset_id IN (\(placeholders))" : ""
        return """
        SELECT people.id, people.name, COUNT(assets.id) AS asset_count
        FROM people
        LEFT JOIN person_assets ON person_assets.person_id = people.id\(scopeClause)
        LEFT JOIN assets ON assets.id = person_assets.asset_id AND assets.bonded_to_asset_id IS NULL
        GROUP BY people.id, people.name
        ORDER BY people.name COLLATE NOCASE ASC
        """
    }

    private func decodePeople(_ rows: [[String: String]]) throws -> [CatalogPerson] {
        try rows.map { row in
            guard let id = row["id"], let name = row["name"], let countString = row["asset_count"], let assetCount = Int(countString) else {
                throw CatalogError.sqlite("person row is missing required columns")
            }
            return CatalogPerson(id: id, name: name, assetCount: assetCount)
        }
    }
```

- [ ] **Step 2: Scope `unassignedFaceObservations`**

Replace `unassignedFaceObservations(provenance:limit:)` (`CatalogRepository.swift:1423-1462`) in full with:

```swift
    // Backs People's suggestion/review queue and the AI auto-apply promoter
    // (both of which surface faces for a person to be matched against or
    // confirmed). Both files of a bonded pair are independently evaluated
    // (secondaries aren't special-cased out of the eval queue), so without
    // the bonded_to_asset_id exclusion a RAW+JPEG pair's pixel-identical
    // face would surface twice; the primary's own observation already
    // covers the shot.
    //
    // `assetIDs == nil` is catalog-wide (People × All Photos, the global
    // grouping queue); a non-nil scope is the shoot the user is looking at.
    public func unassignedFaceObservations(
        provenance: ProviderProvenance,
        limit: Int,
        assetIDs: [AssetID]? = nil
    ) throws -> [CatalogFaceObservation] {
        let provenanceBindings = [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
        guard let assetIDs else {
            let rows = try database.rows(
                Self.unassignedFaceObservationsSQL(scopeClause: ""),
                bindings: provenanceBindings + ["\(limit)"]
            )
            return try rows.map(decodeFaceObservation)
        }
        guard !assetIDs.isEmpty, limit > 0 else { return [] }
        var observations: [CatalogFaceObservation] = []
        for chunk in Self.chunks(assetIDs, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                Self.unassignedFaceObservationsSQL(scopeClause: "\n  AND face_observations.asset_id IN (\(placeholders))"),
                bindings: provenanceBindings + chunk.map(\.rawValue) + ["\(limit)"]
            )
            observations.append(contentsOf: try rows.map(decodeFaceObservation))
        }
        return Array(observations.prefix(limit))
    }

    private static func unassignedFaceObservationsSQL(scopeClause: String) -> String {
        """
        SELECT asset_id, face_index, face_json, provenance_json
        FROM face_observations
        WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?\(scopeClause)
          AND NOT EXISTS (
              SELECT 1 FROM assets
              WHERE assets.id = face_observations.asset_id
                AND assets.bonded_to_asset_id IS NOT NULL
          )
          AND NOT EXISTS (
              SELECT 1 FROM person_faces
              WHERE person_faces.asset_id = face_observations.asset_id
                AND person_faces.face_index = face_observations.face_index
          )
          AND NOT EXISTS (
              SELECT 1 FROM person_assets
              WHERE person_assets.asset_id = face_observations.asset_id
                AND NOT EXISTS (
                    SELECT 1 FROM person_faces
                    WHERE person_faces.asset_id = face_observations.asset_id
                )
          )
          AND NOT EXISTS (
              SELECT 1 FROM dismissed_faces
              WHERE dismissed_faces.asset_id = face_observations.asset_id
                AND dismissed_faces.face_index = face_observations.face_index
          )
          AND NOT EXISTS (
              SELECT 1 FROM dismissed_face_assets
              WHERE dismissed_face_assets.asset_id = face_observations.asset_id
          )
        ORDER BY created_at DESC, asset_id ASC, face_index ASC
        LIMIT ?
        """
    }
```

- [ ] **Step 3: Scope `faceObservationAssetCount`**

Replace `faceObservationAssetCount(provenance:)` (`CatalogRepository.swift:1690-1700`) in full with:

```swift
    public func faceObservationAssetCount(
        provenance: ProviderProvenance,
        assetIDs: [AssetID]? = nil
    ) throws -> Int {
        let provenanceBindings = [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
        guard let assetIDs else {
            let rows = try database.rows(
                """
                SELECT COUNT(DISTINCT asset_id) AS asset_count
                FROM face_observations
                WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?
                """,
                bindings: provenanceBindings
            )
            return rows.first.flatMap { $0["asset_count"] }.flatMap(Int.init) ?? 0
        }
        guard !assetIDs.isEmpty else { return 0 }
        // Chunks are disjoint sets of asset ids, so per-chunk DISTINCT counts
        // sum without double counting.
        var count = 0
        for chunk in Self.chunks(assetIDs, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                """
                SELECT COUNT(DISTINCT asset_id) AS asset_count
                FROM face_observations
                WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?
                  AND asset_id IN (\(placeholders))
                """,
                bindings: provenanceBindings + chunk.map(\.rawValue)
            )
            count += rows.first.flatMap { $0["asset_count"] }.flatMap(Int.init) ?? 0
        }
        return count
    }
```

- [ ] **Step 4: Thread the scope through `AppModel`**

Add the stored property immediately after `public private(set) var peopleFaceObservationAssetCount = 0` (`AppModel.swift:2392`):

```swift
    /// The people present in the currently selected source — what the People
    /// lens lists. `catalogPeople` stays catalog-wide on purpose: naming,
    /// merging, and autocomplete must still reach a person who isn't in this
    /// shoot.
    public private(set) var peopleInCurrentSource: [CatalogPerson] = []
```

Add this method immediately before `refreshPeopleFaceSuggestions()` (`:3833`):

```swift
    /// The asset scope every People read runs against. `nil` means the whole
    /// catalog — the People × All Photos global queue — and avoids materializing
    /// every asset id just to hand it back as an `IN` list.
    public func peopleScopeAssetIDs() throws -> [AssetID]? {
        guard let catalog else { return nil }
        guard selectedExplicitAssetIDs != nil || currentLibraryQuery() != nil else { return nil }
        return try currentAssetScopeIDs(repository: catalog.repository)
    }
```

In `refreshPeopleFaceSuggestions()` (`:3833-3861`), change the body's opening so the scope is computed once and passed to all three reads:

```swift
    public func refreshPeopleFaceSuggestions() {
        guard let catalog else { return }
        do {
            let provenance = AppleVisionEvaluationProvider.faceProvenance
            let scopeAssetIDs = try peopleScopeAssetIDs()
            let unassigned = try catalog.repository.unassignedFaceObservations(
                provenance: provenance,
                limit: Self.maximumFaceSuggestionInputCount,
                assetIDs: scopeAssetIDs
            )
```

and change the two tail statements (`:3857`) to:

```swift
            peopleFaceObservationAssetCount = try catalog.repository.faceObservationAssetCount(
                provenance: provenance,
                assetIDs: scopeAssetIDs
            )
            peopleInCurrentSource = try catalog.repository.people(assetIDs: scopeAssetIDs)
```

Leave every other line of the method untouched.

- [ ] **Step 5: Re-scope People whenever the source reloads**

In `reload()` (`AppModel.swift:10870-10913`), add immediately before the final closing brace of the method (after the `if selectedView == .map { try refreshPlaceData() }` block at `:10910-10912`):

```swift
        // The People lens is source-scoped like every other lens, and `reload()`
        // is the single funnel every source change passes through.
        if selectedView == .people {
            refreshPeopleFaceSuggestions()
        }
```

Add the same three lines immediately before the `return` inside the explicit-ID short-circuit branch (`:10885-10894`), right after its `if selectedView == .map { try refreshPlaceData() }`.

- [ ] **Step 6: Point the People view at the scoped list**

In `Sources/TeststripApp/PeopleView.swift`, in `presentation` (`:18-29`), change

```swift
            namedPeople: model.catalogPeople,
```

to

```swift
            namedPeople: model.peopleInCurrentSource,
```

- [ ] **Step 7: Run the new tests and verify they pass**

Run: `swift test --filter ScopedPeopleQueryTests && swift test --filter PeopleSourceScopingTests`
Expected: 0 failures in both.

- [ ] **Step 8: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds; 0 failures. `PeoplePresentationTests` compiles unchanged — it constructs `PeoplePresentation` directly and never reads `AppModel.catalogPeople`.

- [ ] **Step 9: Commit**

```bash
git status
git add Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/PeopleView.swift
git commit -m "feat: People reads honour the selected source"
```

---

## Task 4A: Map respects an explicit-ID source — tests (test author)

**Files:**
- Test: `Tests/TeststripCoreTests/AssetSetPredicateTests.swift` (create)
- Test: `Tests/TeststripAppTests/MapSourceScopingTests.swift` (create)

**Interfaces (what Task 4B must produce):**
- `SetQuery.Predicate.assetSet(AssetSetID)` — a new predicate matching the **static** membership (`.manual` / `.snapshot`) of one saved set, compiled with the same `json_each(asset_sets.membership_json, …)` technique `.importBatch` and `.workSession` already use. A `.dynamic` set matches nothing through this predicate: its query already reaches SQL through `selectedDynamicSetQuery`.
- `AppModel.currentMapQuery() -> SetQuery?` — `currentLibraryQuery()`'s predicates plus `.assetSet(id)` when the selected set has static membership.
- `AppModel.refreshPlaceData(bounds:cellSize:)` passes `currentMapQuery()` to all three map reads.

**Design note for the implementer — read this before you write the tests.** The spec's behaviour change 11 asks for the Map to be scoped for explicit-ID sources. The obvious route is three `assetIDs:`-taking overloads of `placeClusters` / `topLocations` / `geotaggedCoverage`, mirroring Task 3's People overloads. **That route is rejected, deliberately**, for two reasons: (1) those three reads are *aggregates*, so an `IN`-list scope has to be chunked at 500 like every other id list in this repository, and merging chunked results is unsound for `topLocations` — a location that sits just below the `LIMIT` cut in every chunk can still be the top location overall — and error-prone for `placeClusters`, whose cluster centroids are averages that would need re-weighting across chunks. (2) Every explicit-ID scope the new shell can produce is a saved `AssetSet` (`selectedExplicitAssetIDs` is derived from `selectedAssetSet`; the Selection source and the preview-failed import child both mint real sets), so one predicate fixes the whole class through the `matching:` parameter that already exists — no chunking, no merging, and every other query surface gets set-scoping for free. This is the smaller change and the DRY one.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the predicate test file**

Create `Tests/TeststripCoreTests/AssetSetPredicateTests.swift`:

```swift
import XCTest
@testable import TeststripCore

// A saved set with static membership had no query form, so every read that
// takes a `SetQuery` silently saw the whole catalog for it — which is why the
// Map lens showed every geotagged photo while the grid below showed six.
// This predicate is the missing form, built the same way `.importBatch` and
// `.workSession` already resolve set membership.
final class AssetSetPredicateTests: XCTestCase {
    private func makeRepository(named name: String) throws -> CatalogRepository {
        let directory = try TestDirectories.makeTemporaryDirectory(named: name)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        return CatalogRepository(database: database)
    }

    private func asset(path: String) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    func testAManualSetsMembersMatchThePredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-manual")
        let inSet = asset(path: "/Photos/in.jpg")
        let outOfSet = asset(path: "/Photos/out.jpg")
        try repository.upsert([inSet, outOfSet])
        let setID = AssetSetID(rawValue: "keepers")
        try repository.upsert(AssetSet.manual(id: setID, name: "Keepers", assetIDs: [inSet.id]))

        let matched = try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)]))

        XCTAssertEqual(matched, [inSet.id])
    }

    func testASnapshotSetsMembersMatchThePredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-snapshot")
        let inSet = asset(path: "/Photos/in.jpg")
        let outOfSet = asset(path: "/Photos/out.jpg")
        try repository.upsert([inSet, outOfSet])
        let setID = AssetSetID(rawValue: "frozen")
        try repository.upsert(AssetSet(id: setID, name: "Frozen", membership: .snapshot([inSet.id])))

        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)])),
            [inSet.id]
        )
    }

    // A dynamic set's membership is its query, which already reaches SQL
    // through `selectedDynamicSetQuery`; this predicate is only about static
    // membership, and must not silently match everything.
    func testADynamicSetMatchesNothingThroughThisPredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-dynamic")
        let only = asset(path: "/Photos/only.jpg")
        try repository.upsert(only)
        let setID = AssetSetID(rawValue: "dyn")
        try repository.upsert(AssetSet.dynamic(id: setID, name: "Dyn", query: SetQuery(predicates: [.flag(.pick)])))

        XCTAssertEqual(try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID)])), [])
    }

    func testAnUnknownSetIDMatchesNothing() throws {
        let repository = try makeRepository(named: "asset-set-predicate-unknown")
        try repository.upsert(asset(path: "/Photos/only.jpg"))

        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(AssetSetID(rawValue: "nope"))])),
            []
        )
    }

    // Predicates are implicitly AND-ed, so a set scope composes with a filter
    // exactly the way the Map's bounds + query already compose.
    func testThePredicateComposesWithOtherPredicates() throws {
        let repository = try makeRepository(named: "asset-set-predicate-compose")
        let picked = asset(path: "/Photos/picked.jpg")
        let unpicked = asset(path: "/Photos/unpicked.jpg")
        try repository.upsert([picked, unpicked])
        try repository.updateMetadata(assetID: picked.id) { metadata in
            metadata.flag = .pick
        }
        let setID = AssetSetID(rawValue: "both")
        try repository.upsert(AssetSet.manual(id: setID, name: "Both", assetIDs: [picked.id, unpicked.id]))

        XCTAssertEqual(
            try repository.assetIDs(matching: SetQuery(predicates: [.assetSet(setID), .flag(.pick)])),
            [picked.id]
        )
    }

    // The three map aggregates take the same `matching:` parameter every other
    // read does, so scoping them needs no new overload.
    func testTheMapAggregatesHonourTheSetPredicate() throws {
        let repository = try makeRepository(named: "asset-set-predicate-map")
        let inSet = geotagged(path: "/Photos/in.jpg", latitude: 10, longitude: 20)
        let outOfSet = geotagged(path: "/Photos/out.jpg", latitude: 40, longitude: 50)
        try repository.upsert([inSet, outOfSet])
        let setID = AssetSetID(rawValue: "map-set")
        try repository.upsert(AssetSet.manual(id: setID, name: "Map Set", assetIDs: [inSet.id]))
        let scope = SetQuery(predicates: [.assetSet(setID)])

        let coverage = try repository.geotaggedCoverage(matching: scope)
        let clusters = try repository.placeClusters(bounds: nil, cellSize: 10, matching: scope)

        XCTAssertEqual(coverage.totalCount, 1)
        XCTAssertEqual(coverage.geotaggedCount, 1)
        XCTAssertEqual(clusters.map(\.assetCount).reduce(0, +), 1)
    }

    private func geotagged(path: String, latitude: Double, longitude: Double) -> Asset {
        Asset(
            id: .new(),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: nil,
            fingerprint: FileFingerprint(size: 100, modificationDate: Date(timeIntervalSince1970: 1), contentHash: nil),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 100,
                pixelHeight: 100,
                latitude: latitude,
                longitude: longitude,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }
}
```

The fixture's labels are verified at HEAD: `AssetTechnicalMetadata.init` (`Sources/TeststripCore/Domain/Metadata.swift:225-…`) declares `pixelWidth`, `pixelHeight`, and `provenance` as required, with `latitude`/`longitude`/`capturedAt` among the defaulted optionals — the call above compiles as written.

- [ ] **Step 2: Write the model-level test file**

Create `Tests/TeststripAppTests/MapSourceScopingTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Spec behaviour change 11: the Map lens showed the whole catalog whenever the
// source was a saved static set or the Selection, because those scopes lived
// only in `selectedExplicitAssetIDs` and never became a `SetQuery`.
final class MapSourceScopingTests: XCTestCase {
    func testMapScopesToASelectedStaticSet() throws {
        let inSet = makeGeotaggedAsset(id: "map-in", path: "/Photos/in.jpg", latitude: 10, longitude: 20)
        let outOfSet = makeGeotaggedAsset(id: "map-out", path: "/Photos/out.jpg", latitude: 40, longitude: 50)
        let (model, repository) = try makeModelWithCatalogAssets(named: "map-static-set", assets: [inSet, outOfSet])
        let setID = AssetSetID(rawValue: "map-keepers")
        try repository.upsert(AssetSet.manual(id: setID, name: "Keepers", assetIDs: [inSet.id]))
        try model.refreshSavedAssetSets()

        try model.applyAssetSet(id: setID)
        try model.refreshPlaceData()

        XCTAssertEqual(model.geotaggedCoverage.totalCount, 1)
        XCTAssertEqual(model.catalogPlaceClusters.map(\.assetCount).reduce(0, +), 1)
    }

    func testMapCoversTheWholeCatalogOnAllPhotos() throws {
        let first = makeGeotaggedAsset(id: "map-all-a", path: "/Photos/a.jpg", latitude: 10, longitude: 20)
        let second = makeGeotaggedAsset(id: "map-all-b", path: "/Photos/b.jpg", latitude: 40, longitude: 50)
        let (model, _) = try makeModelWithCatalogAssets(named: "map-all-photos", assets: [first, second])

        try model.refreshPlaceData()

        XCTAssertEqual(model.geotaggedCoverage.totalCount, 2)
        XCTAssertEqual(model.catalogPlaceClusters.map(\.assetCount).reduce(0, +), 2)
    }

    func testTheMapQueryComposesASetScopeWithAnActiveFilter() throws {
        let picked = makeGeotaggedAsset(id: "map-picked", path: "/Photos/picked.jpg", latitude: 10, longitude: 20)
        let unpicked = makeGeotaggedAsset(id: "map-unpicked", path: "/Photos/unpicked.jpg", latitude: 11, longitude: 21)
        let (model, repository) = try makeModelWithCatalogAssets(named: "map-compose", assets: [picked, unpicked])
        try repository.updateMetadata(assetID: picked.id) { metadata in
            metadata.flag = .pick
        }
        let setID = AssetSetID(rawValue: "map-both")
        try repository.upsert(AssetSet.manual(id: setID, name: "Both", assetIDs: [picked.id, unpicked.id]))
        try model.refreshSavedAssetSets()
        try model.applyAssetSet(id: setID)

        model.flagFilter = .pick
        try model.applyLibraryFilters()
        try model.refreshPlaceData()

        XCTAssertEqual(model.geotaggedCoverage.totalCount, 1)
    }

    // MARK: - Fixtures

    private func makeGeotaggedAsset(id: String, path: String, latitude: Double, longitude: Double) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 100,
                pixelHeight: 100,
                latitude: latitude,
                longitude: longitude,
                provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
            )
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-map-scoping-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
```

`AppModel.catalogPlaceClusters`, `catalogTopLocations`, and `geotaggedCoverage` are all `public private(set)` (`AppModel.swift:2373-2375`), so these assertions read them directly.

- [ ] **Step 3: Run and verify the reds**

Run: `swift test --filter AssetSetPredicateTests 2>&1 | tail -30`
Expected: **compile failure**, `type 'SetQuery.Predicate' has no member 'assetSet'`. Genuine red.

Run: `swift test --filter MapSourceScopingTests 2>&1 | tail -30`
Expected: `testMapScopesToASelectedStaticSet` **fails** with `totalCount == 2` (today the Map ignores an explicit-ID scope entirely) and `testTheMapQueryComposesASetScopeWithAnActiveFilter` **fails** with `totalCount == 2` as well. Both are genuine reds — they are the bug.

- [ ] **Step 4: Falsification red proof for the one test that passes today**

`testMapCoversTheWholeCatalogOnAllPhotos` passes against current behaviour — an unscoped Map has always been catalog-wide. Prove it is sensitive: in `Sources/TeststripApp/AppModel.swift`, in `refreshPlaceData(bounds:cellSize:)` (`:11017-11026`), change

```swift
        let query = currentLibraryQuery()
```

to

```swift
        let query = SetQuery(predicates: [.flag(.pick)])
```

Run `swift test --filter MapSourceScopingTests/testMapCoversTheWholeCatalogOnAllPhotos`. Expected: `totalCount == 2` fails with `0` — nothing is flagged in the fixture. Capture. Then `git checkout -- Sources/TeststripApp/AppModel.swift` and confirm `git diff --stat -- Sources/` is empty.

- [ ] **Step 5: Capture every red transcript into your task report**

- [ ] **Step 6: Commit**

```bash
git status
git add Tests/TeststripCoreTests/AssetSetPredicateTests.swift Tests/TeststripAppTests/MapSourceScopingTests.swift
git commit -m "test: pin Map scoping for explicit-ID sources (red)"
```

---

## Task 4B: Map respects an explicit-ID source — implementation

**Files:**
- Modify: `Sources/TeststripCore/Search/SetQuery.swift` (the `Predicate` enum, `:18-43`)
- Modify: `Sources/TeststripCore/Catalog/CatalogRepository.swift` (`compileClauses(_:)` `:2960-…`, plus one private SQL helper next to `workSessionAssetMembershipSelector` `:3328`)
- Modify: `Sources/TeststripApp/AppModel.swift` (`refreshPlaceData(bounds:cellSize:)` `:11017-11026`, plus the four exhaustive `SetQuery.Predicate` switches)
- Modify: `Sources/TeststripApp/LibraryQueryTokenField.swift` (`:359` area — its exhaustive predicate switch)

**Interfaces:**
- Consumes: the `json_each(asset_sets.membership_json, …)` technique already used by `workSessionAssetMembershipSelector` (`CatalogRepository.swift:3328-3336`), `selectedExplicitAssetIDs` (`AppModel.swift`, private computed), `currentLibraryQuery()` (`:11663`).
- Produces: `SetQuery.Predicate.assetSet(AssetSetID)`, `AppModel.currentMapQuery()`. Task 5B's `applySource` and Task 7B's Selection source both benefit for free; nothing else is required to consume it.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Add the predicate**

In `Sources/TeststripCore/Search/SetQuery.swift`, add as the last case of `Predicate` (after `.workSession(String)` at `:42`):

```swift
        /// Membership in one saved set's STATIC membership (`.manual` /
        /// `.snapshot`). A `.dynamic` set's membership is its own query and
        /// reaches SQL that way instead, so it matches nothing here.
        case assetSet(AssetSetID)
```

- [ ] **Step 2: Compile it**

In `Sources/TeststripCore/Catalog/CatalogRepository.swift`, add this arm to `compileClauses(_:)`, next to the `.workSession` arm:

```swift
            case .assetSet(let setID):
                clauses.append(Self.assetSetMembershipClause())
                bindings.append(contentsOf: [setID.rawValue, setID.rawValue])
```

and this private helper immediately after `workSessionAssetMembershipSelector(setIDColumnName:membershipPath:)` (`:3328-3336`):

```swift
    /// The static half of a saved set's membership, resolved the same way
    /// `workSessionAssetMembershipSelector` resolves a work session's sets:
    /// `json_each` on a membership path that doesn't exist (a `.dynamic` set)
    /// yields zero rows, so a dynamic set simply matches nothing here.
    private static func assetSetMembershipClause() -> String {
        let selectors = ["$.manual._0", "$.snapshot._0"].map { membershipPath in
            """
            SELECT json_extract(set_assets.value, '$.rawValue')
            FROM asset_sets
            JOIN json_each(asset_sets.membership_json, '\(membershipPath)') set_assets
            WHERE asset_sets.id = ?
            """
        }
        return "assets.id IN (\n\(selectors.joined(separator: "\nUNION\n"))\n)"
    }
```

- [ ] **Step 3: Close the four other exhaustive switches**

The compiler will name each one. Add these arms:

In `AppModel.activeLibraryFilterRow(for:)` (`:11338-11389`), so the scope renders as a removable chip like every other predicate:

```swift
        case .assetSet(let id):
            ActiveLibraryFilterRow(title: "Set: \(id.rawValue)", target: nil)
```

In `AppModel.sidebarTarget(for predicate:)` / `librarySource(for predicate:)` (`:11413-11446`) — if your version of that function still has an exhaustive switch rather than a `default:`, add:

```swift
        case .assetSet:
            nil
```

In `AppModel.searchTextToken(for:)` (`:11892-11943`), alongside the four other predicates with no text form:

```swift
        case .assetSet:
            nil
```

In `Sources/TeststripApp/LibraryQueryTokenField.swift`'s predicate switch (`:359` area), add the arm its neighbours use for a predicate with no token form — match whatever `.likelyPick` does there.

- [ ] **Step 4: Scope the Map**

In `Sources/TeststripApp/AppModel.swift`, replace `refreshPlaceData(bounds:cellSize:)` (`:11017-11026`) with:

```swift
    func refreshPlaceData(
        bounds: GeoBounds? = nil,
        cellSize: Double = AppModel.defaultPlaceClusterCellSize
    ) throws {
        guard let catalog else { return }
        let query = currentMapQuery()
        catalogPlaceClusters = try catalog.repository.placeClusters(bounds: bounds, cellSize: cellSize, matching: query)
        catalogTopLocations = try catalog.repository.topLocations(limit: Self.topLocationsDisplayLimit, matching: query)
        geotaggedCoverage = try catalog.repository.geotaggedCoverage(matching: query)
    }

    /// The Map lens is source-scoped like every other lens. A dynamic scope
    /// already reaches SQL through `currentLibraryQuery()`; a static one — a
    /// saved manual/snapshot set, or the Selection — lived only in
    /// `selectedExplicitAssetIDs`, which `currentLibraryQuery()` cannot see,
    /// so the Map silently showed every geotagged photo in the catalog for
    /// those sources.
    private func currentMapQuery() -> SetQuery? {
        var predicates = currentLibraryQuery()?.predicates ?? []
        if selectedExplicitAssetIDs != nil, let selectedAssetSetID {
            predicates.append(.assetSet(selectedAssetSetID))
        }
        return predicates.isEmpty ? nil : SetQuery(predicates: predicates)
    }
```

- [ ] **Step 5: Run the new tests and verify they pass**

Run: `swift test --filter AssetSetPredicateTests && swift test --filter MapSourceScopingTests`
Expected: 0 failures in both.

- [ ] **Step 6: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures. Nothing else constructs a `.assetSet` predicate yet, so no other surface can move.

- [ ] **Step 7: Commit**

```bash
git status
git add Sources/TeststripCore/Search/SetQuery.swift Sources/TeststripCore/Catalog/CatalogRepository.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryQueryTokenField.swift
git commit -m "fix: the Map lens scopes to a saved static set, not the whole catalog"
```

---

## Task 5A: Lenses and sources replace workspaces — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/LibraryLensTests.swift` (create)
- Test: `Tests/TeststripAppTests/LibrarySourceTests.swift` (create)
- Test: `Tests/TeststripAppTests/WorkspacePresentationTests.swift` (**delete**)
- Test: `Tests/TeststripAppTests/WorkspaceChromePolicyTests.swift` → **rename** to `LensChromePolicyTests.swift` and rewrite
- Test: `Tests/TeststripAppTests/AppWindowLayoutTests.swift` (rewrite in place)
- Test: `Tests/TeststripAppTests/MenuCoveragePresentationTests.swift` (`:19-33`)
- Test: `Tests/TeststripAppTests/CullingKeyCaptureTests.swift` (`:216-222`, `:261-266`)
- Test: `Tests/TeststripAppTests/SidebarSectionsTests.swift` (`:18`, `:33-55`)
- Test: `Tests/TeststripAppTests/CullSourcePresentationTests.swift` (`:134`, `:148`)
- Test: `Tests/TeststripAppTests/InspectorTabsPresentationTests.swift` (13 call sites)
- Test: `Tests/TeststripAppTests/AppModelFilterPersistenceTests.swift` (`:37,40,55,183,212`)
- Test: `Tests/TeststripAppTests/CullSubViewSwitchingTests.swift` (`:17,23,62`)
- Test: `Tests/TeststripAppTests/AppModelTests.swift` (`:342-390`, `:796-812`, `:2660-2695`, `:6538-6557`, `:6559-…`, `:19939`)
- Test: `Tests/TeststripAppTests/ImportSourceScopingTests.swift` (migrate `selectSidebarTarget` calls — Task 2A wrote them against the old API)
- Test: `Tests/TeststripAppTests/PeopleSourceScopingTests.swift` (same migration)
- Test: `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift` (`:13,223,268` — `selectSidebarTarget(.search)` has no successor; use `.allPhotos`)

**Interfaces (what Task 5B must produce — write your tests against exactly these names):**

- `public enum LibraryLens: String, CaseIterable, Sendable { case cull, grid, loupe, timeline, map, people }` with `title`, `systemImage`, `keyEquivalent: KeyEquivalent` (⌘1–⌘6 in declaration order), `defaultViewMode: LibraryViewMode` (`.loupe/.grid/.libraryLoupe/.timeline/.map/.people`).
- `LibraryViewMode.lens: LibraryLens` — `.loupe/.compare/.abCompare/.cullGrid → .cull`, `.grid → .grid`, `.libraryLoupe → .loupe`, `.timeline → .timeline`, `.map → .map`, `.people → .people`.
- `public struct LensAvailability: Equatable, Sendable { var lens: LibraryLens; var isEnabled: Bool; var disabledReason: String? }`
- `public enum LensRules` with `availability(for:sourceIsDiagnostic:sourceAssetCount:) -> LensAvailability`, `availabilities(sourceIsDiagnostic:sourceAssetCount:) -> [LensAvailability]`, and `resolvedLens(_:sourceIsDiagnostic:sourceAssetCount:) -> LibraryLens` (returns `.grid` when the requested lens is disabled).
- `public enum ImportChildKind: String, Codable, Equatable, Sendable { case stacks, skippedFiles, previewFailed, likelyIssues, facesFound }` with `title`, `systemImage`, `isDiagnostic`.
- `public enum LibrarySourceKind: Equatable, Codable, Sendable` with cases `allPhotos`, `search(SetQuery)`, `smartCollection(SmartCollection)`, `autopilotSuggestions`, `folder(String)`, `sourceAvailability(SourceAvailability)`, `evaluationKind(EvaluationKind)`, `metadataSyncPending`, `metadataSyncConflicts`, `assetSet(AssetSetID)`, `workSession(WorkSessionID)`, `importChild(session: WorkSessionID, child: ImportChildKind)`, `selection`.
- `public struct LibrarySource: Equatable, Codable, Sendable { var kind: LibrarySourceKind; var title: String; var isDiagnostic: Bool { get } }` with static factories `.allPhotos`, `.search(_:titled:)`, `.smartCollection(_:)`, `.autopilotSuggestions`, `.folder(_:)`, `.sourceAvailability(_:)`, `.evaluationKind(_:titled:)`, `.metadataSyncPending`, `.metadataSyncConflicts`, `.assetSet(_:titled:)`, `.workSession(_:titled:)`, `.importChild(session:child:)`, `.selection`.
- `SidebarRow.target: LibrarySource?` (nil = a non-selectable placeholder row); `SidebarRow.isSelectable == (target != nil)`. **`SidebarRowTarget` is deleted.**
- `AppModel.selectedSource: LibrarySource` — `public private(set)`, defaults to `.allPhotos`.
- `AppModel.selectedLens: LibraryLens` — computed `selectedView.lens`.
- `AppModel.selectLens(_ lens: LibraryLens)` — replaces `selectWorkspace(_:)`. Enters `lastCullViewMode` for `.cull`, `lens.defaultViewMode` otherwise. **Never changes the source.**
- `AppModel.selectSource(_ source: LibrarySource) throws` — replaces `selectSidebarTarget(_:)`. **Never changes the lens**, except the Grid fallback when the current lens is disabled on the new source.
- `AppModel.selectSidebarRow(_ row: SidebarRow) throws` — unchanged name; no-ops for a nil target.
- `AppModel.lensAvailabilities: [LensAvailability]` — the switcher's enabled/disabled state for the current source.
- `AppModel.isCullingMenuShortcutActive` — unchanged name, now `CullingKeyCaptureGate.isActive(lens: selectedLens, selectedView: selectedView)`.
- `CullingKeyCaptureGate.isActive(lens: LibraryLens, selectedView: LibraryViewMode) -> Bool`.
- `LensChromePolicy` — `WorkspaceChromePolicy` renamed, same eleven members **minus `showsLibraryViewToggle`** (deleted; the lens switcher is always visible).
- `AppWindowLayoutMetrics.minimumWidth: CGFloat` — a `static let` equal to `1_000`. `minimumWidth(for:)` is deleted.
- `AppMenuCoveragePresentation.lensActionIDs: [String]` = `LibraryLens.allCases.map(\.title)`; `AppMenuCoveragePresentation.cullSubModeMenuModes: [LibraryViewMode]` = `[.loupe, .cullGrid, .compare, .abCompare]`; `LibraryViewMode.cullSubModeMenuTitle: String?` (nil outside those four). `workspaceActionIDs` and `subViewMenuModes` are deleted.
- `AppModel.sidebarSections()` — the `for workspace:` parameter is deleted.
- `AppModel.toggleFolderExpansion(path:)` — unchanged in Task 5 (generalized in Task 6).

**You are the test author. Do not write any file under `Sources/`.** This is the shell cutover: your commit will leave `swift test` red because it references types that do not exist yet. That is expected and Task 5B closes it immediately.

- [ ] **Step 1: Write `LibraryLensTests.swift`**

Create `Tests/TeststripAppTests/LibraryLensTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import TeststripApp

// Six lenses over one source, ⌘1–⌘6 in the same order. The Cull|Library
// workspace split is gone; Compare/A-B/cull-grid stay transient sub-modes of
// the Cull lens rather than becoming lenses of their own.
final class LibraryLensTests: XCTestCase {
    func testLensOrderTitlesAndKeyEquivalents() {
        XCTAssertEqual(LibraryLens.allCases, [.cull, .grid, .loupe, .timeline, .map, .people])
        XCTAssertEqual(LibraryLens.allCases.map(\.title), ["Cull", "Grid", "Loupe", "Timeline", "Map", "People"])
        XCTAssertEqual(
            LibraryLens.allCases.map(\.keyEquivalent),
            [KeyEquivalent("1"), KeyEquivalent("2"), KeyEquivalent("3"), KeyEquivalent("4"), KeyEquivalent("5"), KeyEquivalent("6")]
        )
    }

    func testEveryViewModeMapsToExactlyOneLens() {
        for mode in LibraryViewMode.allCases {
            _ = mode.lens // exhaustive switch compiles = every mode owned
        }
        XCTAssertEqual(LibraryViewMode.loupe.lens, .cull)
        XCTAssertEqual(LibraryViewMode.compare.lens, .cull)
        XCTAssertEqual(LibraryViewMode.abCompare.lens, .cull)
        XCTAssertEqual(LibraryViewMode.cullGrid.lens, .cull)
        XCTAssertEqual(LibraryViewMode.grid.lens, .grid)
        XCTAssertEqual(LibraryViewMode.libraryLoupe.lens, .loupe)
        XCTAssertEqual(LibraryViewMode.timeline.lens, .timeline)
        XCTAssertEqual(LibraryViewMode.map.lens, .map)
        XCTAssertEqual(LibraryViewMode.people.lens, .people)
    }

    func testEveryLensRoundTripsThroughItsDefaultViewMode() {
        for lens in LibraryLens.allCases {
            XCTAssertEqual(lens.defaultViewMode.lens, lens, "\(lens)")
        }
    }

    func testCullIsDisabledOnDiagnosticAndEmptySourcesOnly() {
        let onDiagnostic = LensRules.availability(for: .cull, sourceIsDiagnostic: true, sourceAssetCount: 12)
        XCTAssertFalse(onDiagnostic.isEnabled)
        XCTAssertEqual(onDiagnostic.disabledReason, "Nothing here is cullable")

        let onEmpty = LensRules.availability(for: .cull, sourceIsDiagnostic: false, sourceAssetCount: 0)
        XCTAssertFalse(onEmpty.isEnabled)
        XCTAssertEqual(onEmpty.disabledReason, "No photos to cull")

        let onNormal = LensRules.availability(for: .cull, sourceIsDiagnostic: false, sourceAssetCount: 3)
        XCTAssertTrue(onNormal.isEnabled)
        XCTAssertNil(onNormal.disabledReason)
    }

    func testEveryOtherLensIsEnabledEverywhere() {
        for lens in LibraryLens.allCases where lens != .cull {
            XCTAssertTrue(
                LensRules.availability(for: lens, sourceIsDiagnostic: true, sourceAssetCount: 0).isEnabled,
                "\(lens)"
            )
        }
    }

    func testAvailabilitiesCoverEveryLensInOrder() {
        let availabilities = LensRules.availabilities(sourceIsDiagnostic: true, sourceAssetCount: 0)
        XCTAssertEqual(availabilities.map(\.lens), LibraryLens.allCases)
        XCTAssertEqual(availabilities.filter { !$0.isEnabled }.map(\.lens), [.cull])
    }

    func testADisabledLensFallsBackToGrid() {
        XCTAssertEqual(LensRules.resolvedLens(.cull, sourceIsDiagnostic: true, sourceAssetCount: 5), .grid)
        XCTAssertEqual(LensRules.resolvedLens(.cull, sourceIsDiagnostic: false, sourceAssetCount: 0), .grid)
        XCTAssertEqual(LensRules.resolvedLens(.cull, sourceIsDiagnostic: false, sourceAssetCount: 5), .cull)
        XCTAssertEqual(LensRules.resolvedLens(.timeline, sourceIsDiagnostic: true, sourceAssetCount: 0), .timeline)
    }

    func testSelectingALensNeverChangesTheSource() throws {
        let model = AppModel.demo()
        let source = LibrarySource.smartCollection(.picks)
        try model.selectSource(source)

        for lens in LibraryLens.allCases {
            model.selectLens(lens)
            XCTAssertEqual(model.selectedSource, source, "\(lens) changed the source")
        }
    }

    func testSelectingACullSubModeThenReenteringCullReturnsToIt() {
        let model = AppModel.demo()
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe)

        model.selectedView = .cullGrid
        model.selectLens(.timeline)
        XCTAssertEqual(model.selectedView, .timeline)

        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .cullGrid)
    }

    // The ⌘1 dead-key root cause: Compare/A-B are transient comparator
    // overlays, not a "home" sub-mode — re-entering the Cull lens must escape
    // the trap, not restore it.
    func testReenteringCullNeverRestoresIntoCompareOrABCompare() {
        let model = AppModel.demo()
        model.selectedView = .loupe
        model.selectedView = .compare
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe)

        model.selectedView = .abCompare
        model.selectLens(.cull)
        XCTAssertEqual(model.selectedView, .loupe)
    }

    func testLoupePresentationChromeFlagByMode() {
        XCTAssertTrue(LoupePresentation(mode: .loupe).showsCullChrome)
        XCTAssertFalse(LoupePresentation(mode: .libraryLoupe).showsCullChrome)
    }
}
```

- [ ] **Step 2: Write `LibrarySourceTests.swift`**

Create `Tests/TeststripAppTests/LibrarySourceTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// A source is a noun: the set of photos the sidebar (or a query) names. It is
// stored, not reconstructed from filter state, so the scope line can name it
// and a relaunch can restore it.
final class LibrarySourceTests: XCTestCase {
    func testDiagnosticSourcesAreExactlyTheOnesWithNothingCullable() {
        let session = WorkSessionID(rawValue: "import-1")

        XCTAssertTrue(LibrarySource.importChild(session: session, child: .skippedFiles).isDiagnostic)
        XCTAssertTrue(LibrarySource.importChild(session: session, child: .previewFailed).isDiagnostic)
        XCTAssertTrue(LibrarySource.smartCollection(.providerFailures).isDiagnostic)
        XCTAssertTrue(LibrarySource.metadataSyncConflicts.isDiagnostic)
        XCTAssertTrue(LibrarySource.sourceAvailability(.missing).isDiagnostic)

        XCTAssertFalse(LibrarySource.allPhotos.isDiagnostic)
        XCTAssertFalse(LibrarySource.smartCollection(.picks).isDiagnostic)
        XCTAssertFalse(LibrarySource.importChild(session: session, child: .stacks).isDiagnostic)
        XCTAssertFalse(LibrarySource.importChild(session: session, child: .likelyIssues).isDiagnostic)
        XCTAssertFalse(LibrarySource.importChild(session: session, child: .facesFound).isDiagnostic)
    }

    func testEverySourceRoundTripsThroughCodable() throws {
        let sources: [LibrarySource] = [
            .allPhotos,
            .search(SetQuery(predicates: [.likelyPick, .evaluationFailure]), titled: "Search results"),
            .smartCollection(.likelyIssues),
            .autopilotSuggestions,
            .folder("/Photos/2026"),
            .sourceAvailability(.offline),
            .evaluationKind(.focus, titled: "Focus"),
            .metadataSyncPending,
            .metadataSyncConflicts,
            .assetSet(AssetSetID(rawValue: "set-1"), titled: "Keepers"),
            .workSession(WorkSessionID(rawValue: "import-1"), titled: "Aug 7 · Imported from /Cards/A"),
            .importChild(session: WorkSessionID(rawValue: "import-1"), child: .previewFailed),
            .selection
        ]

        for source in sources {
            let data = try JSONEncoder().encode(source)
            XCTAssertEqual(try JSONDecoder().decode(LibrarySource.self, from: data), source, source.title)
        }
    }

    // The predicates the text serializer loses (.likelyPick, .likelyIssue,
    // .evaluationFailure, .withinGeoBounds) must survive a source round trip,
    // because a search source is exactly how "Cull these" travels.
    func testASearchSourcePreservesThePredicatesTheTextSerializerDrops() throws {
        let query = SetQuery(predicates: [
            .likelyPick,
            .likelyIssue,
            .evaluationFailure,
            .withinGeoBounds(GeoBounds(minLatitude: 1, maxLatitude: 2, minLongitude: 3, maxLongitude: 4))
        ])
        let source = LibrarySource.search(query, titled: "Search results")

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(LibrarySource.self, from: data)

        guard case .search(let decodedQuery) = decoded.kind else {
            return XCTFail("expected a search source")
        }
        XCTAssertEqual(decodedQuery, query)
    }

    func testSelectingASourceNeverChangesTheLens() throws {
        let inside = makeAsset(id: "source-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "source-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-keeps-lens", assets: [inside, outside])

        model.selectLens(.timeline)
        try model.selectSource(.folder("/Photos/Inside"))

        XCTAssertEqual(model.selectedLens, .timeline)
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/Inside"))
        XCTAssertEqual(model.assets.map(\.id), [inside.id])
    }

    func testSelectingADiagnosticSourceFallsTheCullLensBackToGrid() throws {
        let asset = makeAsset(id: "fallback", path: "/Photos/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-lens-fallback", assets: [asset])

        model.selectLens(.cull)
        XCTAssertEqual(model.selectedLens, .cull)

        try model.selectSource(.smartCollection(.providerFailures))

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(model.selectedSource, LibrarySource.smartCollection(.providerFailures))
    }

    func testCullStaysDisabledOnAnEmptySource() throws {
        let asset = makeAsset(id: "empty-source", path: "/Photos/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-empty-cull", assets: [asset])

        try model.selectSource(.folder("/Photos/Nowhere"))

        XCTAssertTrue(model.assets.isEmpty)
        let cull = try XCTUnwrap(model.lensAvailabilities.first { $0.lens == .cull })
        XCTAssertFalse(cull.isEnabled)
        XCTAssertEqual(cull.disabledReason, "No photos to cull")
    }

    func testSelectingAllPhotosClearsTheScopeAndNamesTheSource() throws {
        let inside = makeAsset(id: "all-inside", path: "/Photos/Inside/a.jpg")
        let outside = makeAsset(id: "all-outside", path: "/Photos/Outside/b.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "source-all-photos", assets: [inside, outside])
        try model.selectSource(.folder("/Photos/Inside"))

        try model.selectSource(.allPhotos)

        XCTAssertEqual(model.selectedSource.title, "All Photos")
        XCTAssertEqual(Set(model.assets.map(\.id)), Set([inside.id, outside.id]))
        XCTAssertTrue(model.activeLibraryFilterChips.isEmpty)
    }

    // MARK: - Fixtures

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: Int64(id.count + 1), modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private func makeModelWithCatalogAssets(
        named name: String,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-library-source-\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog, workerSupervisor: nil)
        return (model, repository)
    }
}
```

- [ ] **Step 3: Delete the workspace test file and rewrite the two policy files**

```bash
git rm Tests/TeststripAppTests/WorkspacePresentationTests.swift
```

Rename the chrome-policy test file so it names what it tests, then replace its contents in full:

```bash
git mv Tests/TeststripAppTests/WorkspaceChromePolicyTests.swift Tests/TeststripAppTests/LensChromePolicyTests.swift
```

`Tests/TeststripAppTests/LensChromePolicyTests.swift`:

```swift
import XCTest
@testable import TeststripApp

/// `LensChromePolicy` is keyed on the selected `LibraryViewMode` through its
/// lens: the browse lenses (Grid/Loupe/Timeline/Map) carry the full browse
/// chrome; the focused lenses (Cull and People) carry none of it.
final class LensChromePolicyTests: XCTestCase {
    private static let browseViews: [LibraryViewMode] = [.grid, .libraryLoupe, .timeline, .map]
    private static let focusedViews: [LibraryViewMode] = [.people, .loupe, .compare, .abCompare, .cullGrid]

    func testBrowseLensesShowAllBrowseChrome() {
        for view in Self.browseViews {
            XCTAssertTrue(LensChromePolicy.showsSearchField(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsFilterTokens(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsImportButton(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsFooter(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsImportMenu(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsCullButton(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsExportButton(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsMoreMenu(view), "\(view)")
            XCTAssertTrue(LensChromePolicy.showsInspector(view), "\(view)")
        }
    }

    func testFocusedLensesHideBrowseChromeButKeepTheInspector() {
        for view in Self.focusedViews {
            XCTAssertFalse(LensChromePolicy.showsSearchField(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsFilterTokens(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsImportButton(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsFooter(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsImportMenu(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsCullButton(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsExportButton(view), "\(view)")
            XCTAssertFalse(LensChromePolicy.showsMoreMenu(view), "\(view)")
            // ⌘I is reachable in every lens.
            XCTAssertTrue(LensChromePolicy.showsInspector(view), "\(view)")
        }
    }

    func testToolbarActionChromeMatrixCoversEveryViewMode() {
        for view in LibraryViewMode.allCases {
            let expected = Self.browseViews.contains(view)
            XCTAssertEqual(LensChromePolicy.showsImportMenu(view), expected, "\(view)")
            XCTAssertEqual(LensChromePolicy.showsCullButton(view), expected, "\(view)")
            XCTAssertEqual(LensChromePolicy.showsExportButton(view), expected, "\(view)")
            XCTAssertEqual(LensChromePolicy.showsMoreMenu(view), expected, "\(view)")
        }
    }
}
```

Replace `Tests/TeststripAppTests/AppWindowLayoutTests.swift` in full with:

```swift
import XCTest
@testable import TeststripApp

final class AppWindowLayoutTests: XCTestCase {
    // One window, one floor: the per-workspace 1000/800 split went away with
    // the Cull|Library split, because there is no longer a workspace whose
    // chrome another workspace was paying for.
    func testTheWindowHasASingleMinimumWidth() {
        XCTAssertEqual(AppWindowLayoutMetrics.minimumWidth, 1_000)
    }

    func testMainWindowDefaultSizeClearsTheMinimums() {
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultWidth, AppWindowLayoutMetrics.minimumWidth)
        XCTAssertGreaterThanOrEqual(AppWindowLayoutMetrics.defaultHeight, AppWindowLayoutMetrics.minimumHeight)
    }
}
```

- [ ] **Step 4: Rewrite the menu-coverage invariants (F14 — same commit as the source change)**

In `Tests/TeststripAppTests/MenuCoveragePresentationTests.swift`, replace `testViewMenuCoversEveryWorkspace` (`:19-21`) and `testViewMenuCoversEverySubView` (`:23-33`) with:

```swift
    func testViewMenuCoversEveryLens() {
        XCTAssertEqual(AppMenuCoveragePresentation.lensActionIDs, LibraryLens.allCases.map(\.title))
        XCTAssertEqual(AppMenuCoveragePresentation.lensActionIDs.count, 6)
    }

    // Every route must be reachable from a menu item: five of the nine view
    // modes are a lens's default route, and the four cull sub-modes
    // (loupe/cull grid/compare/A-B) get their own items below the divider.
    func testEveryViewModeIsReachableFromAMenuItem() {
        for mode in LibraryViewMode.allCases {
            let reachableAsLensDefault = LibraryLens.allCases.contains { $0.defaultViewMode == mode }
            let reachableAsCullSubMode = AppMenuCoveragePresentation.cullSubModeMenuModes.contains(mode)
            XCTAssertTrue(reachableAsLensDefault || reachableAsCullSubMode, "\(mode) has no menu item")
        }
        for mode in AppMenuCoveragePresentation.cullSubModeMenuModes {
            XCTAssertNotNil(mode.cullSubModeMenuTitle, "\(mode) has no cull sub-mode menu title")
        }
    }

    // Bare menu key equivalents double-dispatch against the in-view NSEvent
    // monitors (run-cull-iter2 cull-003/005/007), so the culling shortcuts
    // stay unbound in the menu and every lens key is ⌘-modified.
    func testLensShortcutsAreModifierBearingAndCullingShortcutsStayUnbound() {
        for key in CullingShortcutKey.allCases {
            XCTAssertNil(key.menuKeyboardShortcut, "\(key) must not carry a bare menu key equivalent")
        }
    }
```

**Before running, confirm `CullingShortcutKey` is `CaseIterable`:**

```bash
grep -n "enum CullingShortcutKey" Sources/TeststripApp/*.swift
```

If it is not `CaseIterable`, drop only `testLensShortcutsAreModifierBearingAndCullingShortcutsStayUnbound` and say so in your report — the constraint is still enforced by `main.swift:569-571` returning `nil` unconditionally.

- [ ] **Step 5: Migrate the gate, sidebar, and workspace call sites**

In `Tests/TeststripAppTests/CullingKeyCaptureTests.swift`, replace `testCullingKeyCaptureGateInactiveOutsideCullWorkspace` (`:216-222`) and `testCullingKeyCaptureGateActiveInCullSubViewsExceptGrid` (`:261-266`) with:

```swift
    func testCullingKeyCaptureGateInactiveOutsideTheCullLens() {
        XCTAssertFalse(CullingKeyCaptureGate.isActive(lens: .people, selectedView: .people))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(lens: .timeline, selectedView: .timeline))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(lens: .map, selectedView: .map))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(lens: .grid, selectedView: .grid))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(lens: .loupe, selectedView: .libraryLoupe))
    }
```

```swift
    func testCullingKeyCaptureGateActiveInCullSubModesExceptTheCullGrid() {
        XCTAssertTrue(CullingKeyCaptureGate.isActive(lens: .cull, selectedView: .loupe))
        XCTAssertTrue(CullingKeyCaptureGate.isActive(lens: .cull, selectedView: .compare))
        XCTAssertTrue(CullingKeyCaptureGate.isActive(lens: .cull, selectedView: .abCompare))
        XCTAssertFalse(CullingKeyCaptureGate.isActive(lens: .cull, selectedView: .cullGrid))
    }
```

In `Tests/TeststripAppTests/SidebarSectionsTests.swift`: change `model.sidebarSections(for: .library)` (`:18`) and `model.sidebarSections(for: .library)` (`:64`) to `model.sidebarSections()`; delete `testCullSidebarSectionsAreEmpty` (`:33-37`) outright — there is no per-workspace sidebar to be empty; and replace `testSidebarSectionsTrackTheCurrentWorkspaceAsSelectedViewChanges` (`:39-55`) with:

```swift
    func testTheSidebarIsTheSameInEveryLens() {
        let model = AppModel.demo()
        let expected = model.sidebarSections.map(\.title)

        for lens in LibraryLens.allCases {
            model.selectLens(lens)
            XCTAssertEqual(model.sidebarSections.map(\.title), expected, "\(lens)")
        }
    }
```

In `Tests/TeststripAppTests/CullSourcePresentationTests.swift`, change `XCTAssertEqual(model.selectedWorkspace, .cull)` at `:134` and `:148` to `XCTAssertEqual(model.selectedLens, .cull)`.

In `Tests/TeststripAppTests/InspectorTabsPresentationTests.swift`, `Tests/TeststripAppTests/AppModelFilterPersistenceTests.swift`, `Tests/TeststripAppTests/CullSubViewSwitchingTests.swift`, and `Tests/TeststripAppTests/AppModelTests.swift`, apply this mechanical mapping. Do not work from the line numbers alone — they have already drifted. Find every occurrence with

```bash
grep -rn "selectWorkspace\|selectedWorkspace\|selectSidebarTarget" Tests/
```

and convert **all** of them, including the ones Tasks 1A, 2A, and 3A added:

| Old | New |
|---|---|
| `model.selectWorkspace(.cull)` | `model.selectLens(.cull)` |
| `model.selectWorkspace(.library)` | `model.selectLens(.grid)` |
| `model.selectedWorkspace` | `model.selectedLens` |
| `XCTAssertEqual(model.selectedWorkspace, .cull)` | `XCTAssertEqual(model.selectedLens, .cull)` |
| `XCTAssertEqual(model.selectedWorkspace, .library)` | `XCTAssertEqual(model.selectedLens, .grid)` |
| `model.selectSidebarTarget(.allPhotographs)` | `model.selectSource(.allPhotos)` |
| `model.selectSidebarTarget(.smartCollection(q))` | `model.selectSource(.smartCollection(q))` |
| `model.selectSidebarTarget(.folder(p))` | `model.selectSource(.folder(p))` |
| `model.selectSidebarTarget(.search)` | `model.selectSource(.allPhotos)` |
| `model.selectSidebarTarget(.places)` | `model.selectLens(.map)` |
| `model.selectSidebarTarget(.people)` | `model.selectLens(.people)` |
| `model.selectSidebarTarget(.timeline)` | `model.selectLens(.timeline)` |

Also rename `testApplyingCullingShortcutSwitchesSubViewWithoutLeavingCullWorkspace` → `…WithoutLeavingTheCullLens` and `testCullGridBelongsToCullWorkspace` → `testCullGridBelongsToTheCullLens` in `CullSubViewSwitchingTests.swift`.

Also migrate the `selectSidebarTarget` calls in `Tests/TeststripAppTests/ImportSourceScopingTests.swift` and `Tests/TeststripAppTests/PeopleSourceScopingTests.swift` (written in Tasks 2A/3A against the old API) using the same mapping.

- [ ] **Step 6: Rewrite the three nav-history tests, which used lens routes as stand-in sources**

In `Tests/TeststripAppTests/AppModelTests.swift`, replace `testNavigateBackAndForwardMovesThroughSidebarViewHistory` (`:342-367`), `testNavigatingToANewViewAfterGoingBackClearsForwardHistory` (`:369-382`), and `testRepeatingTheCurrentViewDoesNotGrowNavigationHistory` (`:384-389`) with:

```swift
    func testNavigateBackAndForwardMovesThroughSourceHistory() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        XCTAssertFalse(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)

        try model.selectSource(.folder("/Photos/A"))
        try model.selectSource(.folder("/Photos/B"))
        try model.selectSource(.allPhotos)
        XCTAssertTrue(model.canNavigateBack)
        XCTAssertFalse(model.canNavigateForward)

        try model.navigateBack()
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/B"))
        XCTAssertTrue(model.canNavigateForward)

        try model.navigateBack()
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/A"))
        XCTAssertFalse(model.canNavigateBack)

        try model.navigateForward()
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/B"))
        try model.navigateForward()
        XCTAssertEqual(model.selectedSource, LibrarySource.allPhotos)
        XCTAssertFalse(model.canNavigateForward)
    }

    func testNavigatingToANewSourceAfterGoingBackClearsForwardHistory() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        try model.selectSource(.folder("/Photos/A"))
        try model.selectSource(.folder("/Photos/B"))

        try model.navigateBack()
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/A"))
        XCTAssertTrue(model.canNavigateForward)

        try model.selectSource(.allPhotos)
        XCTAssertFalse(model.canNavigateForward)

        try model.navigateBack()
        XCTAssertEqual(model.selectedSource, LibrarySource.folder("/Photos/A"))
    }

    func testRepeatingTheCurrentSourceDoesNotGrowNavigationHistory() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [])
        try model.selectSource(.folder("/Photos/A"))
        try model.selectSource(.folder("/Photos/A"))
        XCTAssertFalse(model.canNavigateBack)
    }
```

Also in `AppModelTests.swift`: in `testActiveLibraryFilterRowsBridgeConcreteFiltersToExistingTargets` (`:6559-…`), change every `target: .smartCollection(q)` / `.workSession(id)` / `.sourceAvailability(a)` / `.evaluationKind(k)` / `.metadataSyncPending` expectation to its `LibrarySource` factory equivalent (`target: LibrarySource.smartCollection(q)` etc.), keeping the `title:` strings byte-identical. Delete `testReselectingCullWorkspaceEscapesABCompareTrap` (`:796-812`) — `LibraryLensTests.testReenteringCullNeverRestoresIntoCompareOrABCompare` replaces it.

- [ ] **Step 7: Run and verify the red**

Run: `swift build 2>&1 | tail -40`
Expected: build succeeds (Sources are untouched).

Run: `swift test 2>&1 | tail -60`
Expected: **compile failure of the test target** naming, at minimum, `cannot find 'LibraryLens' in scope`, `cannot find 'LensRules' in scope`, `cannot find 'LibrarySource' in scope`, `cannot find 'LensChromePolicy' in scope`, `value of type 'AppModel' has no member 'selectLens'`, `… has no member 'selectSource'`, `… has no member 'selectedSource'`, `… has no member 'lensAvailabilities'`, `type 'AppMenuCoveragePresentation' has no member 'lensActionIDs'`, `type 'AppWindowLayoutMetrics' has no member 'minimumWidth'` (as a property).

Genuine red throughout: none of these symbols exists. No falsification step is needed — every assertion here names a type or method that has to be written.

- [ ] **Step 8: Capture the red transcript into your task report**

Your report must also list, explicitly, every test you deleted and why:
`WorkspacePresentationTests.swift` (whole file — replaced by `LibraryLensTests.swift`), `SidebarSectionsTests.testCullSidebarSectionsAreEmpty`, `SidebarSectionsTests.testSidebarSectionsTrackTheCurrentWorkspaceAsSelectedViewChanges`, `AppModelTests.testReselectingCullWorkspaceEscapesABCompareTrap`, and the three nav-history tests you rewrote.

- [ ] **Step 9: Commit**

```bash
git status
git add Tests/TeststripAppTests/
git commit -m "test: pin lenses and sources replacing workspaces (red)"
```

Note: this commit leaves `swift test` red. It is the only such point in the shell cutover; Task 5B closes it immediately.

---

## Task 5B: Lenses and sources replace workspaces — implementation

**Files:**
- Create: `Sources/TeststripApp/LibraryLens.swift`
- Create: `Sources/TeststripApp/LibrarySource.swift`
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift`
- Modify: `Sources/TeststripApp/main.swift`
- Modify: `Sources/TeststripApp/SidebarView.swift`
- Modify: `Sources/TeststripApp/CullingKeyCaptureView.swift`
- Modify: `Sources/TeststripApp/LoupeZoomView.swift`

**Interfaces:**
- Consumes: `SmartCollection.query` and `SmartCollection: Codable` (Task 1B), `ImportChildCounts`/`ImportSourceSummary` (Task 2B), `peopleScopeAssetIDs()` (Task 3B).
- Produces: everything listed in Task 5A's Interfaces block. Tasks 6B–10B all build on `LibrarySource`, `LibraryLens`, `selectSource`, and `selectLens`.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.** If a test looks wrong, stop and report it rather than editing it.

**F15 blast-radius checklist — you are done only when every one of these is handled:**

- [ ] `main.swift:43-48` — the `if model.selectedWorkspace == .cull` sidebar branch
- [ ] `AppModel.sidebarSections(for: Workspace)` (`:2119-2136`)
- [ ] `AppModel.selectWorkspace(_:)` (`:4955`) and `lastSubView` (`:2139`)
- [ ] `selectedView.didSet` arms 1 and 4 (`:2063-2065`, `:2068-2070`)
- [ ] `CullingKeyCaptureGate.isActive(workspace:selectedView:)` (`CullingKeyCaptureView.swift:12-14`) and its two consumers (`LibraryGridView.swift:205`, `AppModel.swift:2112-2114` → `main.swift:500`)
- [ ] `WorkspaceChromePolicy` (`LibraryGridView.swift:8357-8415`) and `LoupeZoomView.swift:273`
- [ ] `AppWindowLayoutMetrics.minimumWidth(for:)` (`main.swift:13-18`) and its use at `main.swift:59`
- [ ] `AppModel.requestFocusSearch` (`:2570-2575`) and `requestExport` (`:2606-2611`)
- [ ] `AppMenuCoveragePresentation.workspaceActionIDs` (`main.swift:108`) and `subViewMenuModes` (`main.swift:113-116`) — **same commit, F14**
- [ ] `workspaceSwitcher` (`LibraryGridView.swift:463-474`) and its toolbar mount (`:234-236`)
- [ ] `librarySubViewToggle` (`LibraryGridView.swift:480-494`) and `libraryTopBar` (`:550-587`)

- [ ] **Step 1: Create `LibraryLens.swift`**

```swift
import SwiftUI
import TeststripCore

/// How you are looking at the selected source. Six lenses, switched by one
/// toolbar control and ⌘1–⌘6 in the same order. This replaces `Workspace`:
/// there is no Cull|Library split any more, only a lens over a source.
///
/// Compare, A/B Compare, and the cull grid are deliberately NOT lenses — they
/// stay transient sub-modes inside the Cull lens, reached by g/c/b.
public enum LibraryLens: String, CaseIterable, Sendable {
    case cull
    case grid
    case loupe
    case timeline
    case map
    case people

    /// Display name shared by the toolbar switcher and the View menu so the
    /// two never drift out of sync.
    public var title: String {
        switch self {
        case .cull: return "Cull"
        case .grid: return "Grid"
        case .loupe: return "Loupe"
        case .timeline: return "Timeline"
        case .map: return "Map"
        case .people: return "People"
        }
    }

    public var systemImage: String {
        switch self {
        case .cull: return "checkmark.seal"
        case .grid: return "square.grid.2x2"
        case .loupe: return "photo"
        case .timeline: return "calendar"
        case .map: return "map"
        case .people: return "person.2"
        }
    }

    /// ⌘1–⌘6 in declaration order. Modifier-bearing on purpose: a bare menu
    /// key equivalent fires through AppKit's performKeyEquivalent path
    /// independently of the in-view NSEvent monitors, so one keypress
    /// dispatches twice (run-cull-iter2 cull-003/005/007).
    public var keyEquivalent: KeyEquivalent {
        switch self {
        case .cull: return "1"
        case .grid: return "2"
        case .loupe: return "3"
        case .timeline: return "4"
        case .map: return "5"
        case .people: return "6"
        }
    }

    /// The route a lens lands on when it has no remembered sub-mode.
    public var defaultViewMode: LibraryViewMode {
        switch self {
        case .cull: return .loupe
        case .grid: return .grid
        case .loupe: return .libraryLoupe
        case .timeline: return .timeline
        case .map: return .map
        case .people: return .people
        }
    }
}

public extension LibraryViewMode {
    /// Which lens this route belongs to. The four cull sub-modes all belong to
    /// the Cull lens, which is what keeps g/c/b transient rather than
    /// promoting them to top-level lenses.
    var lens: LibraryLens {
        switch self {
        case .loupe, .compare, .abCompare, .cullGrid:
            return .cull
        case .grid:
            return .grid
        case .libraryLoupe:
            return .loupe
        case .timeline:
            return .timeline
        case .map:
            return .map
        case .people:
            return .people
        }
    }
}

/// Whether a lens can be entered over a given source, and why not — rendered
/// as a disabled segment with the reason on hover.
public struct LensAvailability: Equatable, Sendable {
    public var lens: LibraryLens
    public var isEnabled: Bool
    public var disabledReason: String?

    public init(lens: LibraryLens, isEnabled: Bool, disabledReason: String? = nil) {
        self.lens = lens
        self.isEnabled = isEnabled
        self.disabledReason = disabledReason
    }
}

public enum LensRules {
    /// Cull disables on diagnostic sources — nothing there is cullable, and
    /// skipped files aren't even in the catalog — and on empty sources.
    /// Everything else works everywhere.
    public static func availability(
        for lens: LibraryLens,
        sourceIsDiagnostic: Bool,
        sourceAssetCount: Int
    ) -> LensAvailability {
        guard lens == .cull else {
            return LensAvailability(lens: lens, isEnabled: true)
        }
        if sourceIsDiagnostic {
            return LensAvailability(lens: lens, isEnabled: false, disabledReason: "Nothing here is cullable")
        }
        if sourceAssetCount == 0 {
            return LensAvailability(lens: lens, isEnabled: false, disabledReason: "No photos to cull")
        }
        return LensAvailability(lens: lens, isEnabled: true)
    }

    public static func availabilities(
        sourceIsDiagnostic: Bool,
        sourceAssetCount: Int
    ) -> [LensAvailability] {
        LibraryLens.allCases.map {
            availability(for: $0, sourceIsDiagnostic: sourceIsDiagnostic, sourceAssetCount: sourceAssetCount)
        }
    }

    /// Selecting a source the current lens disables on falls back to Grid.
    public static func resolvedLens(
        _ lens: LibraryLens,
        sourceIsDiagnostic: Bool,
        sourceAssetCount: Int
    ) -> LibraryLens {
        availability(for: lens, sourceIsDiagnostic: sourceIsDiagnostic, sourceAssetCount: sourceAssetCount).isEnabled
            ? lens
            : .grid
    }
}
```

- [ ] **Step 2: Create `LibrarySource.swift`**

```swift
import Foundation
import TeststripCore

/// The import-scoped child rows an import row discloses.
public enum ImportChildKind: String, Codable, Equatable, Sendable {
    case stacks
    case skippedFiles
    case previewFailed
    case likelyIssues
    case facesFound

    public var title: String {
        switch self {
        case .stacks: return "Stacks"
        case .skippedFiles: return "⚠ Skipped files"
        case .previewFailed: return "⚠ Preview failed"
        case .likelyIssues: return "⚠ Likely issues"
        case .facesFound: return "Faces found"
        }
    }

    public var systemImage: String {
        switch self {
        case .stacks: return "square.stack"
        case .skippedFiles: return "exclamationmark.triangle"
        case .previewFailed: return "exclamationmark.triangle"
        case .likelyIssues: return "exclamationmark.triangle"
        case .facesFound: return "person.2"
        }
    }

    /// Skipped files are not in the catalog at all and a failed preview has no
    /// frame to look at, so these two open in Grid for inspection and the Cull
    /// lens disables on them.
    public var isDiagnostic: Bool {
        self == .skippedFiles || self == .previewFailed
    }
}

/// What a source *is*. Every case names a set of photos; none of them names a
/// way of looking at one — `.timeline`, `.people`, and `.places` were lenses
/// masquerading as sources and are gone.
public enum LibrarySourceKind: Equatable, Codable, Sendable {
    case allPhotos
    case search(SetQuery)
    case smartCollection(SmartCollection)
    case autopilotSuggestions
    case folder(String)
    case sourceAvailability(SourceAvailability)
    case evaluationKind(EvaluationKind)
    case metadataSyncPending
    case metadataSyncConflicts
    case assetSet(AssetSetID)
    case workSession(WorkSessionID)
    case importChild(session: WorkSessionID, child: ImportChildKind)
    case selection
}

/// A named set of photos: the stored answer to "what am I looking at". The
/// title travels with the kind because several kinds (a saved set, an import,
/// a search) cannot derive their own display name.
public struct LibrarySource: Equatable, Codable, Sendable {
    public var kind: LibrarySourceKind
    public var title: String

    public init(kind: LibrarySourceKind, title: String) {
        self.kind = kind
        self.title = title
    }

    /// Diagnostic sources hold problems rather than photographs. The Cull lens
    /// disables on them; they open in Grid for inspection.
    public var isDiagnostic: Bool {
        switch kind {
        case .importChild(_, let child):
            return child.isDiagnostic
        case .smartCollection(let queue):
            return queue == .providerFailures
        case .metadataSyncConflicts, .metadataSyncPending, .sourceAvailability:
            return true
        case .allPhotos, .search, .autopilotSuggestions, .folder, .evaluationKind,
             .assetSet, .workSession, .selection:
            return false
        }
    }

    public static let allPhotos = LibrarySource(kind: .allPhotos, title: "All Photos")
    public static let autopilotSuggestions = LibrarySource(kind: .autopilotSuggestions, title: "AI Suggestions")
    public static let metadataSyncPending = LibrarySource(kind: .metadataSyncPending, title: "XMP Pending")
    public static let metadataSyncConflicts = LibrarySource(kind: .metadataSyncConflicts, title: "XMP Conflicts")
    public static let selection = LibrarySource(kind: .selection, title: "Selection")

    public static func search(_ query: SetQuery, titled title: String) -> LibrarySource {
        LibrarySource(kind: .search(query), title: title)
    }

    public static func smartCollection(_ queue: SmartCollection) -> LibrarySource {
        LibrarySource(kind: .smartCollection(queue), title: queue.presentation.title)
    }

    public static func folder(_ path: String) -> LibrarySource {
        let name = URL(fileURLWithPath: path).lastPathComponent
        return LibrarySource(kind: .folder(path), title: name.isEmpty ? path : name)
    }

    public static func sourceAvailability(_ availability: SourceAvailability) -> LibrarySource {
        LibrarySource(
            kind: .sourceAvailability(availability),
            title: "\(availability.rawValue.capitalized) Originals"
        )
    }

    public static func evaluationKind(_ kind: EvaluationKind, titled title: String) -> LibrarySource {
        LibrarySource(kind: .evaluationKind(kind), title: title)
    }

    public static func assetSet(_ id: AssetSetID, titled title: String) -> LibrarySource {
        LibrarySource(kind: .assetSet(id), title: title)
    }

    public static func workSession(_ id: WorkSessionID, titled title: String) -> LibrarySource {
        LibrarySource(kind: .workSession(id), title: title)
    }

    public static func importChild(session: WorkSessionID, child: ImportChildKind) -> LibrarySource {
        LibrarySource(kind: .importChild(session: session, child: child), title: child.title)
    }
}
```

- [ ] **Step 3: Delete `Workspace` and rewire `selectedView`**

In `Sources/TeststripApp/AppModel.swift`:

Delete the `LibraryViewMode: Codable` extension (`:22-44`) in full — no back-compat, so the legacy `"search"`/`"copilot"` shim goes, and Swift synthesizes the conformance from the raw value. Add `Codable` to the enum declaration at `:6`:

```swift
public enum LibraryViewMode: String, CaseIterable, Codable, Sendable {
```

Delete `public enum Workspace` (`:46-78`) and `extension LibraryViewMode { public var workspace: Workspace }` (`:80-89`) in full — `LibraryLens.swift` replaces both.

Replace `selectedView`'s `didSet` arm 1 (`:2063-2065`) with:

```swift
            // .compare/.abCompare aren't sticky restore targets (the ⌘1 dead-key
            // root cause): they're transient comparator overlays, not a "home"
            // sub-mode. Without this, re-pressing ⌘1 while trapped in A/B
            // Compare restored the trap instead of escaping it.
            if selectedView.lens == .cull, selectedView != .compare, selectedView != .abCompare {
                lastCullViewMode = selectedView
            }
```

Replace arm 4 (`:2068-2070`) with nothing — **delete it**. The sidebar no longer varies by lens, so a lens change cannot change its contents.

Replace arms 5 and 6's `workspace` references (`:2076`, `:2082-2083`) with `lens`:

```swift
            if oldValue.lens == .cull, selectedView.lens != .cull {
                lastCullingMetadataDecision = nil
            }
```

```swift
            if selectedView.lens == .cull,
               oldValue.lens != .cull,
               !hasShownCullKeyboardHint {
```

Replace `lastSubView` (`:2139`) with:

```swift
    /// The cull sub-mode to return to when the Cull lens is re-entered. The
    /// other five lenses have exactly one route each, so one property replaces
    /// the old per-workspace dictionary.
    private var lastCullViewMode: LibraryViewMode = .loupe
```

Replace `selectedWorkspace` (`:2099-2102`) with:

```swift
    /// Which lens `selectedView` currently belongs to.
    public var selectedLens: LibraryLens {
        selectedView.lens
    }
```

Replace `isCullingMenuShortcutActive` (`:2112-2114`) body with:

```swift
        CullingKeyCaptureGate.isActive(lens: selectedLens, selectedView: selectedView)
```

Replace `sidebarSections(for:)` (`:2116-2136`) with:

```swift
    /// One sidebar, every lens. Sources are nouns; lenses are verbs; the
    /// sidebar lists nouns, so it does not vary with the lens.
    public func sidebarSections() -> [SidebarSection] {
        Self.defaultSidebarSections(
            totalAssetCount: totalAssetCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            workSessionScopeCounts: workSessionScopeCounts,
            catalogFolders: catalogFolders,
            expandedFolderPaths: expandedFolderPaths,
            recentWork: recentWork,
            starredWork: starredWork,
            matchedWork: workHistorySearchResults
        )
    }
```

Replace `rebuildSidebarSections()` (`:13167-13169`) body with:

```swift
        sidebarSections = sidebarSections()
```

Replace `selectWorkspace(_:)` (`:4953-4957`) with:

```swift
    /// ⌘1–⌘6 and the toolbar switcher. Switching lenses never changes the
    /// selected source or the selection; the Cull lens returns to whichever
    /// sub-mode it was last in.
    public func selectLens(_ lens: LibraryLens) {
        selectedView = lens == .cull ? lastCullViewMode : lens.defaultViewMode
    }

    /// The switcher's per-lens enabled state for the current source.
    public var lensAvailabilities: [LensAvailability] {
        LensRules.availabilities(
            sourceIsDiagnostic: selectedSource.isDiagnostic,
            sourceAssetCount: assets.count
        )
    }
```

- [ ] **Step 4: Replace `SidebarRowTarget` with `LibrarySource`**

Delete `public enum SidebarRowTarget` (`AppModel.swift:990-1005`) in full.

In `SidebarRowContextActionKind` (`:1007-1014`) — unchanged.

In `SidebarRow` (`:1045-1085`), change the property, the initializer default, and `isSelectable`:

```swift
    public var target: LibrarySource?
```

```swift
        target: LibrarySource? = nil,
```

```swift
    public var isSelectable: Bool {
        target != nil
    }
```

In `ActiveLibraryFilterRow` (`:1093-1113`), change `public var target: SidebarRowTarget?` to `public var target: LibrarySource?` and its initializer parameter likewise.

Replace `selectSidebarRow(_:)` / `selectSidebarTarget(_:)` / `applySidebarTarget(_:)` (`AppModel.swift:4932-4934`, `4948-4951`, `5016-5076`) with:

```swift
    public func selectSidebarRow(_ row: SidebarRow) throws {
        guard let source = row.target else { return }
        try selectSource(source)
    }

    public func selectSource(_ source: LibrarySource) throws {
        try applySource(source)
        recordNavigation(to: source)
    }

    /// Applies a source's scope and records it as the selected source.
    /// Deliberately never touches `selectedView` except for the one spec'd
    /// exception: a source the current lens disables on falls back to Grid.
    private func applySource(_ source: LibrarySource) throws {
        switch source.kind {
        case .allPhotos:
            selectedAssetSetID = nil
            try clearLibraryFilters()
        case .search(let query):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            detachedLibraryFilterPredicates = query.predicates
            try reload()
        case .smartCollection(let queue):
            try applySmartCollection(queue)
        case .autopilotSuggestions:
            try beginAutopilotReview()
        case .folder(let path):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            folderFilterText = path
            try reload()
        case .sourceAvailability(let availability):
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            availabilityFilter = availability
            try reload()
        case .evaluationKind(let kind):
            try applyEvaluationKindFilter(kind)
        case .metadataSyncPending:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            metadataSyncPendingFilter = true
            try reload()
        case .metadataSyncConflicts:
            selectedAssetSetID = nil
            clearLibraryQueryFilters()
            metadataSyncConflictFilter = true
            try reload()
        case .assetSet(let id):
            try applyAssetSet(id: id)
        case .workSession(let id):
            try applyWorkSession(id: id)
        case .importChild(let sessionID, let child):
            try applyImportChild(sessionID: sessionID, child: child)
        case .selection:
            try applySelectionSource()
        }
        selectedSource = source
        let resolvedLens = LensRules.resolvedLens(
            selectedLens,
            sourceIsDiagnostic: source.isDiagnostic,
            sourceAssetCount: assets.count
        )
        if resolvedLens != selectedLens {
            selectLens(resolvedLens)
        }
    }
```

Add the stored source property immediately after `public var selectedView: LibraryViewMode { … }`'s closing brace (`:2095`):

```swift
    /// What the user is looking at, as opposed to how. Stored rather than
    /// reconstructed from filter state, so the scope line can name it and a
    /// relaunch can restore it.
    public private(set) var selectedSource: LibrarySource = .allPhotos
```

and initialize it in `AppModel.init` alongside `self.selectedView = selectedView` (`:4358`):

```swift
        self.selectedSource = .allPhotos
```

Add the two new apply helpers immediately after `applyWorkSession(id:)` (which ends `:5092`):

```swift
    /// An import row's disclosure child. The two diagnostic children have no
    /// catalog scope of their own — skipped files aren't in the catalog and a
    /// failed preview's frame is only interesting as a problem row — so they
    /// scope to the import and let the Grid render the issue list.
    private func applyImportChild(sessionID: WorkSessionID, child: ImportChildKind) throws {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        selectedAssetSetID = nil
        clearLibraryQueryFilters()
        switch child {
        case .stacks, .skippedFiles:
            detachedLibraryFilterPredicates = [.importBatch(sessionID.rawValue)]
        case .likelyIssues:
            detachedLibraryFilterPredicates =
                [.importBatch(sessionID.rawValue)] + SmartCollection.likelyIssues.query.predicates
        case .facesFound:
            detachedLibraryFilterPredicates =
                [.importBatch(sessionID.rawValue)] + SmartCollection.facesFound.query.predicates
        case .previewFailed:
            let importAssetIDs = try latestImportOutputAssetIDs(
                activityID: sessionID.rawValue,
                repository: catalog.repository
            )
            let failedAssetIDs = try catalog.repository.previewGenerationFailureAssetIDs(assetIDs: importAssetIDs)
            let setID = AssetSetID(rawValue: "import-preview-failed-\(sessionID.rawValue)")
            try catalog.repository.upsert(
                AssetSet.manual(id: setID, name: ImportChildKind.previewFailed.title, assetIDs: failedAssetIDs)
            )
            try applyAssetSet(id: setID)
            return
        }
        try reload()
    }

    /// The transient Selection source: the current batch selection, or the
    /// single selected frame.
    private func applySelectionSource() throws {
        let selectionIDs = selectedBatchAssetIDsInCatalogOrder.isEmpty
            ? (selectedAssetID.map { [$0] } ?? [])
            : selectedBatchAssetIDsInCatalogOrder
        guard !selectionIDs.isEmpty, let catalog else { return }
        let setID = AssetSetID(rawValue: "selection-source-\(UUID().uuidString)")
        try catalog.repository.upsert(
            AssetSet.manual(id: setID, name: "Selection", assetIDs: selectionIDs)
        )
        try applyAssetSet(id: setID)
    }
```

- [ ] **Step 5: Stop the four scope-appliers from changing the lens**

Delete the `selectedView = .grid` line from each of: `applySmartCollection(_:)` (`:11087`), `applyAssetSet(id:)` (`:5480`), `applyEvaluationKindFilter(_:)` (`:11035`). In `applyWorkSession(id:)`, delete the line

```swift
        selectedView = session.kind == .culling ? .loupe : .grid
```

Every cull entry point that relied on those (`beginCullingSession` `:5793`/`:5799`, `beginStackCullingFromLatestImportCompletion` `:5158`) already sets `selectedView = .loupe` itself, after the apply.

`revealConflicts(_:)` (`:3042-3061`) is a deep link with an explicit destination, not a plain source selection: keep its `selectedView = .grid` and add, immediately after it:

```swift
        selectedSource = .metadataSyncConflicts
```

`selectPlaceBounds(_:)` (`:11006`) is a Map drill-down with an explicit destination: keep its route change and add, immediately after it:

```swift
        selectedSource = .search(SetQuery(predicates: [.withinGeoBounds(bounds)]), titled: "Map area")
```

- [ ] **Step 6: Retype the navigation history and the predicate→source bridges**

Change the three navigation stacks (`AppModel.swift:2149-2151`):

```swift
    private var navigationBackStack: [LibrarySource] = []
    private var navigationForwardStack: [LibrarySource] = []
    private var currentNavigationTarget: LibrarySource?
```

Change `recordNavigation(to:)` (`:5000`) and `restoreNavigation(to:)` (`:5009`) parameter types from `SidebarRowTarget` to `LibrarySource`, and in `restoreNavigation` call `applySource(target)` instead of `applySidebarTarget(target)`.

Change `sidebarTarget(for predicate:)` (`:11413-11446`) to return `LibrarySource?` and rename it `librarySource(for predicate:)`, mapping each arm to the matching factory:

```swift
    private static func librarySource(for predicate: SetQuery.Predicate) -> LibrarySource? {
        switch predicate {
        case .ratingAtLeast(let rating):
            rating == 5 ? LibrarySource.smartCollection(.fiveStars) : nil
        case .flag(.pick):
            LibrarySource.smartCollection(.picks)
        case .flag(.reject):
            LibrarySource.smartCollection(.rejects)
        case .missingKeywords:
            LibrarySource.smartCollection(.needsKeywords)
        case .availability(let availability):
            LibrarySource.sourceAvailability(availability)
        case .evaluationKind(let kind):
            if let queue = smartCollection(forEvaluationKind: kind) {
                LibrarySource.smartCollection(queue)
            } else {
                LibrarySource.evaluationKind(kind, titled: kind.filterChipLabel)
            }
        case .unevaluated:
            LibrarySource.smartCollection(.needsEvaluation)
        case .likelyIssue:
            LibrarySource.smartCollection(.likelyIssues)
        case .likelyPick:
            LibrarySource.smartCollection(.potentialPicks)
        case .evaluationFailure:
            LibrarySource.smartCollection(.providerFailures)
        case .metadataSyncPending:
            LibrarySource.metadataSyncPending
        case .metadataSyncConflict:
            LibrarySource.metadataSyncConflicts
        case .importBatch(let id), .workSession(let id):
            LibrarySource.workSession(WorkSessionID(rawValue: id), titled: id)
        default:
            nil
        }
    }
```

Update every caller (`activeLibraryFilterRow(for:)` `:11338-11389`, `activeLibraryFilterRow(forEvaluationKind:)` `:11391-11396`, `activeLibraryFilterRows` `:3288`) to the new name and type. Keep every chip **title string byte-identical** — the tests compare them verbatim.

Update `canToggleWorkSessionStarred(_:)` (`:5265-5271`) and `sidebarContextActions(for:)` (`:5273-…`) to destructure `row.target?.kind` instead of `row.target`:

```swift
        guard catalog != nil,
              case .workSession(let id)? = row.target?.kind else {
            return false
        }
```

Update the sidebar row builders (`recentlyAddedSidebarRow` `:14336-14343`, `sidebarRow(for assetSet:count:)` `:14354-14363`, `workSidebarRows` `:14404-14414`, `folderTreeSidebarRows(for:depth:expandedFolderPaths:)` `:14219-14227`, `smartCollectionSidebarRows` `:14242-14247`, and the "All Photographs" row at `:14141-14146`) to pass a `LibrarySource`:

| Builder | New `target:` |
|---|---|
| All Photographs (`:14145`) | `.allPhotos` (and change its `title:` to `"All Photos"` to match the spec's Library section) |
| Recent Import (`:14342`) | `.workSession(WorkSessionID(rawValue: activity.id), titled: activity.detail.isEmpty ? "Latest import" : activity.detail)` |
| saved set (`:14361`) | `.assetSet(assetSet.id, titled: assetSet.name)` |
| work row (`:14412`) | `.workSession(sessionID, titled: workSidebarTitle(for: activity))` |
| folder row (`:14224`) | `.folder(node.fullPath)` |
| review queue row (`:14246`) | `.smartCollection(queue)` |

- [ ] **Step 7: Rename the chrome policy and the key gate**

In `Sources/TeststripApp/LibraryGridView.swift`, rename `enum WorkspaceChromePolicy` → `enum LensChromePolicy` (`:8357`), delete `showsLibraryViewToggle(_:)` (`:8377-8382`), and replace `showsBrowseChrome(_:)` (`:8361-8363`) with:

```swift
    /// The search field, filter tokens, import, footer, and the
    /// Cull/Export/More toolbar actions — everything a photographer uses to
    /// browse. The two focused lenses (Cull and People) carry none of it.
    static func showsBrowseChrome(_ view: LibraryViewMode) -> Bool {
        switch view.lens {
        case .grid, .loupe, .timeline, .map:
            return true
        case .cull, .people:
            return false
        }
    }
```

Update every `WorkspaceChromePolicy.` reference to `LensChromePolicy.` in `LibraryGridView.swift`, `LoupeZoomView.swift:273`, `main.swift:53`, and `AppModel.swift:2571`, `:2607`, `:4971`.

In `Sources/TeststripApp/CullingKeyCaptureView.swift`, replace `CullingKeyCaptureGate` (`:11-15`) with:

```swift
enum CullingKeyCaptureGate {
    static func isActive(lens: LibraryLens, selectedView: LibraryViewMode) -> Bool {
        lens == .cull && selectedView != .cullGrid
    }
}
```

and update the comment above it to say "the Cull lens" rather than "the Cull workspace". Update the call site at `LibraryGridView.swift:205`:

```swift
                isActive: CullingKeyCaptureGate.isActive(lens: model.selectedLens, selectedView: model.selectedView),
```

In `AppModel.requestFocusSearch()` (`:2570-2575`) and `requestExport()` (`:2606-2611`), change the bounce from `selectedView = .grid` to `selectLens(.grid)` and the policy name to `LensChromePolicy`.

- [ ] **Step 8: Replace the two switchers with one lens switcher**

In `Sources/TeststripApp/LibraryGridView.swift`, replace `workspaceSwitcher` (`:463-474`) with:

```swift
    /// The one lens control: Cull | Grid | Loupe | Timeline | Map | People,
    /// ⌘1–⌘6 in the same order. A lens the current source disables on renders
    /// disabled with its reason on hover.
    private var lensSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(model.lensAvailabilities, id: \.lens) { availability in
                Button {
                    model.selectLens(availability.lens)
                } label: {
                    Text(availability.lens.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(
                            model.selectedLens == availability.lens ? Color.white.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!availability.isEnabled)
                .help(availability.disabledReason ?? availability.lens.title)
                .accessibilityLabel(availability.lens.title)
                .accessibilityValue(model.selectedLens == availability.lens ? "Selected" : "Not selected")
            }
        }
        .padding(2)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lens")
    }
```

(A `Picker` cannot disable individual segments, which the spec requires — "a disabled lens is visibly disabled in the switcher with the reason on hover" — so this uses the same button-row idiom `thumbnailDensityControl` at `:521-548` already uses.)

Delete `librarySubViewToggle` (`:480-494`) in full.

At the toolbar mount (`:234-236`), change `workspaceSwitcher` to `lensSwitcher`.

In `libraryTopBar` (`:550-587`), delete the `if WorkspaceChromePolicy.showsLibraryViewToggle(model.selectedView) { librarySubViewToggle }` block (`:552-554`) and its leading `Spacer(minLength: 12)` becomes the first element. Replace `hasVisibleLibraryTopBarContent` (`:715-718`) with:

```swift
    private var hasVisibleLibraryTopBarContent: Bool {
        LensChromePolicy.showsImportButton(model.selectedView)
    }
```

- [ ] **Step 9: Rewire `main.swift`**

Replace `AppWindowLayoutMetrics` (`main.swift:5-23`) with:

```swift
struct AppWindowLayoutMetrics {
    /// One window, one floor. The per-workspace 1000/800 split went away with
    /// the Cull|Library split — there is no longer a workspace paying for
    /// another workspace's chrome.
    static let minimumWidth: CGFloat = 1_000
    static let defaultWidth: CGFloat = 1_520
    static let minimumHeight: CGFloat = 720
    static let defaultHeight: CGFloat = 820
}
```

Replace the sidebar branch (`:43-48`) with:

```swift
            NavigationSplitView {
                SidebarView(model: model)
            } detail: {
```

Replace the frame call (`:58-61`) with:

```swift
            .frame(
                minWidth: AppWindowLayoutMetrics.minimumWidth,
                minHeight: AppWindowLayoutMetrics.minimumHeight
            )
```

Replace `workspaceActionIDs` (`:108`) and `subViewMenuModes` (`:110-116`) with:

```swift
    static let lensActionIDs: [String] = LibraryLens.allCases.map(\.title)

    /// The Cull lens's transient sub-modes, which keep their own View-menu
    /// items below the lens divider. They are reached by g/c/b in the loupe;
    /// the menu items exist because menus are the system of record.
    static let cullSubModeMenuModes: [LibraryViewMode] = [.loupe, .cullGrid, .compare, .abCompare]
```

Replace the `LibraryViewMode.subViewMenuTitle` extension (`:158-183`) with:

```swift
extension LibraryViewMode {
    /// Title shown in the View menu's Cull sub-mode group. Nil for the five
    /// routes that are a lens's default — those are reached by ⌘1–⌘6.
    var cullSubModeMenuTitle: String? {
        switch self {
        case .loupe: return "Loupe"
        case .cullGrid: return "Cull Grid"
        case .compare: return "Compare"
        case .abCompare: return "A/B Compare"
        case .grid, .libraryLoupe, .timeline, .map, .people: return nil
        }
    }

    // The cull sub-mode keys (g/c/b) are owned solely by the in-view key
    // monitors (CullingKeyCaptureView in loupe/compare/A-B, GridKeyCaptureView
    // in the cull grid). Binding them here as bare menu key equivalents
    // dispatched a second, mode-blind `selectedView = mode` ~150ms after the
    // monitor's switch — from the cull grid, G flipped to loupe and the menu
    // equivalent immediately flipped back to cullGrid, making G/Esc appear
    // inert (run-cull-iter2 cull-008). Menus stay clickable; the ? key map
    // documents the keys.
}
```

Replace `WorkspaceCommands` (`:185-220`) with:

```swift
private struct LensCommands: Commands {
    var model: AppModel

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            ForEach(LibraryLens.allCases, id: \.self) { lens in
                Button(lens.title) {
                    model.selectLens(lens)
                }
                .keyboardShortcut(lens.keyEquivalent, modifiers: [.command])
            }

            Divider()

            // Menus stay the system of record even though the in-view key
            // captures also reach these routes.
            ForEach(AppMenuCoveragePresentation.cullSubModeMenuModes, id: \.self) { mode in
                cullSubModeButton(for: mode)
            }
        }
    }

    @ViewBuilder
    private func cullSubModeButton(for mode: LibraryViewMode) -> some View {
        if let title = mode.cullSubModeMenuTitle {
            Button(title) {
                model.selectedView = mode
            }
        }
    }
}
```

and change the `Group` wiring at `:79` from `WorkspaceCommands(model: model)` to `LensCommands(model: model)`.

- [ ] **Step 10: Rewire `SidebarView`**

In `Sources/TeststripApp/SidebarView.swift`, change `toggleFolderExpansion(_:)` (`:176-179`) to destructure through the new type:

```swift
    private func toggleFolderExpansion(_ row: SidebarRow) {
        guard case .folder(let path)? = row.target?.kind else { return }
        model.toggleFolderExpansion(path: path)
    }
```

Replace `sidebarRowButton(_:)`'s icon argument (`:206-209`) and `iconName(for:)` (`:346-377`) with:

```swift
    private func sidebarRowButton(_ row: SidebarRow) -> some View {
        Button {
            select(row)
        } label: {
            SidebarRowView(
                row: row,
                systemImage: iconName(for: row.target)
            )
        }
        .buttonStyle(.plain)
        .disabled(!row.isSelectable)
    }
```

```swift
    private func iconName(for source: LibrarySource?) -> String {
        guard let source else { return "circle" }
        switch source.kind {
        case .allPhotos:
            return "photo.on.rectangle"
        case .search:
            return "magnifyingglass"
        case .smartCollection(let queue):
            return queue.presentation.systemImage
        case .autopilotSuggestions:
            return "wand.and.stars"
        case .folder:
            return "folder"
        case .sourceAvailability:
            return "externaldrive.badge.exclamationmark"
        case .evaluationKind(let kind):
            return evaluationKindIconName(kind)
        case .metadataSyncPending:
            return "arrow.triangle.2.circlepath"
        case .metadataSyncConflicts:
            return "exclamationmark.triangle"
        case .assetSet:
            return "rectangle.stack"
        case .workSession:
            return "tray.and.arrow.down"
        case .importChild(_, let child):
            return child.systemImage
        case .selection:
            return "checkmark.circle"
        }
    }
```

Delete `smartCollectionIconName(_:)` (`:379-381`) — the switch above reads `queue.presentation.systemImage` directly.

- [ ] **Step 11: Run the new tests and verify they pass**

Run: `swift build 2>&1 | tail -40`
Expected: build succeeds. If anything still names `Workspace`, `selectedWorkspace`, `WorkspaceChromePolicy`, `SidebarRowTarget`, or `lastSubView`, the checklist above is incomplete. Verify with:

```bash
grep -rn "\bWorkspace\b\|selectedWorkspace\|selectWorkspace\|lastSubView\|WorkspaceChromePolicy\|SidebarRowTarget" --include="*.swift" Sources/
```
Expected: no hits.

Run: `swift test --filter LibraryLensTests && swift test --filter LibrarySourceTests`
Expected: 0 failures in both.

- [ ] **Step 12: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures.

- [ ] **Step 13: Commit**

```bash
git status
git add Sources/TeststripApp/
git commit -m "feat: lenses over sources replace the Cull|Library workspace split"
```

---

## Task 6A: One sidebar — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/UnifiedSidebarPresentationTests.swift` (create)
- Test: `Tests/TeststripAppTests/CullSourcePresentationTests.swift` (rewrite: delete every `cullSourcePresentation` test; keep the three `cullCurrentSelection` tests and rename the file's class)
- Test: `Tests/TeststripAppTests/SidebarSectionsTests.swift` (`:10-31` — the section list changes)

**Interfaces (what Task 6B must produce):**
- `public enum UnifiedSidebarPresentation` with:
  - `public static let allImportsRowID = "imports-all"`
  - `public static let importsSectionTitle = "Imports"`, `smartCollectionsSectionTitle = "Smart Collections"`, `setsSectionTitle = "Sets"`, `librarySectionTitle = "Library"`, `foldersSectionTitle = "Folders"`, `recentWorkSectionTitle = "Recent Work"`, `selectionSectionTitle = "Selection"`
  - `public static let recentImportRowLimit = 3`
  - `public static func visibleSavedAssetSets(_ assetSets: [AssetSet]) -> [AssetSet]`
  - `public static func sections(totalAssetCount:importSummaries:expandedImportSessionIDs:importChildCounts:isShowingAllImports:smartCollectionCounts:autopilotGhostCount:savedAssetSets:assetSetCounts:catalogFolders:expandedFolderPaths:recentWork:starredWork:matchedWork:workSessionScopeCounts:selectionCount:) -> [SidebarSection]`
- `AppModel.expandedImportSessionIDs: Set<String>` (`public private(set)`), `AppModel.isShowingAllImports: Bool` (`public private(set)`), `AppModel.importChildCountsBySessionID: [String: ImportChildCounts]` (`public private(set)`)
- `AppModel.toggleSidebarExpansion(_ row: SidebarRow)` — handles folder rows, import rows, and the "All imports…" overflow row.
- `AppModel.requestSaveSearch()` + `AppModel.saveSearchRequestToken: Int` (`public private(set)`) — the Smart Collections header's "+ New from search…", which opens the **existing** save-search popover.
- **Deleted:** `CullSource`, `CullSourceGroup`, `CullSourcePresentation`, `AppModel.cullSourcePresentation`, `AppModel.activateCullSource(_:)`, `AppModel.defaultSidebarSections(…)`, `AppModel.recentlyAddedSidebarRow(_:)`, `AppModel.mergedRecentWorkSidebarRows(…)`, `AppModel.smartCollectionSidebarRows(…)`, `Sources/TeststripApp/CullSidebarView.swift`.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the presentation test file**

Create `Tests/TeststripAppTests/UnifiedSidebarPresentationTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// One sidebar, top to bottom: Library, Imports, Smart Collections, Sets,
// Folders, Recent Work, Selection. Every count lives in exactly one place.
final class UnifiedSidebarPresentationTests: XCTestCase {
    private func summary(_ id: String, day: Int, count: Int, issues: Int = 0) -> ImportSourceSummary {
        ImportSourceSummary(
            sessionID: WorkSessionID(rawValue: id),
            createdAt: Date(timeIntervalSince1970: TimeInterval(day * 86_400)),
            detail: "Imported from /Cards/\(id)",
            assetCount: count,
            issues: (0..<issues).map { index in
                WorkSessionIssue(kind: .skippedSourceFile, sourceURL: nil, message: "skipped \(index)")
            }
        )
    }

    private func sections(
        importSummaries: [ImportSourceSummary] = [],
        expandedImportSessionIDs: Set<String> = [],
        importChildCounts: [String: ImportChildCounts] = [:],
        isShowingAllImports: Bool = false,
        smartCollectionCounts: [SmartCollection: Int] = [:],
        autopilotGhostCount: Int = 0,
        savedAssetSets: [AssetSet] = [],
        assetSetCounts: [AssetSetID: Int] = [:],
        selectionCount: Int = 0
    ) -> [SidebarSection] {
        UnifiedSidebarPresentation.sections(
            totalAssetCount: 42,
            importSummaries: importSummaries,
            expandedImportSessionIDs: expandedImportSessionIDs,
            importChildCounts: importChildCounts,
            isShowingAllImports: isShowingAllImports,
            smartCollectionCounts: smartCollectionCounts,
            autopilotGhostCount: autopilotGhostCount,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: [],
            expandedFolderPaths: [],
            recentWork: [],
            starredWork: [],
            matchedWork: [],
            workSessionScopeCounts: [:],
            selectionCount: selectionCount
        )
    }

    func testLibrarySectionAlwaysLeadsWithAllPhotos() {
        let library = try? XCTUnwrap(sections().first)
        XCTAssertEqual(library?.title, "Library")
        XCTAssertEqual(library?.rows.first?.title, "All Photos")
        XCTAssertEqual(library?.rows.first?.target, LibrarySource.allPhotos)
        XCTAssertEqual(library?.rows.first?.countText, "42")
    }

    func testImportsShowTheRecentThreePlusAnAllImportsOverflowRow() throws {
        let summaries = (0..<7).map { summary("import-\($0)", day: $0, count: 10 + $0) }.reversed()
        let imports = try XCTUnwrap(sections(importSummaries: Array(summaries)).first { $0.title == "Imports" })

        XCTAssertEqual(imports.rows.count, 4)
        XCTAssertEqual(imports.rows.prefix(3).map(\.countText), ["16", "15", "14"])
        let overflow = try XCTUnwrap(imports.rows.last)
        XCTAssertEqual(overflow.id, UnifiedSidebarPresentation.allImportsRowID)
        XCTAssertEqual(overflow.title, "All imports…")
        XCTAssertEqual(overflow.countText, "7")
        XCTAssertEqual(overflow.disclosure, .collapsed)
    }

    func testAllImportsExpandsToEveryImportWithoutAnOverflowRow() throws {
        let summaries = (0..<7).map { summary("import-\($0)", day: $0, count: 10) }.reversed()
        let imports = try XCTUnwrap(
            sections(importSummaries: Array(summaries), isShowingAllImports: true).first { $0.title == "Imports" }
        )

        XCTAssertEqual(imports.rows.count, 8)
        XCTAssertEqual(imports.rows.last?.disclosure, .expanded)
    }

    func testTheImportsSectionIsAbsentWithNoImports() {
        XCTAssertNil(sections().first { $0.title == "Imports" })
    }

    func testImportRowLabelCarriesTheDateAndFolderNotTheConstantTitle() throws {
        let imports = try XCTUnwrap(
            sections(importSummaries: [summary("import-a", day: 5, count: 3)]).first { $0.title == "Imports" }
        )

        let row = try XCTUnwrap(imports.rows.first)
        XCTAssertTrue(row.title.hasSuffix("Imported from /Cards/import-a"), row.title)
        XCTAssertNotEqual(row.title, "Import photos")
    }

    func testExpandedImportRendersOnlyItsNonzeroChildren() throws {
        let imports = try XCTUnwrap(
            sections(
                importSummaries: [summary("import-a", day: 5, count: 30, issues: 2)],
                expandedImportSessionIDs: ["import-a"],
                importChildCounts: [
                    "import-a": ImportChildCounts(
                        stacks: 4,
                        skippedFiles: 2,
                        previewFailed: 0,
                        likelyIssues: 3,
                        facesFound: 0
                    )
                ]
            ).first { $0.title == "Imports" }
        )

        let children = imports.rows.filter { $0.depth == 1 }
        XCTAssertEqual(children.map(\.title), ["Stacks", "⚠ Skipped files", "⚠ Likely issues"])
        XCTAssertEqual(children.map(\.countText), ["4", "2", "3"])
        XCTAssertEqual(imports.rows.first?.disclosure, .expanded)
    }

    func testWarningChildrenCarryTheWarningTone() throws {
        let imports = try XCTUnwrap(
            sections(
                importSummaries: [summary("import-a", day: 5, count: 30, issues: 1)],
                expandedImportSessionIDs: ["import-a"],
                importChildCounts: [
                    "import-a": ImportChildCounts(stacks: 1, skippedFiles: 1, previewFailed: 1, likelyIssues: 1, facesFound: 1)
                ]
            ).first { $0.title == "Imports" }
        )

        let tonesByTitle = Dictionary(
            uniqueKeysWithValues: imports.rows.filter { $0.depth == 1 }.map { ($0.title, $0.tone) }
        )
        XCTAssertEqual(tonesByTitle["Stacks"], .neutral)
        XCTAssertEqual(tonesByTitle["⚠ Skipped files"], .warning)
        XCTAssertEqual(tonesByTitle["⚠ Preview failed"], .warning)
        XCTAssertEqual(tonesByTitle["⚠ Likely issues"], .warning)
        XCTAssertEqual(tonesByTitle["Faces found"], .neutral)
    }

    func testCollapsedImportHasNoChildren() throws {
        let imports = try XCTUnwrap(
            sections(
                importSummaries: [summary("import-a", day: 5, count: 30)],
                importChildCounts: ["import-a": ImportChildCounts(stacks: 4)]
            ).first { $0.title == "Imports" }
        )

        XCTAssertTrue(imports.rows.allSatisfy { $0.depth == 0 })
        XCTAssertEqual(imports.rows.first?.disclosure, .collapsed)
    }

    func testSmartCollectionsHoldAllTenSmartCollectionsWithNonzeroCounts() throws {
        var counts: [SmartCollection: Int] = [:]
        for (index, queue) in SmartCollection.allCases.enumerated() {
            counts[queue] = index + 1
        }
        let smart = try XCTUnwrap(
            sections(smartCollectionCounts: counts).first { $0.title == "Smart Collections" }
        )

        XCTAssertEqual(smart.rows.count, 10)
        XCTAssertTrue(smart.rowTitles.contains("Analysis Failures"))
        XCTAssertTrue(smart.rowTitles.contains("Potential Picks"))
    }

    func testSmartCollectionsDropZeroCountQueuesAndShowAISuggestionsOnlyWhenGhostsExist() throws {
        let withoutGhosts = sections(smartCollectionCounts: [.picks: 2, .rejects: 0]).first { $0.title == "Smart Collections" }
        XCTAssertEqual(withoutGhosts?.rowTitles, ["Picks"])

        let withGhosts = try XCTUnwrap(
            sections(smartCollectionCounts: [.picks: 2], autopilotGhostCount: 5).first { $0.title == "Smart Collections" }
        )
        XCTAssertEqual(withGhosts.rowTitles, ["Picks", "AI Suggestions"])
        XCTAssertEqual(withGhosts.rows.last?.target, LibrarySource.autopilotSuggestions)
    }

    // A saved dynamic set IS a smart collection — that is what the header's
    // "+ New from search…" produces. Static membership belongs in Sets.
    func testDynamicSavedSetsJoinSmartCollectionsAndStaticOnesJoinSets() throws {
        let dynamic = AssetSet.dynamic(
            id: AssetSetID(rawValue: "dyn"),
            name: "Recent Keepers",
            query: SetQuery(predicates: [.flag(.pick)])
        )
        let manual = AssetSet.manual(id: AssetSetID(rawValue: "man"), name: "Portfolio", assetIDs: [])
        let starredManual = AssetSet(
            id: AssetSetID(rawValue: "star"),
            name: "Starred Set",
            membership: .snapshot([]),
            starred: true
        )
        let result = sections(
            smartCollectionCounts: [.picks: 1],
            savedAssetSets: [dynamic, manual, starredManual],
            assetSetCounts: [dynamic.id: 7, manual.id: 3, starredManual.id: 1]
        )

        let smart = try XCTUnwrap(result.first { $0.title == "Smart Collections" })
        XCTAssertTrue(smart.rowTitles.contains("Recent Keepers"))

        let sets = try XCTUnwrap(result.first { $0.title == "Sets" })
        XCTAssertEqual(sets.rowTitles, ["Starred Set", "Portfolio"], "starred sets sort first")
        XCTAssertFalse(sets.rowTitles.contains("Recent Keepers"))
    }

    func testInternalWorkSetsNeverAppear() {
        let output = AssetSet.manual(id: AssetSetID(rawValue: "work-output-1"), name: "Imported", assetIDs: [])
        let input = AssetSet.manual(id: AssetSetID(rawValue: "work-input-1"), name: "Cull input", assetIDs: [])
        let stack = AssetSet.manual(id: AssetSetID(rawValue: "work-stack-1"), name: "Stack 1", assetIDs: [])

        let result = sections(savedAssetSets: [output, input, stack])

        XCTAssertNil(result.first { $0.title == "Sets" })
    }

    func testSelectionSectionIsTransientAndLast() throws {
        XCTAssertNil(sections(selectionCount: 0).first { $0.title == "Selection" })

        let result = sections(selectionCount: 4)
        XCTAssertEqual(result.last?.title, "Selection")
        XCTAssertEqual(result.last?.rows.first?.countText, "4")
        XCTAssertEqual(result.last?.rows.first?.target, LibrarySource.selection)
    }

    func testSectionOrderIsLibraryImportsSmartCollectionsSetsSelection() {
        let result = sections(
            importSummaries: [summary("import-a", day: 1, count: 3)],
            smartCollectionCounts: [.picks: 1],
            savedAssetSets: [AssetSet.manual(id: AssetSetID(rawValue: "man"), name: "Portfolio", assetIDs: [])],
            assetSetCounts: [AssetSetID(rawValue: "man"): 3],
            selectionCount: 2
        )

        XCTAssertEqual(
            result.map(\.title),
            ["Library", "Imports", "Smart Collections", "Sets", "Selection"]
        )
    }
}
```

- [ ] **Step 2: Rewrite the cull-source tests and the section-list test**

In `Tests/TeststripAppTests/CullSourcePresentationTests.swift`: delete `testSourcesIncludeRecentImportAndBothSmartCollectionGroups`, `testSourcesIncludeRecentImportWhenLatestImportCompletionExists`, `testSourcesOmitAutopilotProposalsRowWhenNoneArePending`, `testSourcesIncludeAutopilotProposalsRowWhileProposalsArePending`, `testVisibleSourcesOmitsZeroCountRows`, and `testIsEmptyIsTrueOnlyWhenAllSourcesAreZeroCount` — the `CullSource*` types they exercise are gone, and `UnifiedSidebarPresentationTests` now owns "which sources exist and when". Rename the class to `CullSelectionSourceTests` and keep the three `cullCurrentSelection` tests unchanged. In your report, list this as a deliberate coverage move, not a loss, naming the replacement test for each deleted one.

In `Tests/TeststripAppTests/SidebarSectionsTests.swift`, replace `testLibrarySidebarSectionsAreExactlyCollectionsSavedSetsFolders` (`:10-31`) with:

```swift
    func testSidebarSectionsAreTheUnifiedShellsSections() throws {
        let asset = makeAsset(id: "hero", path: "/Photos/hero.jpg", rating: 5)
        let (model, _) = try makeModelWithCatalogAssets(named: "sidebar-sections-unified", assets: [asset])
        model.minimumRatingFilter = 5
        try model.applyLibraryFilters()
        _ = try model.saveCurrentLibraryQuery(named: "Five Stars", starred: false)
        model.catalogFolders = [CatalogFolder(path: "photos", name: "photos", assetCount: 1)]

        let sections = model.sidebarSections()

        XCTAssertEqual(sections.first?.title, "Library")
        XCTAssertEqual(sections.first?.rows.first?.title, "All Photos")
        XCTAssertEqual(sections.first?.rows.first?.target, LibrarySource.allPhotos)

        // A saved dynamic search is a smart collection, not a static set.
        let smart = try XCTUnwrap(sections.first { $0.title == "Smart Collections" })
        XCTAssertTrue(smart.rowTitles.contains("Five Stars"))
        XCTAssertNil(sections.first { $0.title == "Sets" })

        let folders = try XCTUnwrap(sections.first { $0.title == "Folders" })
        XCTAssertEqual(folders.rowTitles, ["photos"])
    }
```

and update `testSavedSetContextMenuActionsStillResolveUnderTheNewSidebarShape` (`:57-73`) to look the starred row up in the `"Smart Collections"` section instead of `"Collections"`.

- [ ] **Step 3: Run and verify the red**

Run: `swift test --filter UnifiedSidebarPresentationTests 2>&1 | tail -30`
Expected: **compile failure**, `cannot find 'UnifiedSidebarPresentation' in scope` and `type 'UnifiedSidebarPresentation' has no member 'sections'`.

Run: `swift test --filter SidebarSectionsTests 2>&1 | tail -20`
Expected: **compile failure**, `extra argument`/`incorrect argument label` on `sidebarSections()`.

Genuine reds. No falsification step is needed.

- [ ] **Step 4: Capture the red transcripts and the deleted-test rationale into your task report**

- [ ] **Step 5: Commit**

```bash
git status
git add Tests/TeststripAppTests/UnifiedSidebarPresentationTests.swift Tests/TeststripAppTests/CullSourcePresentationTests.swift Tests/TeststripAppTests/SidebarSectionsTests.swift
git commit -m "test: pin the unified sidebar's sections and import rows (red)"
```

---

## Task 6B: One sidebar — implementation

**Files:**
- Modify: `Sources/TeststripApp/UnifiedSidebarPresentation.swift` (add the composition to the file Task 2B created)
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/SidebarView.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (observe `saveSearchRequestToken`)
- Delete: `Sources/TeststripApp/CullSidebarView.swift`

**Interfaces:**
- Consumes: `LibrarySource`/`ImportChildKind` (Task 5B), `ImportSourceSummary`/`ImportChildCounts`/`AppModel.importSourceSummaries`/`AppModel.importChildCounts(sessionID:)` (Task 2B), `SmartCollection.presentation` (unchanged), `AppModel.autopilotGhostAssetIDs`, `AppModel.cullingStackListEntries()` (`:7072`), `AppModel.selectCullingStackSet(id:)`.
- Produces: everything in Task 6A's Interfaces block. Task 9B pulses the new import row.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Add the composition to `UnifiedSidebarPresentation.swift`**

Append to `Sources/TeststripApp/UnifiedSidebarPresentation.swift`:

```swift
/// The one sidebar, top to bottom: Library, Imports, Smart Collections, Sets,
/// Folders, Recent Work, Selection. Pure value logic — `SidebarView` is a thin
/// shell over this. Every count lives in exactly one place.
public enum UnifiedSidebarPresentation {
    public static let librarySectionTitle = "Library"
    public static let importsSectionTitle = "Imports"
    public static let smartCollectionsSectionTitle = "Smart Collections"
    public static let setsSectionTitle = "Sets"
    public static let foldersSectionTitle = "Folders"
    public static let recentWorkSectionTitle = "Recent Work"
    public static let selectionSectionTitle = "Selection"

    /// The Imports section shows this many rows plus an "All imports…"
    /// overflow row carrying the total.
    public static let recentImportRowLimit = 3
    public static let allImportsRowID = "imports-all"

    private static let smartCollectionOrder: [SmartCollection] = [
        .picks, .potentialPicks, .likelyIssues, .needsEvaluation,
        .rejects, .fiveStars, .needsKeywords, .facesFound, .ocrFound, .providerFailures
    ]

    /// Internal bookkeeping sets never appear as user-facing rows.
    public static func visibleSavedAssetSets(_ assetSets: [AssetSet]) -> [AssetSet] {
        assetSets.filter {
            !$0.id.rawValue.hasPrefix("work-output-")
                && !$0.id.rawValue.hasPrefix("work-input-")
                && !$0.id.rawValue.hasPrefix("work-stack-")
                && !$0.id.rawValue.hasPrefix("import-preview-failed-")
                && !$0.id.rawValue.hasPrefix("selection-source-")
                && !$0.id.rawValue.hasPrefix("cull-selection-")
        }
    }

    public static func countText(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }

    public static func sections(
        totalAssetCount: Int,
        importSummaries: [ImportSourceSummary],
        expandedImportSessionIDs: Set<String>,
        importChildCounts: [String: ImportChildCounts],
        isShowingAllImports: Bool,
        smartCollectionCounts: [SmartCollection: Int],
        autopilotGhostCount: Int,
        savedAssetSets: [AssetSet],
        assetSetCounts: [AssetSetID: Int],
        catalogFolders: [CatalogFolder],
        expandedFolderPaths: Set<String>,
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity],
        matchedWork: [AppWorkActivity],
        workSessionScopeCounts: [WorkSessionID: Int],
        selectionCount: Int
    ) -> [SidebarSection] {
        var sections: [SidebarSection] = [
            SidebarSection(title: librarySectionTitle, rows: [
                SidebarRow(
                    id: "library-all",
                    title: "All Photos",
                    countText: countText(totalAssetCount),
                    target: .allPhotos
                )
            ])
        ]

        let importRows = importSectionRows(
            importSummaries: importSummaries,
            expandedImportSessionIDs: expandedImportSessionIDs,
            importChildCounts: importChildCounts,
            isShowingAllImports: isShowingAllImports
        )
        if !importRows.isEmpty {
            sections.append(SidebarSection(title: importsSectionTitle, rows: importRows))
        }

        let visibleSets = visibleSavedAssetSets(savedAssetSets)
        var smartRows = smartCollectionOrder.compactMap { queue -> SidebarRow? in
            guard let count = smartCollectionCounts[queue], count > 0 else { return nil }
            return SidebarRow(
                id: "smart-\(queue.rawValue)",
                title: queue.presentation.title,
                countText: countText(count),
                tone: queue == .providerFailures ? .warning : .neutral,
                target: .smartCollection(queue)
            )
        }
        if autopilotGhostCount > 0 {
            smartRows.append(SidebarRow(
                id: "smart-ai-suggestions",
                title: "AI Suggestions",
                countText: countText(autopilotGhostCount),
                tone: .accent,
                target: .autopilotSuggestions
            ))
        }
        // A saved dynamic search IS a smart collection — that is exactly what
        // the section header's "+ New from search…" produces.
        smartRows.append(contentsOf: visibleSets.filter(\.isDynamic).map { assetSet in
            row(for: assetSet, count: assetSetCounts[assetSet.id])
        })
        if !smartRows.isEmpty {
            sections.append(SidebarSection(title: smartCollectionsSectionTitle, rows: smartRows))
        }

        // Sets are static membership only, starred first.
        let staticSets = visibleSets.filter { !$0.isDynamic }
        let setRows = (staticSets.filter(\.starred) + staticSets.filter { !$0.starred })
            .map { row(for: $0, count: assetSetCounts[$0.id]) }
        if !setRows.isEmpty {
            sections.append(SidebarSection(title: setsSectionTitle, rows: setRows))
        }

        if !catalogFolders.isEmpty {
            sections.append(SidebarSection(
                title: foldersSectionTitle,
                rows: folderRows(catalogFolders: catalogFolders, expandedFolderPaths: expandedFolderPaths)
            ))
        }

        // Imports have their own section, so Recent Work carries only the
        // other work kinds — culling, export, relocation, collecting.
        let workActivities = matchedWork.isEmpty
            ? mergedWorkActivities(recentWork: recentWork, starredWork: starredWork)
            : matchedWork
        let workRows = workActivities
            .filter { $0.kind != .ingest }
            .map { activity -> SidebarRow in
                let sessionID = WorkSessionID(rawValue: activity.id)
                return SidebarRow(
                    id: "work-\(activity.id)",
                    title: activity.title,
                    detailText: activity.sidebarDetailText,
                    countText: activity.sidebarCountText(scopeCount: workSessionScopeCounts[sessionID]),
                    tone: activity.sidebarTone,
                    target: .workSession(sessionID, titled: activity.title)
                )
            }
        if !workRows.isEmpty {
            sections.append(SidebarSection(title: recentWorkSectionTitle, rows: workRows))
        }

        if selectionCount > 0 {
            sections.append(SidebarSection(title: selectionSectionTitle, rows: [
                SidebarRow(
                    id: "selection",
                    title: "Selection",
                    countText: countText(selectionCount),
                    target: .selection
                )
            ]))
        }

        return sections
    }

    private static func importSectionRows(
        importSummaries: [ImportSourceSummary],
        expandedImportSessionIDs: Set<String>,
        importChildCounts: [String: ImportChildCounts],
        isShowingAllImports: Bool
    ) -> [SidebarRow] {
        guard !importSummaries.isEmpty else { return [] }
        let visible = isShowingAllImports ? importSummaries : Array(importSummaries.prefix(recentImportRowLimit))
        var rows: [SidebarRow] = []
        for summary in visible {
            let counts = importChildCounts[summary.sessionID.rawValue] ?? ImportChildCounts()
            let isExpanded = expandedImportSessionIDs.contains(summary.sessionID.rawValue)
            rows.append(SidebarRow(
                id: "import-\(summary.sessionID.rawValue)",
                title: summary.title,
                countText: countText(summary.assetCount),
                tone: summary.issues.isEmpty ? .neutral : .warning,
                target: .workSession(summary.sessionID, titled: summary.title),
                disclosure: counts.isEmpty ? .none : (isExpanded ? .expanded : .collapsed)
            ))
            guard isExpanded else { continue }
            rows.append(contentsOf: childRows(sessionID: summary.sessionID, counts: counts))
        }
        if importSummaries.count > recentImportRowLimit {
            rows.append(SidebarRow(
                id: allImportsRowID,
                title: "All imports…",
                countText: countText(importSummaries.count),
                target: nil,
                disclosure: isShowingAllImports ? .expanded : .collapsed
            ))
        }
        return rows
    }

    /// Children render only with nonzero counts, in a fixed order.
    private static func childRows(sessionID: WorkSessionID, counts: ImportChildCounts) -> [SidebarRow] {
        let ordered: [(ImportChildKind, Int)] = [
            (.stacks, counts.stacks),
            (.skippedFiles, counts.skippedFiles),
            (.previewFailed, counts.previewFailed),
            (.likelyIssues, counts.likelyIssues),
            (.facesFound, counts.facesFound)
        ]
        return ordered.compactMap { child, count in
            guard count > 0 else { return nil }
            return SidebarRow(
                id: "import-\(sessionID.rawValue)-\(child.rawValue)",
                title: child.title,
                countText: countText(count),
                tone: child.isDiagnostic || child == .likelyIssues ? .warning : .neutral,
                target: .importChild(session: sessionID, child: child),
                depth: 1
            )
        }
    }

    private static func row(for assetSet: AssetSet, count: Int?) -> SidebarRow {
        SidebarRow(
            id: "asset-set-\(assetSet.id.rawValue)",
            title: assetSet.name,
            detailText: assetSet.sidebarDetailText,
            countText: count.map(countText),
            tone: assetSet.isDynamic ? .accent : .neutral,
            target: .assetSet(assetSet.id, titled: assetSet.name)
        )
    }

    private static func mergedWorkActivities(
        recentWork: [AppWorkActivity],
        starredWork: [AppWorkActivity]
    ) -> [AppWorkActivity] {
        let recentSlice = Array(recentWork.prefix(5))
        let recentIDs = Set(recentSlice.map(\.id))
        return recentSlice + starredWork.filter { !recentIDs.contains($0.id) }.prefix(5)
    }

    private static func folderRows(
        catalogFolders: [CatalogFolder],
        expandedFolderPaths: Set<String>
    ) -> [SidebarRow] {
        FolderTreePresentation.build(from: catalogFolders).flatMap { node in
            folderRows(for: node, depth: 0, expandedFolderPaths: expandedFolderPaths)
        }
    }

    private static func folderRows(
        for node: FolderTreeNode,
        depth: Int,
        expandedFolderPaths: Set<String>
    ) -> [SidebarRow] {
        let isExpanded = expandedFolderPaths.contains(node.fullPath)
        let disclosure: SidebarRowDisclosure = node.hasChildren ? (isExpanded ? .expanded : .collapsed) : .none
        let row = SidebarRow(
            id: "folder-\(node.fullPath)",
            title: node.title,
            detailText: node.fullPath,
            countText: countText(node.assetCount),
            target: .folder(node.fullPath),
            depth: depth,
            disclosure: disclosure
        )
        guard isExpanded else { return [row] }
        return [row] + node.children.flatMap {
            folderRows(for: $0, depth: depth + 1, expandedFolderPaths: expandedFolderPaths)
        }
    }
}
```

- [ ] **Step 2: Rewire `AppModel.sidebarSections()` and delete the old composition**

In `Sources/TeststripApp/AppModel.swift`, replace `sidebarSections()` (written in Task 5B) with:

```swift
    public func sidebarSections() -> [SidebarSection] {
        UnifiedSidebarPresentation.sections(
            totalAssetCount: totalAssetCount,
            importSummaries: importSourceSummaries,
            expandedImportSessionIDs: expandedImportSessionIDs,
            importChildCounts: importChildCountsBySessionID,
            isShowingAllImports: isShowingAllImports,
            smartCollectionCounts: smartCollectionCounts,
            autopilotGhostCount: autopilotGhostAssetIDs.count,
            savedAssetSets: savedAssetSets,
            assetSetCounts: assetSetCounts,
            catalogFolders: catalogFolders,
            expandedFolderPaths: expandedFolderPaths,
            recentWork: recentWork,
            starredWork: starredWork,
            matchedWork: workHistorySearchResults,
            workSessionScopeCounts: workSessionScopeCounts,
            selectionCount: selectedBatchAssetIDs.isEmpty
                ? (selectedAssetID != nil ? 1 : 0)
                : selectedBatchAssetIDs.count
        )
    }
```

Delete in full: `defaultSidebarSections(…)` (`:14113-14182`), `mergedRecentWorkSidebarRows(…)` (`:14187-14197`), `folderTreeSidebarRows(catalogFolders:expandedFolderPaths:)` and `folderTreeSidebarRows(for:depth:expandedFolderPaths:)` (`:14203-14234`), `smartCollectionSidebarRows(smartCollectionCounts:)` (`:14236-14249`), `recentlyAddedSidebarRow(_:)` (`:14328-14344`), `sidebarRow(for assetSet:count:)` (`:14354-14363`), `workSidebarRows(for:idPrefix:scopeCounts:)` (`:14399-14415`), `sidebarCountText(_:)` (`:14417-14419`), `workSidebarTitle(for:)` (`:14421-14428`), and `visibleSavedAssetSets(_:)` (`:14346-14352`).

Repoint the two surviving `visibleSavedAssetSets` callers — `starredAssetSets` (`:3248-3250`) and `assetSetCounts(_:repository:)` (`:14365-14372`) — at `UnifiedSidebarPresentation.visibleSavedAssetSets(_:)`. Repoint the two `AppModel.sidebarCountText` calls inside `AppWorkActivity.sidebarCountText(scopeCount:)` (`:14495`, `:14498`) at `UnifiedSidebarPresentation.countText(_:)`.

The three row-decorating extensions at the bottom of `AppModel.swift` are `private extension`, so a second file cannot see them. Drop the `private` keyword from `private extension AssetSet` (`:14462`) and `private extension AppWorkActivity` (`:14475`) so `UnifiedSidebarPresentation` can read `sidebarDetailText`, `sidebarCountText(scopeCount:)`, and `sidebarTone`. Leave their bodies untouched.

Fix the three `defaultSidebarSections(...)` call sites in `AppModel.init` (`:4341-4358`), `AppModel.demo()` (`:4548`), and `AppModel.load(repository:)` (`:4578-4594`) / `load(catalog:…)`: replace each with `[]` and let the first `rebuildSidebarSections()` fill them — every one of those paths already reaches `rebuildSidebarSections()` before the view renders. In `demo()` call `rebuildSidebarSections()` explicitly before returning.

- [ ] **Step 3: Add the expansion state and the save-search token**

Add immediately after `importSourceSummaries` (Task 2B's property):

```swift
    /// Which import rows are disclosed. Child counts are queried lazily, only
    /// for expanded rows, so a catalog with hundreds of imports does not pay
    /// five queries per row on every sidebar rebuild.
    public private(set) var expandedImportSessionIDs: Set<String> = []
    public private(set) var importChildCountsBySessionID: [String: ImportChildCounts] = [:]
    /// Whether the Imports section is showing every import rather than the
    /// three most recent plus the overflow row.
    public private(set) var isShowingAllImports = false
```

Add next to the other request tokens (after `newSetFromSelectionRequestToken`, `:2622-2625`):

```swift
    /// Bumped by the Smart Collections header's "+ New from search…", which
    /// opens the existing save-search popover rather than a second builder.
    public private(set) var saveSearchRequestToken = 0
    public func requestSaveSearch() {
        saveSearchRequestToken += 1
    }
```

Add next to `toggleFolderExpansion(path:)` (`:4939-4946`):

```swift
    /// One disclosure gesture for every tree-shaped sidebar row: Folders,
    /// import rows, and the "All imports…" overflow row. Purely a rendering
    /// concern, so it never reloads the library scope.
    public func toggleSidebarExpansion(_ row: SidebarRow) {
        if case .folder(let path)? = row.target?.kind {
            toggleFolderExpansion(path: path)
            return
        }
        if case .workSession(let sessionID)? = row.target?.kind {
            if expandedImportSessionIDs.contains(sessionID.rawValue) {
                expandedImportSessionIDs.remove(sessionID.rawValue)
            } else {
                expandedImportSessionIDs.insert(sessionID.rawValue)
                importChildCountsBySessionID[sessionID.rawValue] =
                    (try? importChildCounts(sessionID: sessionID)) ?? ImportChildCounts()
            }
            rebuildSidebarSections()
            return
        }
        if row.id == UnifiedSidebarPresentation.allImportsRowID {
            isShowingAllImports.toggle()
            rebuildSidebarSections()
        }
    }
```

- [ ] **Step 4: Delete the Cull sidebar and its source list**

```bash
git rm Sources/TeststripApp/CullSidebarView.swift
```

In `AppModel.swift`, delete `public enum CullSourceGroup` (`:715-727`), `public struct CullSource` (`:729-752`), `public struct CullSourcePresentation` (`:754-771`), `public var cullSourcePresentation` (`:5868-5937`), and `public func activateCullSource(_:)` (`:5848-5866`). Their behaviour is now: sidebar rows (Task 6B) plus `selectSource(_:)` (Task 5B); `.autopilotProposals` is reachable as `LibrarySource.autopilotSuggestions`, whose `applySource` arm calls `beginAutopilotReview()`.

- [ ] **Step 5: Render the new sidebar**

In `Sources/TeststripApp/SidebarView.swift`:

Replace the `savedSetsSectionTitle` constant (`:22`) and `savedSetsSectionHeader(title:)` (`:86-108`) so the "+" affordance is section-driven:

```swift
    // Two sections carry a creation affordance: Sets (save the current
    // selection) and Smart Collections (save the current search). Both reuse
    // the popovers the result header's Save ▾ menu already opens.
    private static let setsSectionTitle = UnifiedSidebarPresentation.setsSectionTitle
    private static let smartCollectionsSectionTitle = UnifiedSidebarPresentation.smartCollectionsSectionTitle
```

```swift
    @ViewBuilder
    private func sectionHeader(title: String) -> some View {
        switch title {
        case Self.setsSectionTitle:
            headerWithAddButton(
                title: title,
                help: "New Set from Selection…",
                accessibilityLabel: "New Set from Selection",
                action: addSavedSetTapped
            )
        case Self.smartCollectionsSectionTitle:
            headerWithAddButton(
                title: title,
                help: "New from search…",
                accessibilityLabel: "New from search",
                action: { model.requestSaveSearch() }
            )
        default:
            Text(title)
        }
    }

    private func headerWithAddButton(
        title: String,
        help: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.plain)
            .help(help)
            .accessibilityLabel(accessibilityLabel)
            .popover(isPresented: $isShowingSavedSetsNoSelectionHint) {
                VStack(spacing: 12) {
                    Text("Select photos, then save them as a set")
                    Button("OK") {
                        isShowingSavedSetsNoSelectionHint = false
                    }
                }
                .padding()
            }
        }
    }
```

and change the `header:` closure in `body` (`:35-41`) to `sectionHeader(title: section.title)`.

Replace `folderDisclosureControl(for:)`'s action (`:221-222`) so it calls the generalized toggle, and rename it `disclosureControl(for:)`:

```swift
            Button {
                model.toggleSidebarExpansion(row)
            } label: {
```

Update `sidebarRowContent(_:)` (`:189-200`) to call `disclosureControl(for:)`, and delete `toggleFolderExpansion(_:)` (`:176-179`) — `toggleSidebarExpansion` subsumes it.

Append the cull stack list below the data-driven sections, inside the `List` in `body` (immediately after the `ForEach(model.sidebarSections)` block at `:42`). This is the "Stacks · Auto-Grouped" section moved verbatim out of the deleted `CullSidebarView`; it is a run surface rather than a source list, so it stays outside `sidebarSections`:

```swift
            let stackEntries = model.cullingStackListEntries()
            if !stackEntries.isEmpty {
                Section("Stacks · Auto-Grouped") {
                    ForEach(stackEntries) { entry in
                        stackRow(entry)
                    }
                }
            }
```

and copy `private func stackRow(_ entry: CullingStackListEntry) -> some View` verbatim from the deleted `CullSidebarView.swift:76-124` into `SidebarView`.

- [ ] **Step 6: Wire the save-search token**

In `Sources/TeststripApp/LibraryGridView.swift`, add next to the other request-token observers (after `.onChange(of: model.newSetFromSelectionRequestToken)` at `:152-154`):

```swift
        .onChange(of: model.saveSearchRequestToken) { _, _ in
            showSaveSearchPopover()
        }
```

- [ ] **Step 7: Keep the sidebar fresh**

In `refreshCatalogSidebarCounts()` (`:13210-13217`), add immediately before `rebuildSidebarSections()`:

```swift
        for sessionID in expandedImportSessionIDs {
            importChildCountsBySessionID[sessionID] =
                (try? importChildCounts(sessionID: WorkSessionID(rawValue: sessionID))) ?? ImportChildCounts()
        }
```

- [ ] **Step 8: Run the new tests and verify they pass**

Run: `swift test --filter UnifiedSidebarPresentationTests && swift test --filter SidebarSectionsTests && swift test --filter CullSelectionSourceTests`
Expected: 0 failures.

Verify the deletions are complete:

```bash
grep -rn "CullSource\|cullSourcePresentation\|activateCullSource\|defaultSidebarSections\|CullSidebarView" --include="*.swift" Sources/
```
Expected: no hits.

- [ ] **Step 9: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures.

- [ ] **Step 10: Commit**

```bash
git status
git add Sources/TeststripApp/
git commit -m "feat: one sidebar of sources — Library, Imports, Smart Collections, Sets, Selection"
```

---

## Task 7A: Cull these, and the scope line — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/ScopeLinePresentationTests.swift` (create)
- Test: `Tests/TeststripAppTests/LibrarySourceTests.swift` (append the handoff tests)

**Interfaces (what Task 7B must produce):**
- `public struct ScopeLinePresentation: Equatable, Sendable { public var sourceTitle: String; public var statusText: String }` with
  `public static func line(source: LibrarySource, lens: LibraryLens, resultCount: Int, activeFilterChips: [String], cullProgress: CullingProgressSummary?, stackCount: Int) -> ScopeLinePresentation`
- `AppModel.scopeLine: ScopeLinePresentation` — the assembled line the view renders.
- `AppModel.cullCurrentResults() throws -> WorkSession` (`@discardableResult`) — the "Cull these" action.
- `AppModel.canCullCurrentResults: Bool` — `canBeginCullingSession && !selectedSource.isDiagnostic`.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the scope-line test file**

Create `Tests/TeststripAppTests/ScopeLinePresentationTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// A persistent line under the toolbar names the source and shows
// lens-appropriate status: run progress in Cull, result count and active
// filters in the browse lenses.
final class ScopeLinePresentationTests: XCTestCase {
    func testBrowseLensesShowTheResultCount() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .grid,
            resultCount: 42,
            activeFilterChips: [],
            cullProgress: nil,
            stackCount: 0
        )

        XCTAssertEqual(line.sourceTitle, "All Photos")
        XCTAssertEqual(line.statusText, "42 photos")
    }

    func testBrowseLensesAppendActiveFilters() {
        let line = ScopeLinePresentation.line(
            source: .smartCollection(.likelyIssues),
            lens: .grid,
            resultCount: 1,
            activeFilterChips: ["Likely Issues", "Pick"],
            cullProgress: nil,
            stackCount: 0
        )

        XCTAssertEqual(line.sourceTitle, "Likely Issues")
        XCTAssertEqual(line.statusText, "1 photo · Likely Issues + Pick")
    }

    func testTheCullLensShowsRunProgress() {
        let line = ScopeLinePresentation.line(
            source: .workSession(WorkSessionID(rawValue: "import-1"), titled: "Aug 7 · Imported from /Cards/A"),
            lens: .cull,
            resultCount: 854,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 854",
                pickCount: 15,
                rejectCount: 5,
                totalCount: 854
            ),
            stackCount: 326
        )

        XCTAssertEqual(line.sourceTitle, "Aug 7 · Imported from /Cards/A")
        XCTAssertEqual(line.statusText, "854 photos · 326 stacks · ✓ 15 · ✕ 5 · 834 left")
    }

    func testTheCullLensOmitsStacksWhenThereAreNone() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 4,
            activeFilterChips: [],
            cullProgress: CullingProgressSummary(
                selectedPosition: 1,
                positionText: "1 of 4",
                pickCount: 1,
                rejectCount: 1,
                totalCount: 4
            ),
            stackCount: 0
        )

        XCTAssertEqual(line.statusText, "4 photos · ✓ 1 · ✕ 1 · 2 left")
    }

    func testTheCullLensFallsBackToTheResultCountWithNoRun() {
        let line = ScopeLinePresentation.line(
            source: .allPhotos,
            lens: .cull,
            resultCount: 9,
            activeFilterChips: [],
            cullProgress: nil,
            stackCount: 0
        )

        XCTAssertEqual(line.statusText, "9 photos")
    }

    func testTheLineAlwaysNamesTheSourceInEveryLens() {
        for lens in LibraryLens.allCases {
            let line = ScopeLinePresentation.line(
                source: .folder("/Photos/2026"),
                lens: lens,
                resultCount: 3,
                activeFilterChips: [],
                cullProgress: nil,
                stackCount: 0
            )
            XCTAssertEqual(line.sourceTitle, "2026", "\(lens)")
        }
    }
}
```

- [ ] **Step 2: Append the handoff tests to `LibrarySourceTests.swift`**

```swift
    // MARK: - Cull these

    // The handoff travels as a SetQuery. The text serializer silently drops
    // .likelyPick, .likelyIssue, .evaluationFailure, and .withinGeoBounds — a
    // handoff routed through librarySearchText would lose the scope.
    func testCullTheseHandsTheResultSetToTheCullLensAsASetQuery() throws {
        let pick = makeAsset(id: "cull-these-pick", path: "/Photos/a.jpg")
        let plain = makeAsset(id: "cull-these-plain", path: "/Photos/b.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "cull-these-handoff", assets: [pick, plain])
        try repository.updateMetadata(assetID: pick.id) { metadata in
            metadata.flag = .pick
        }
        try model.selectSource(.smartCollection(.picks))
        XCTAssertEqual(model.assets.map(\.id), [pick.id])

        _ = try model.cullCurrentResults()

        XCTAssertEqual(model.selectedLens, .cull)
        XCTAssertEqual(model.assets.map(\.id), [pick.id])
        guard case .search(let query) = model.selectedSource.kind else {
            return XCTFail("expected the handed-off search to become the source, got \(model.selectedSource.kind)")
        }
        XCTAssertTrue(query.predicates.contains(.flag(.pick)))
    }

    func testCullTheseSurvivesThePredicatesTheTextSerializerWouldDrop() throws {
        let asset = makeAsset(id: "cull-these-lossy", path: "/Photos/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-these-lossy", assets: [asset])
        try model.selectSource(.smartCollection(.potentialPicks))

        _ = try? model.cullCurrentResults()

        guard case .search(let query) = model.selectedSource.kind else {
            return XCTFail("expected a search source")
        }
        XCTAssertTrue(
            query.predicates.contains(.likelyPick),
            "`.likelyPick` has no text form at all — routing the handoff through text loses it silently"
        )
    }

    func testCullTheseIsUnavailableOnADiagnosticSource() throws {
        let asset = makeAsset(id: "cull-these-diagnostic", path: "/Photos/a.jpg")
        let (model, _) = try makeModelWithCatalogAssets(named: "cull-these-diagnostic", assets: [asset])

        try model.selectSource(.smartCollection(.providerFailures))

        XCTAssertFalse(model.canCullCurrentResults)
    }

    func testTheScopeLineNamesTheHandedOffSearch() throws {
        let pick = makeAsset(id: "scope-line-pick", path: "/Photos/a.jpg")
        let (model, repository) = try makeModelWithCatalogAssets(named: "cull-these-scope-line", assets: [pick])
        try repository.updateMetadata(assetID: pick.id) { metadata in
            metadata.flag = .pick
        }
        try model.selectSource(.smartCollection(.picks))

        _ = try model.cullCurrentResults()

        XCTAssertEqual(model.scopeLine.sourceTitle, "Pick")
    }
```

**Before running, confirm the metadata-write helper:**

```bash
grep -n "public func updateMetadata(assetID" Sources/TeststripCore/Catalog/CatalogRepository.swift
```

If the label differs, adapt only the two `updateMetadata` calls and say so in your report.

- [ ] **Step 3: Run and verify the red**

Run: `swift test --filter ScopeLinePresentationTests 2>&1 | tail -30`
Expected: **compile failure**, `cannot find 'ScopeLinePresentation' in scope`.

Run: `swift test --filter LibrarySourceTests 2>&1 | tail -30`
Expected: **compile failure**, `value of type 'AppModel' has no member 'cullCurrentResults'` / `'canCullCurrentResults'` / `'scopeLine'`.

Genuine reds. No falsification step is needed.

- [ ] **Step 4: Capture the red transcripts into your task report**

- [ ] **Step 5: Commit**

```bash
git status
git add Tests/TeststripAppTests/ScopeLinePresentationTests.swift Tests/TeststripAppTests/LibrarySourceTests.swift
git commit -m "test: pin the Cull-these handoff and the scope line (red)"
```

---

## Task 7B: Cull these, and the scope line — implementation

**Files:**
- Create: `Sources/TeststripApp/ScopeLinePresentation.swift`
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift`

**Interfaces:**
- Consumes: `LibrarySource`, `LibraryLens` (Task 5B), `currentLibraryQuery()` (`:11663`), `selectedExplicitAssetIDs`, `beginCullingSession(named:intent:)` (`:5768`), `cullingProgressSummary` (`:2766`), `cullingStackListEntries()` (`:7072`), `activeLibraryFilterChips` (`:3260`), `canBeginCullingSession` (`:3379`).
- Produces: `ScopeLinePresentation`, `AppModel.scopeLine`, `AppModel.cullCurrentResults()`, `AppModel.canCullCurrentResults`.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Create `ScopeLinePresentation.swift`**

```swift
import Foundation
import TeststripCore

/// The persistent line under the toolbar: what you are looking at, and
/// lens-appropriate status about it. Pure value logic — the view is a thin
/// shell over this.
public struct ScopeLinePresentation: Equatable, Sendable {
    public var sourceTitle: String
    public var statusText: String

    public init(sourceTitle: String, statusText: String) {
        self.sourceTitle = sourceTitle
        self.statusText = statusText
    }

    public static func line(
        source: LibrarySource,
        lens: LibraryLens,
        resultCount: Int,
        activeFilterChips: [String],
        cullProgress: CullingProgressSummary?,
        stackCount: Int
    ) -> ScopeLinePresentation {
        ScopeLinePresentation(
            sourceTitle: source.title,
            statusText: lens == .cull
                ? cullStatusText(resultCount: resultCount, cullProgress: cullProgress, stackCount: stackCount)
                : browseStatusText(resultCount: resultCount, activeFilterChips: activeFilterChips)
        )
    }

    private static func photoCountText(_ count: Int) -> String {
        "\(count) \(count == 1 ? "photo" : "photos")"
    }

    private static func browseStatusText(resultCount: Int, activeFilterChips: [String]) -> String {
        let count = photoCountText(resultCount)
        guard !activeFilterChips.isEmpty else { return count }
        return "\(count) · \(activeFilterChips.joined(separator: " + "))"
    }

    /// "854 photos · 326 stacks · ✓ 15 · ✕ 5 · 834 left". The stack segment is
    /// omitted when the run has no multi-frame stacks, and the whole progress
    /// tail is omitted when no run is under way.
    private static func cullStatusText(
        resultCount: Int,
        cullProgress: CullingProgressSummary?,
        stackCount: Int
    ) -> String {
        guard let cullProgress else { return photoCountText(resultCount) }
        var segments = [photoCountText(cullProgress.totalCount)]
        if stackCount > 0 {
            segments.append("\(stackCount) \(stackCount == 1 ? "stack" : "stacks")")
        }
        segments.append("✓ \(cullProgress.pickCount)")
        segments.append("✕ \(cullProgress.rejectCount)")
        segments.append("\(max(cullProgress.totalCount - cullProgress.reviewedCount, 0)) left")
        return segments.joined(separator: " · ")
    }
}
```

- [ ] **Step 2: Add the model surface**

In `Sources/TeststripApp/AppModel.swift`, add immediately after `canBeginCullingSession` (`:3379-3381`):

```swift
    /// The Cull lens's "Cull these" is unavailable on diagnostic sources —
    /// nothing there is cullable — and on an empty scope.
    public var canCullCurrentResults: Bool {
        canBeginCullingSession && !selectedSource.isDiagnostic
    }

    /// The persistent scope line under the toolbar.
    public var scopeLine: ScopeLinePresentation {
        ScopeLinePresentation.line(
            source: selectedSource,
            lens: selectedLens,
            resultCount: totalAssetCount,
            activeFilterChips: activeLibraryFilterChips,
            cullProgress: activeCullingSessionID == nil ? nil : cullingProgressSummary,
            stackCount: activeCullingSessionID == nil ? 0 : cullingStackListEntries().count
        )
    }
```

Add immediately after `cullCurrentSelection()` (which ends `:5846`):

```swift
    /// "Cull these": hands the current result set to the Cull lens as its
    /// source. The handoff travels as a `SetQuery`, never through the text
    /// serializer — `searchTextToken(for:)` returns nil for `.likelyPick`,
    /// `.likelyIssue`, `.evaluationFailure`, and `.withinGeoBounds`, so a
    /// text round trip would silently widen the scope.
    ///
    /// The scope must be applied and loaded before a run can start
    /// (`beginCullingSession` guards on `assets.isEmpty` and reads the current
    /// scope's count), so this is a re-scope followed by a session start, not
    /// a pure state change.
    @discardableResult
    public func cullCurrentResults() throws -> WorkSession {
        let title = cullTheseSourceTitle()
        if selectedExplicitAssetIDs == nil, let query = currentLibraryQuery() {
            try selectSource(.search(query, titled: title))
        }
        // An explicit-id scope (a saved set, the selection) already *is* the
        // source; there is nothing to re-scope.
        return try beginCullingSession(named: title)
    }

    private func cullTheseSourceTitle() -> String {
        let chips = activeLibraryFilterChips
        return chips.isEmpty ? selectedSource.title : chips.joined(separator: " + ")
    }
```

- [ ] **Step 3: Render the scope line and the Cull-these action**

In `Sources/TeststripApp/LibraryGridView.swift`, add this view next to `libraryResultHeader` (`:831`):

```swift
    /// Persistent in every lens: what you are looking at, and lens-appropriate
    /// status about it.
    private var scopeLineBar: some View {
        let presentation = model.scopeLine
        return HStack(spacing: 8) {
            Text(presentation.sourceTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(presentation.statusText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(.bar)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scope")
        .accessibilityValue("\(presentation.sourceTitle), \(presentation.statusText)")
    }
```

In `topInsetContent` (`:720-739`), put the scope line **outside** the browse-chrome gate so it renders in every lens, immediately after the `libraryTopBar` block:

```swift
    @ViewBuilder
    private var topInsetContent: some View {
        VStack(spacing: 0) {
            if hasVisibleLibraryTopBarContent {
                libraryTopBar
            }
            scopeLineBar
            if LensChromePolicy.showsFilterTokens(model.selectedView) {
                libraryQueryBar
                if libraryResultHeaderPresentation.hasContent {
                    libraryResultHeader
                }
            }
            if let summary = visibleImportCompletionSummary {
                importCompletionSummary(summary)
            }
        }
    }
```

In `libraryResultHeader` (`:831-860`), add the one new action immediately before `saveMenu(presentation.saveActions)`:

```swift
            Button("Cull these") {
                cullCurrentResults()
            }
            .buttonStyle(.borderless)
            .disabled(!model.canCullCurrentResults)
            .help("Cull the photos this search found")
            .accessibilityLabel("Cull these")
```

and add the wrapper next to `performSaveAction(_:)` (`:900-909`):

```swift
    private func cullCurrentResults() {
        do {
            try model.cullCurrentResults()
            focusCullingSurface()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 4: Run the new tests and verify they pass**

Run: `swift test --filter ScopeLinePresentationTests && swift test --filter LibrarySourceTests`
Expected: 0 failures.

- [ ] **Step 5: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures.

- [ ] **Step 6: Commit**

```bash
git status
git add Sources/TeststripApp/ScopeLinePresentation.swift Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: Cull these hands the result set to the Cull lens, and a scope line names the source"
```

---

## Task 8A: Session restore returns source + lens — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/SessionRestoreStateTests.swift` (rewrite the literals)
- Test: `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift` (`:290-312` literal; add three tests)

**Interfaces (what Task 8B must produce):**
- `SessionRestoreState.currentVersion = 2`.
- `SessionRestoreState` replaces `selectedView: LibraryViewMode` with **`lens: LibraryLens`** and adds **`source: LibrarySource`**, both as the first two stored properties after `version`. Every other field is unchanged (including `detachedFilterPredicates` from Task 1B).
- `LibraryLens: Codable`.
- `AppModel.isRestorableLens(_:) -> Bool` — `lens != .cull`. Quitting mid-cull relaunches on the same source in Grid.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Rewrite the round-trip literals**

In `Tests/TeststripAppTests/SessionRestoreStateTests.swift`, replace `selectedView: .grid,` in `testRoundTripPreservesAllFields` (`:8`) with:

```swift
            lens: .timeline,
            source: .smartCollection(.likelyIssues),
```

and change the `minimalState(selectedView:searchText:)` helper (`:120-140`) to `minimalState(lens:source:searchText:)`, replacing its `selectedView:` argument with `lens:` and `source:` and defaulting `source` to `.allPhotos`. Update its three call sites (`:45`, and the two in `testStoreNamespacesPerCatalogRoot` and the detached-predicates test added in Task 1A) to pass `lens:` instead of `selectedView:`.

Add:

```swift
    func testTheStoredVersionIsTwo() {
        XCTAssertEqual(SessionRestoreState.currentVersion, 2)
    }

    // No back-compat: a v1 blob is discarded rather than migrated, so the
    // app cold-starts on All Photos in Grid instead of restoring a shape that
    // no longer exists.
    func testAVersionOneBlobIsDiscarded() throws {
        let defaults = try makeIsolatedDefaults()
        let catalogRoot = URL(fileURLWithPath: "/tmp/catalog-v1", isDirectory: true)
        let key = SessionRestoreStore.key(forCatalogRoot: catalogRoot)
        let legacy = #"{"version":1,"selectedView":"grid","sortOption":"importOrder","librarySearchText":""}"#
        defaults.set(Data(legacy.utf8), forKey: key)

        XCTAssertNil(SessionRestoreStore(defaults: defaults, catalogRoot: catalogRoot).load())
    }
```

- [ ] **Step 2: Add the model-level restore tests**

In `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`, update the `SessionRestoreState(...)` literal at `:290-312` the same way, and change `try modelA.selectSidebarTarget(.search)` at `:13,223,268` to `try modelA.selectSource(.allPhotos)` if Task 5A has not already. Then append:

```swift
    // Relaunch restores the selected source and the browse lens it was seen
    // through.
    func testRestoresTheSourceAndTheBrowseLens() throws {
        let directory = try makeTemporaryDirectory(named: "restore-source-lens")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 4, in: catalogA.repository, ratingForIndex: { $0 < 2 ? 5 : 1 })

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.smartCollection(.fiveStars))
        modelA.selectLens(.timeline)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedLens, .timeline)
        XCTAssertEqual(modelB.selectedSource, LibrarySource.smartCollection(.fiveStars))
        XCTAssertEqual(modelB.assets.count, 2)
    }

    // Quitting mid-cull relaunches on the same source in Grid — actual run
    // resume is the SP-D lifecycle spec's job.
    func testAMidCullQuitRelaunchesOnTheSameSourceInGrid() throws {
        let directory = try makeTemporaryDirectory(named: "restore-mid-cull")
        let defaults = try makeIsolatedDefaults()
        let catalogA = try makeCatalog(directory: directory)
        try seedAssets(count: 3, in: catalogA.repository)

        let modelA = try AppModel.load(catalog: catalogA, sessionRestoreDefaults: defaults)
        try modelA.selectSource(.folder("/Photos"))
        modelA.selectLens(.cull)
        XCTAssertEqual(modelA.selectedLens, .cull)

        let catalogB = try makeCatalog(directory: directory)
        let modelB = try AppModel.load(catalog: catalogB, sessionRestoreDefaults: defaults)

        XCTAssertEqual(modelB.selectedLens, .grid)
        XCTAssertEqual(modelB.selectedSource, LibrarySource.folder("/Photos"))
    }

    func testAFreshCatalogColdStartsOnAllPhotosInGrid() throws {
        let directory = try makeTemporaryDirectory(named: "restore-cold-start")
        let defaults = try makeIsolatedDefaults()
        let catalog = try makeCatalog(directory: directory)
        try seedAssets(count: 2, in: catalog.repository)

        let model = try AppModel.load(catalog: catalog, sessionRestoreDefaults: defaults)

        XCTAssertEqual(model.selectedLens, .grid)
        XCTAssertEqual(model.selectedSource, LibrarySource.allPhotos)
    }
```

- [ ] **Step 3: Run and verify the red**

Run: `swift test --filter SessionRestoreStateTests 2>&1 | tail -30`
Expected: **compile failure**, `extra argument 'lens'`/`'source'` and `missing argument for parameter 'selectedView'`.

Run: `swift test --filter AppModelSessionRestoreTests 2>&1 | tail -30`
Expected: the same compile failure.

- [ ] **Step 4: Falsification red proof for the cold-start test**

`testAFreshCatalogColdStartsOnAllPhotosInGrid` would pass trivially once the types exist (a fresh catalog restores nothing). Prove it is sensitive: in `Sources/TeststripApp/AppModel.swift`, change the `selectedSource` declaration's default from `= .allPhotos` to `= .smartCollection(.picks)`. Run `swift test --filter AppModelSessionRestoreTests/testAFreshCatalogColdStartsOnAllPhotosInGrid`. Expected: the `selectedSource` assertion fails with `Picks`. Capture. Then `git checkout -- Sources/TeststripApp/AppModel.swift` and confirm `git diff --stat -- Sources/` is empty.

- [ ] **Step 5: Capture every red transcript into your task report**

- [ ] **Step 6: Commit**

```bash
git status
git add Tests/TeststripAppTests/SessionRestoreStateTests.swift Tests/TeststripAppTests/AppModelSessionRestoreTests.swift
git commit -m "test: pin session restore returning source plus lens (red)"
```

---

## Task 8B: Session restore returns source + lens — implementation

**Files:**
- Modify: `Sources/TeststripApp/SessionRestoreState.swift`
- Modify: `Sources/TeststripApp/LibraryLens.swift` (add `Codable`)
- Modify: `Sources/TeststripApp/AppModel.swift` (`currentSessionRestoreState()` `:11787`, `applyRestoredSessionState(_:catalog:)` `:11827`, `isRestorableSessionRoute(_:)` `:11878`)

**Interfaces:**
- Consumes: `LibraryLens`, `LibrarySource` (Task 5B), `detachedFilterPredicates` (Task 1B).
- Produces: `SessionRestoreState` v2, `AppModel.isRestorableLens(_:)`.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Make the lens `Codable`**

In `Sources/TeststripApp/LibraryLens.swift`, change the declaration:

```swift
public enum LibraryLens: String, CaseIterable, Codable, Sendable {
```

- [ ] **Step 2: Reshape `SessionRestoreState`**

In `Sources/TeststripApp/SessionRestoreState.swift`, replace the header comment and the first two stored properties:

```swift
// UI state persisted across relaunches: the selected source, the lens it was
// seen through, the saved-set scope, active search/filters, selection, and sort
// order. A mid-cull quit relaunches on the same source in Grid — actual run
// resume is the SP-D lifecycle spec's job, and in-progress culling sessions
// already survive as work sessions.
struct SessionRestoreState: Codable, Equatable, Sendable {
    // No back-compat: v1 persisted a `selectedView` route and no source at
    // all. `load()` discards a mismatched version, so a v1 blob simply
    // cold-starts the app.
    static let currentVersion = 2

    var version: Int = SessionRestoreState.currentVersion
    var lens: LibraryLens
    var source: LibrarySource
    var selectedAssetSetID: AssetSetID?
```

leaving every remaining property (through `detachedFilterPredicates`) untouched.

- [ ] **Step 3: Persist and restore the pair**

In `AppModel.currentSessionRestoreState()` (`:11787-11814`), replace the `selectedView:` argument with:

```swift
            lens: selectedLens,
            source: selectedSource,
```

In `AppModel.applyRestoredSessionState(_:catalog:)` (`:11827-11875`), replace the route line (`:11856`) with:

```swift
        selectedSource = state.source
        selectLens(Self.isRestorableLens(state.lens) ? state.lens : .grid)
```

Replace `isRestorableSessionRoute(_:)` (`:11878-11885`) with:

```swift
    /// Every lens survives a relaunch except Cull: a mid-cull quit relaunches
    /// on the same source in Grid, because the run itself is not resumed here.
    private static func isRestorableLens(_ lens: LibraryLens) -> Bool {
        lens != .cull
    }
```

- [ ] **Step 4: Run the new tests and verify they pass**

Run: `swift test --filter SessionRestoreStateTests && swift test --filter AppModelSessionRestoreTests`
Expected: 0 failures.

- [ ] **Step 5: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures.

- [ ] **Step 6: Commit**

```bash
git status
git add Sources/TeststripApp/SessionRestoreState.swift Sources/TeststripApp/LibraryLens.swift Sources/TeststripApp/AppModel.swift
git commit -m "feat: session restore returns the selected source and its lens"
```

---

## Task 9A: Completion toast and bell receipts — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/ImportCompletionToastPresentationTests.swift` (create)
- Test: `Tests/TeststripAppTests/ImportCompletionPresentationTests.swift` (**delete** — the whole file is about the banner)
- Test: `Tests/TeststripAppTests/ActivityCenterPresentationTests.swift` (add the receipt tests)
- Test: `Tests/TeststripAppTests/LibraryGridChromeTests.swift` (delete the `shouldShowImportCompletionSummary` cases)
- Test: `Tests/TeststripAppTests/AppModelTests.swift` (the 14 `latestImportCompletionSummary`-adjacent assertions — keep the ones that assert the summary itself, delete the ones that assert banner actions)

**Interfaces (what Task 9B must produce):**
- `public struct ImportCompletionToastPresentation: Equatable, Sendable` with `summaryID: String`, `sessionID: WorkSessionID`, `headline: String`, `warningText: String?`, `showsStartCulling: Bool`, `cullingSessionName: String`; `public static let visibleDuration: TimeInterval = 10`; and
  `public static func toast(for summary: ImportCompletionSummary?, isCurrentSessionActivity: Bool, isImporting: Bool) -> ImportCompletionToastPresentation?`
- `public struct ImportReceiptRow: Equatable, Identifiable, Sendable` with `id: String`, `sessionID: WorkSessionID`, `title: String`, `detail: String`, `issueCount: Int`, `canStartCulling: Bool`; `public static func rows(from activities: [AppWorkActivity], limit: Int) -> [ImportReceiptRow]`; `public static let retentionLimit = 5`.
- `ActivityCenterPresentation` gains `public var receipts: [ImportReceiptRow]` and a `receipts:` init parameter placed after `xmpConflicts:`. **The badge math is unchanged — receipts never badge.**
- `AppModel.importCompletionToast: ImportCompletionToastPresentation?`
- `AppModel.startCullingImport(sessionID:title:) throws -> WorkSession` (`@discardableResult`)
- **Deleted:** `ImportCompletionPresentation`, `ImportCompletionMetricRow`, `ImportCompletionActionPresentation`, `LibraryGridChromePolicy.shouldShowImportCompletionSummary`, `AppModel.reviewLatestImportFlagged()`.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Write the toast test file**

Create `Tests/TeststripAppTests/ImportCompletionToastPresentationTests.swift`:

```swift
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// One capsule, top-right, ~10s, then it docks into the bell as the receipt.
// It replaces roughly 280pt of banner chrome whose nine actions collapsed to
// four intents.
final class ImportCompletionToastPresentationTests: XCTestCase {
    private func summary(
        activityID: String = "import-1",
        imported: Int = 24,
        new: Int = 24,
        existing: Int = 0,
        issues: Int = 0
    ) -> ImportCompletionSummary {
        ImportCompletionSummary(
            activityID: activityID,
            title: "Import complete",
            detail: "Imported \(imported) photos from /Cards/A",
            importedPhotoCount: imported,
            photoCountText: "\(imported) \(imported == 1 ? "photo" : "photos")",
            newPhotoCount: new,
            existingPhotoCount: existing,
            previewFailureCount: 0,
            failureText: nil,
            previewStatusText: "Previews ready",
            issues: (0..<issues).map { index in
                WorkSessionIssue(kind: .skippedSourceFile, sourceURL: nil, message: "skipped \(index)")
            },
            stackCount: 0,
            stackedPhotoCount: 0,
            cullingSessionName: "/Cards/A Cull"
        )
    }

    func testAFullImportOffersStartCulling() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.headline, "Imported 24 photos")
        XCTAssertNil(toast.warningText)
        XCTAssertTrue(toast.showsStartCulling)
        XCTAssertEqual(toast.sessionID, WorkSessionID(rawValue: "import-1"))
        XCTAssertEqual(toast.cullingSessionName, "/Cards/A Cull")
    }

    func testASkippedFileCountSurfacesAsAWarning() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(issues: 2),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.warningText, "2 files skipped")
        XCTAssertTrue(toast.showsStartCulling)
    }

    func testOneSkippedFileIsSingular() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(issues: 1),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.warningText, "1 file skipped")
    }

    // Existing-only imports get the same shape with that copy and no Start
    // culling button — there is nothing new to cull.
    func testAnExistingOnlyImportGetsItsOwnCopyAndNoStartCulling() throws {
        let toast = try XCTUnwrap(
            ImportCompletionToastPresentation.toast(
                for: summary(imported: 24, new: 0, existing: 24),
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )

        XCTAssertEqual(toast.headline, "No new photos imported — 24 already in catalog")
        XCTAssertFalse(toast.showsStartCulling)
    }

    // The persona-7 zombie-panel lesson: a summary restored from persisted
    // work history must never resurrect the toast on relaunch.
    func testARestoredSummaryFromAPreviousSessionProducesNoToast() {
        XCTAssertNil(
            ImportCompletionToastPresentation.toast(
                for: summary(),
                isCurrentSessionActivity: false,
                isImporting: false
            )
        )
    }

    func testNoToastWhileAnImportIsStillRunning() {
        XCTAssertNil(
            ImportCompletionToastPresentation.toast(
                for: summary(),
                isCurrentSessionActivity: true,
                isImporting: true
            )
        )
    }

    func testNoSummaryMeansNoToast() {
        XCTAssertNil(
            ImportCompletionToastPresentation.toast(
                for: nil,
                isCurrentSessionActivity: true,
                isImporting: false
            )
        )
    }

    func testTheToastFadesAfterAboutTenSeconds() {
        XCTAssertEqual(ImportCompletionToastPresentation.visibleDuration, 10)
    }

    // The banner presentation types are gone at compile level. This test does
    // not reference them — their absence is proven by this file compiling
    // after ImportCompletionPresentationTests.swift is deleted.
}
```

- [ ] **Step 2: Delete the banner test file and prune its stragglers**

```bash
git rm Tests/TeststripAppTests/ImportCompletionPresentationTests.swift
```

In `Tests/TeststripAppTests/LibraryGridChromeTests.swift`, delete every test whose body calls `LibraryGridChromePolicy.shouldShowImportCompletionSummary`. In your report, name each deleted test and its replacement in `ImportCompletionToastPresentationTests` (`testARestoredSummaryFromAPreviousSessionProducesNoToast` and `testNoToastWhileAnImportIsStillRunning` carry the whole session-scope guard forward).

In `Tests/TeststripAppTests/AppModelTests.swift`, run

```bash
grep -n "latestImportCompletionSummary\|reviewLatestImportFlagged\|ImportCompletionPresentation" Tests/TeststripAppTests/AppModelTests.swift
```

Keep every assertion about `latestImportCompletionSummary`'s own fields (it survives as the toast/receipt data source). Delete any test whose subject is `reviewLatestImportFlagged()` — the "⚠ Likely issues" import child replaces it, covered by `ImportSourceScopingTests.testImportChildCountsAreScopedToTheImport` and scenario card `import-011`. List each deletion in your report.

- [ ] **Step 3: Add the receipt tests**

Append to `Tests/TeststripAppTests/ActivityCenterPresentationTests.swift`:

```swift
    // MARK: - Import receipts

    // The toast is the announcement; the bell is the archive. Completed
    // imports become a receipt family in the Activity Center — and they never
    // badge, because the badge counts problems only.
    func testCompletedImportsBecomeReceipts() {
        let receipts = ImportReceiptRow.rows(
            from: [
                AppWorkActivity(
                    id: "import-1",
                    kind: .ingest,
                    status: .completed,
                    title: "Import photos",
                    detail: "Imported 24 photos from /Cards/A",
                    completedUnitCount: 24,
                    totalUnitCount: 24,
                    failureCount: 0
                ),
                AppWorkActivity(
                    id: "cull-1",
                    kind: .culling,
                    status: .completed,
                    title: "Cull the shoot",
                    detail: "12 picks",
                    completedUnitCount: 12,
                    totalUnitCount: 24,
                    failureCount: 0
                ),
                AppWorkActivity(
                    id: "import-running",
                    kind: .ingest,
                    status: .running,
                    title: "Import photos",
                    detail: "Importing…",
                    completedUnitCount: 3,
                    totalUnitCount: 24,
                    failureCount: 0
                )
            ],
            limit: ImportReceiptRow.retentionLimit
        )

        XCTAssertEqual(receipts.map(\.id), ["import-1"])
        XCTAssertEqual(receipts.first?.title, "Imported 24 photos from /Cards/A")
        XCTAssertTrue(receipts.first?.canStartCulling ?? false)
    }

    func testReceiptsAreCappedByTheRetentionLimit() {
        let activities = (0..<12).map { index in
            AppWorkActivity(
                id: "import-\(index)",
                kind: .ingest,
                status: .completed,
                title: "Import photos",
                detail: "Imported 1 photo from /Cards/\(index)",
                completedUnitCount: 1,
                totalUnitCount: 1,
                failureCount: 0
            )
        }

        XCTAssertEqual(ImportReceiptRow.rows(from: activities, limit: 5).count, 5)
    }

    func testAReceiptCarriesItsIssueCountButNeverBadges() {
        let presentation = ActivityCenterPresentation(
            kindRows: [],
            importActivity: nil,
            importError: nil,
            sources: [],
            xmpConflicts: [],
            receipts: [
                ImportReceiptRow(
                    id: "import-1",
                    sessionID: WorkSessionID(rawValue: "import-1"),
                    title: "Imported 6 photos from /Cards/A",
                    detail: "2 files skipped",
                    issueCount: 2,
                    canStartCulling: true
                )
            ],
            providerFailureCount: 0
        )

        XCTAssertEqual(presentation.receipts.count, 1)
        XCTAssertEqual(presentation.badge, .none, "receipts never badge — the badge counts problems only")
        XCTAssertFalse(presentation.isWorking)
    }
```

**Before running, check the existing `ActivityCenterPresentation(...)` call sites in that file** and add `receipts: []` to every one — the initializer gains a parameter.

- [ ] **Step 4: Run and verify the red**

Run: `swift test --filter ImportCompletionToastPresentationTests 2>&1 | tail -30`
Expected: **compile failure**, `cannot find 'ImportCompletionToastPresentation' in scope`.

Run: `swift test --filter ActivityCenterPresentationTests 2>&1 | tail -30`
Expected: **compile failure**, `cannot find 'ImportReceiptRow' in scope` and `extra argument 'receipts' in call`.

Genuine reds.

- [ ] **Step 5: Falsification red proof for the badge invariant**

`testAReceiptCarriesItsIssueCountButNeverBadges` will pass the moment the types exist, because the badge math is untouched. Prove it is sensitive: in `Sources/TeststripApp/ActivityCenterPresentation.swift`, change the badge math (`:174-176`) from

```swift
        let problemCount = xmpConflicts.count + unavailableSourceCount + providerFailureCount
```

to

```swift
        let problemCount = xmpConflicts.count + unavailableSourceCount + providerFailureCount + receipts.count
```

Run `swift test --filter ActivityCenterPresentationTests/testAReceiptCarriesItsIssueCountButNeverBadges`. Expected: `XCTAssertEqual(presentation.badge, .none)` fails with `.problems(1)`. Capture. Then `git checkout -- Sources/TeststripApp/ActivityCenterPresentation.swift` and confirm `git diff --stat -- Sources/` is empty.

- [ ] **Step 6: Capture every red transcript and the deleted-test rationale into your task report**

- [ ] **Step 7: Commit**

```bash
git status
git add Tests/TeststripAppTests/
git commit -m "test: pin the completion toast and the bell receipts (red)"
```

---

## Task 9B: Completion toast and bell receipts — implementation

**Files:**
- Create: `Sources/TeststripApp/ImportCompletionToastPresentation.swift`
- Modify: `Sources/TeststripApp/ActivityCenterPresentation.swift`
- Modify: `Sources/TeststripApp/ActivityCenterView.swift`
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift`

**Interfaces:**
- Consumes: `ImportCompletionSummary` (`AppModel.swift:1426`), `isCurrentSessionActivity(id:)` (`:13869`), `isImportCompletionActivity(_:)` (`:13838`), `selectSource(_:)` / `selectLens(_:)` (Task 5B), `beginCullingSession(named:intent:)` (`:5768`), `beginStackCullingFromLatestImportCompletion()` (`:5110`), `reviewLatestImportInCompare()` (`:5166`), `requestCurrentScopeAssetEvaluations()`.
- Produces: everything in Task 9A's Interfaces block.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Create the toast and receipt presentation**

Create `Sources/TeststripApp/ImportCompletionToastPresentation.swift`:

```swift
import Foundation
import TeststripCore

/// The completion moment: one thin capsule, top-right, that fades after ~10s
/// (or on click/dismiss) and docks into the Activity Center bell as the
/// receipt. It replaces the post-import banner's headline, four metric tiles,
/// and nine action buttons — whose nine actions collapsed to four intents,
/// three of which were different doors into culling the same set.
public struct ImportCompletionToastPresentation: Equatable, Sendable {
    /// ~10s, then the bell keeps the full receipt.
    public static let visibleDuration: TimeInterval = 10

    public var summaryID: String
    public var sessionID: WorkSessionID
    public var headline: String
    public var warningText: String?
    public var showsStartCulling: Bool
    public var cullingSessionName: String

    public init(
        summaryID: String,
        sessionID: WorkSessionID,
        headline: String,
        warningText: String?,
        showsStartCulling: Bool,
        cullingSessionName: String
    ) {
        self.summaryID = summaryID
        self.sessionID = sessionID
        self.headline = headline
        self.warningText = warningText
        self.showsStartCulling = showsStartCulling
        self.cullingSessionName = cullingSessionName
    }

    /// The optional return *is* the gating decision, expressed as data.
    /// Session-scoped on purpose: a summary restored from persisted work
    /// history must never resurrect the toast on relaunch (persona-7's zombie
    /// panel, which `app-006` tests for).
    public static func toast(
        for summary: ImportCompletionSummary?,
        isCurrentSessionActivity: Bool,
        isImporting: Bool
    ) -> ImportCompletionToastPresentation? {
        guard let summary, isCurrentSessionActivity, !isImporting else { return nil }
        let skippedCount = summary.issues.filter { $0.kind == .skippedSourceFile }.count
        let isExistingOnly = summary.newPhotoCount == 0 && summary.existingPhotoCount > 0
        return ImportCompletionToastPresentation(
            summaryID: summary.id,
            sessionID: WorkSessionID(rawValue: summary.activityID),
            headline: isExistingOnly
                ? "No new photos imported — \(summary.existingPhotoCount) already in catalog"
                : "Imported \(summary.photoCountText)",
            warningText: skippedCount > 0
                ? "\(skippedCount) \(skippedCount == 1 ? "file" : "files") skipped"
                : nil,
            showsStartCulling: !isExistingOnly && summary.newPhotoCount > 0,
            cullingSessionName: summary.cullingSessionName
        )
    }
}

/// A completed import, archived in the Activity Center bell. The fifth item
/// family: the first four (work kinds, import progress, sources, XMP
/// conflicts) are all about work in flight or problems; this one is history.
public struct ImportReceiptRow: Equatable, Identifiable, Sendable {
    /// How many receipts the bell keeps. Older imports stay reachable through
    /// the sidebar's Imports section, which is unbounded.
    public static let retentionLimit = 5

    public var id: String
    public var sessionID: WorkSessionID
    public var title: String
    public var detail: String
    public var issueCount: Int
    public var canStartCulling: Bool

    public init(
        id: String,
        sessionID: WorkSessionID,
        title: String,
        detail: String,
        issueCount: Int,
        canStartCulling: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.title = title
        self.detail = detail
        self.issueCount = issueCount
        self.canStartCulling = canStartCulling
    }

    public static func rows(from activities: [AppWorkActivity], limit: Int) -> [ImportReceiptRow] {
        activities
            .filter { $0.kind == .ingest && $0.status == .completed }
            .prefix(limit)
            .map { activity in
                let skippedCount = activity.issues.filter { $0.kind == .skippedSourceFile }.count
                return ImportReceiptRow(
                    id: activity.id,
                    sessionID: WorkSessionID(rawValue: activity.id),
                    title: activity.detail.isEmpty ? "Import complete" : activity.detail,
                    detail: skippedCount > 0
                        ? "\(skippedCount) \(skippedCount == 1 ? "file" : "files") skipped"
                        : "",
                    issueCount: skippedCount,
                    canStartCulling: activity.completedUnitCount > 0
                )
            }
    }
}
```

- [ ] **Step 2: Add receipts to the Activity Center**

In `Sources/TeststripApp/ActivityCenterPresentation.swift`, add the stored property after `xmpConflicts` (`:158`):

```swift
    /// Completed imports, newest first. Receipts never badge — the badge
    /// counts problems only; the toast is the announcement and this is the
    /// archive.
    public var receipts: [ImportReceiptRow]
```

add the init parameter after `xmpConflicts:` (`:165`):

```swift
        receipts: [ImportReceiptRow],
```

and the assignment after `self.xmpConflicts = xmpConflicts` (`:172`):

```swift
        self.receipts = receipts
```

**Leave the badge math (`:174-176`) exactly as it is.**

In `Sources/TeststripApp/AppModel.swift`, in `activityCenterPresentation` (`:3029-3036`), add the argument:

```swift
            xmpConflicts: xmpConflicts,
            receipts: ImportReceiptRow.rows(from: recentWork, limit: ImportReceiptRow.retentionLimit),
            providerFailureCount: smartCollectionCounts[.providerFailures] ?? 0
```

In `Sources/TeststripApp/ActivityCenterView.swift`, add the section after the conflicts block (`:36-38`):

```swift
            if !presentation.receipts.isEmpty {
                receiptsSection(presentation.receipts)
            }
```

and add the renderer next to `conflictsSection(_:)` (`:240-257`):

```swift
    // MARK: - Import receipts

    private func receiptsSection(_ receipts: [ImportReceiptRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent Imports")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(receipts) { receipt in
                VStack(alignment: .leading, spacing: 3) {
                    Text(receipt.title)
                        .font(.caption)
                        .lineLimit(2)
                    if !receipt.detail.isEmpty {
                        Text(receipt.detail)
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .lineLimit(1)
                    }
                    if receipt.canStartCulling {
                        Button("Start culling") {
                            startCulling(receipt)
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                        .accessibilityLabel("Start culling")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func startCulling(_ receipt: ImportReceiptRow) {
        do {
            try model.startCullingImport(sessionID: receipt.sessionID, title: receipt.title)
            model.isActivityCenterPresented = false
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
```

- [ ] **Step 3: Add the model surface and generalize the stack cull**

In `Sources/TeststripApp/AppModel.swift`, add next to `latestImportCompletionSummary` (`:3383-3391`):

```swift
    /// The completion toast, or nil when there is nothing to announce.
    public var importCompletionToast: ImportCompletionToastPresentation? {
        guard let summary = latestImportCompletionSummary else { return nil }
        return ImportCompletionToastPresentation.toast(
            for: summary,
            isCurrentSessionActivity: isCurrentSessionActivity(id: summary.activityID),
            isImporting: isImporting
        )
    }
```

Replace `beginCullingFromLatestImportCompletion()` (`:5103-5107`) with:

```swift
    /// The single "cull this import" primitive, shared by the toast's Start
    /// culling button, the bell receipt, and the sidebar's import rows.
    @discardableResult
    public func startCullingImport(sessionID: WorkSessionID, title: String) throws -> WorkSession {
        try selectSource(.workSession(sessionID, titled: title))
        return try beginCullingSession(named: title)
    }

    @discardableResult
    public func beginCullingFromLatestImportCompletion() throws -> WorkSession {
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("no completed import")
        }
        return try startCullingImport(
            sessionID: WorkSessionID(rawValue: summary.activityID),
            title: summary.cullingSessionName
        )
    }
```

Generalize the stack cull so the import row's **Stacks** child can drive it for *any* import (F10 — its only affordance today is the banner's "Cull stacks", which is being deleted). Change `beginStackCullingFromLatestImportCompletion()` (`:5109-5164`) to take the import explicitly and keep a thin wrapper:

```swift
    @discardableResult
    public func beginStackCulling(importSessionID: WorkSessionID, title: String) throws -> WorkSession {
```

Inside the body, replace the two lines that read the latest summary

```swift
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("no completed import")
        }
```

with

```swift
        let activityID = importSessionID.rawValue
```

and replace every remaining `summary.activityID` with `activityID`, every `summary.cullingSessionName` with `title`, and `summary.stackCount > 0` (`:5118`) with `!stacks.isEmpty` — hoisting the `let stacks = try latestImportStacks(activityID: activityID, repository: catalog.repository)` line (`:5121`) above the `stackIntent` computation. Replace the `_ = try openLatestImportCompletion()` degradation (`:5123`) with `try selectSource(.workSession(importSessionID, titled: title))`.

Then add the wrapper:

```swift
    @discardableResult
    public func beginStackCullingFromLatestImportCompletion() throws -> WorkSession {
        guard let summary = latestImportCompletionSummary else {
            throw TeststripError.invalidState("no completed import")
        }
        return try beginStackCulling(
            importSessionID: WorkSessionID(rawValue: summary.activityID),
            title: summary.cullingSessionName
        )
    }
```

Delete `reviewLatestImportFlagged()` (`:5171-5181`) — the "⚠ Likely issues" import child replaces it.

Add the import row's context-menu verbs. In `SidebarRowContextActionKind` (`:1007-1014`) add:

```swift
    case cullImportStacks(WorkSessionID)
    case evaluateImport(WorkSessionID)
    case compareImport(WorkSessionID)
```

and the matching `id` arms in `SidebarRowContextAction.id` (`:1021-1036`):

```swift
        case .cullImportStacks(let id):
            return "cull-import-stacks-\(id.rawValue)"
        case .evaluateImport(let id):
            return "evaluate-import-\(id.rawValue)"
        case .compareImport(let id):
            return "compare-import-\(id.rawValue)"
```

In `sidebarContextActions(for:)` (`:5273-…`), append these three actions for a `.workSession` row whose id appears in `importSourceSummaries`:

```swift
        if case .workSession(let sessionID)? = row.target?.kind,
           importSourceSummaries.contains(where: { $0.sessionID == sessionID }) {
            actions.append(SidebarRowContextAction(
                kind: .cullImportStacks(sessionID),
                title: "Cull stacks",
                systemImage: "square.stack"
            ))
            actions.append(SidebarRowContextAction(
                kind: .evaluateImport(sessionID),
                title: "Evaluate import",
                systemImage: "sparkles"
            ))
            actions.append(SidebarRowContextAction(
                kind: .compareImport(sessionID),
                title: "Manual Compare over the import",
                systemImage: "rectangle.split.2x1"
            ))
        }
```

(Adapt `actions.append` to whatever accumulator that function already uses.) In `performSidebarContextAction(_:)`, add the three arms — each reuses an existing primitive rather than inventing one:

```swift
        case .cullImportStacks(let sessionID):
            let title = importSourceSummaries.first { $0.sessionID == sessionID }?.title ?? "Stack cull"
            _ = try beginStackCulling(importSessionID: sessionID, title: title)
        case .evaluateImport(let sessionID):
            let title = importSourceSummaries.first { $0.sessionID == sessionID }?.title ?? "Import"
            try selectSource(.workSession(sessionID, titled: title))
            try requestCurrentScopeAssetEvaluations()
        case .compareImport(let sessionID):
            let title = importSourceSummaries.first { $0.sessionID == sessionID }?.title ?? "Import"
            try selectSource(.workSession(sessionID, titled: title))
            selectedView = .compare
```

- [ ] **Step 4: Delete the banner and mount the toast**

In `Sources/TeststripApp/LibraryGridView.swift`, delete in full: `importCompletionSummary(_:)` (`:1420-1469`), `importCompletionMetric(_:)` (`:1471-1499`), `importCompletionAction(_:)` (`:1501-1520`), `importCompletionActionLabel(_:)` (`:1522-1546`), `performImportCompletionAction(_:)` (`:1548-1569`), `visibleImportCompletionSummary` (`:741-752`), the `@State private var dismissedImportCompletionSummaryID` (`:45`), `struct ImportCompletionPresentation` (`:8916-9246`), `struct ImportCompletionMetricRow` (`:9248-9275`), `struct ImportCompletionActionPresentation` (`:9277-9301`), `LibraryGridChromePolicy.shouldShowImportCompletionSummary` (`:8463-8476`), and the view-local wrappers `openLatestImportCompletion` (`:3138-3144`), `reviewLatestImportInCompare` (`:3164-3171`), `reviewLatestImportFlagged` (`:3173-3179`), `reviewLatestImportKeywordSuggestions` (`:3186-3196`), `requestLatestImportEvaluations` (`:3198-3205`), `reviewFaceQueueFromImportCompletion` (`:3207-3213`).

Keep `beginCullingFromLatestImportCompletion` (`:3146-3153`), `beginStackCullingFromLatestImportCompletion` (`:3155-3162`), `reviewImportIssuesFromCompletion` (`:3181-3184`) — but change the last one to read the toast instead of the deleted `visibleImportCompletionSummary`:

```swift
    private func reviewImportIssuesFromCompletion() {
        guard let summary = model.latestImportCompletionSummary, !summary.issues.isEmpty else { return }
        importIssueReview = ImportIssueReview(summaryID: summary.id, issues: summary.issues)
    }
```

Delete the banner mount from `topInsetContent` — the `if let summary = visibleImportCompletionSummary { importCompletionSummary(summary) }` block Task 7B carried forward.

Add the toast state and view. New `@State` next to the others (`:44`):

```swift
    @State private var dismissedToastSummaryID: String?
    @State private var isToastVisible = false
```

New view, next to `scopeLineBar`:

```swift
    @ViewBuilder
    private func importCompletionToast(_ toast: ImportCompletionToastPresentation) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text(toast.headline)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if let warningText = toast.warningText {
                    Text(warningText)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .lineLimit(1)
                }
            }
            if toast.showsStartCulling {
                Button("Start culling") {
                    startCullingFromToast(toast)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.orange)
                .accessibilityLabel("Start culling")
            }
            Button {
                dismissToast(toast)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss import toast")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.10)))
        .padding(.top, 10)
        .padding(.trailing, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Import complete")
    }

    private func startCullingFromToast(_ toast: ImportCompletionToastPresentation) {
        do {
            try model.startCullingImport(sessionID: toast.sessionID, title: toast.cullingSessionName)
            dismissToast(toast)
            focusCullingSurface()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func dismissToast(_ toast: ImportCompletionToastPresentation) {
        dismissedToastSummaryID = toast.summaryID
        isToastVisible = false
    }

    /// ~10s, then it fades and the bell keeps the receipt. Mirrors the cull
    /// loupe's `showDecisionToastThenFade`, which is the only other
    /// auto-dismissing surface in the app.
    private func showToastThenFade(_ toast: ImportCompletionToastPresentation) async {
        isToastVisible = true
        try? await Task.sleep(for: .seconds(ImportCompletionToastPresentation.visibleDuration))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.3)) {
            isToastVisible = false
        }
    }
```

Mount it as a top-trailing overlay on `body`, next to the existing overlays (after the `KeyMapOverlayView` overlay at `:221-229`):

```swift
        .overlay(alignment: .topTrailing) {
            if let toast = model.importCompletionToast,
               toast.summaryID != dismissedToastSummaryID,
               isToastVisible {
                importCompletionToast(toast)
                    .transition(.opacity)
            }
        }
        .task(id: model.importCompletionToast?.summaryID) {
            guard let toast = model.importCompletionToast, toast.summaryID != dismissedToastSummaryID else {
                isToastVisible = false
                return
            }
            await showToastThenFade(toast)
        }
```

- [ ] **Step 5: Verify the deletions and run the tests**

```bash
grep -rn "ImportCompletionPresentation\|ImportCompletionMetricRow\|ImportCompletionActionPresentation\|shouldShowImportCompletionSummary\|dismissedImportCompletionSummaryID\|reviewLatestImportFlagged" --include="*.swift" Sources/
```
Expected: no hits.

Run: `swift test --filter ImportCompletionToastPresentationTests && swift test --filter ActivityCenterPresentationTests`
Expected: 0 failures.

- [ ] **Step 6: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures.

- [ ] **Step 7: Commit**

```bash
git status
git add Sources/TeststripApp/
git commit -m "feat: a completion toast replaces the import banner, and the bell keeps the receipt"
```

---

## Task 10A: Timeline's histogram follows the source — tests (test author)

**Files:**
- Test: `Tests/TeststripAppTests/TimelinePresentationTests.swift` (append)

**Interfaces (what Task 10B must produce):**
- `AppModel.timelinePresentation: TimelinePresentation` — assembled from the **loaded source** (`assets` + `totalAssetCount`), not from the catalog-wide `catalogTimelineDays` cache.

**You are the test author. Do not write any file under `Sources/`.**

- [ ] **Step 1: Append the scoping test**

```swift
    // Spec behaviour change 7: the year histogram was catalog-wide while the
    // thumbnails below it were filtered, papered over by "Showing N loaded of
    // M photos". Under the unified shell every lens is source-scoped, so the
    // ribbon counts only the source's photos. The self-deriving initializer
    // that makes this free has existed all along, exercised only by this file.
    func testTheHistogramCountsOnlyTheSelectedSourcesPhotos() throws {
        let inScope = makeAsset(id: "timeline-in", path: "/Photos/Inside/a.jpg", capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let outOfScope = makeAsset(id: "timeline-out", path: "/Photos/Outside/b.jpg", capturedAt: Date(timeIntervalSince1970: 1_600_000_000))
        let (model, _) = try makeModelWithCatalogAssets(named: "timeline-scoped", assets: [inScope, outOfScope])

        try model.selectSource(.folder("/Photos/Inside"))
        model.selectLens(.timeline)

        let presentation = model.timelinePresentation
        XCTAssertEqual(presentation.yearRibbon.years.map(\.assetCount).reduce(0, +), 1)
        XCTAssertFalse(
            presentation.summaryText.contains("loaded of"),
            "the loaded-vs-total apology only existed because the halves disagreed"
        )
    }

    func testTheHistogramCoversTheWholeCatalogOnAllPhotos() throws {
        let first = makeAsset(id: "timeline-all-a", path: "/Photos/Inside/a.jpg", capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let second = makeAsset(id: "timeline-all-b", path: "/Photos/Outside/b.jpg", capturedAt: Date(timeIntervalSince1970: 1_600_000_000))
        let (model, _) = try makeModelWithCatalogAssets(named: "timeline-all", assets: [first, second])

        try model.selectSource(.allPhotos)

        XCTAssertEqual(model.timelinePresentation.yearRibbon.years.map(\.assetCount).reduce(0, +), 2)
    }
```

Add the two fixtures this file needs if they are not already present (`makeAsset(id:path:capturedAt:)` building an `Asset` with `AssetTechnicalMetadata(pixelWidth:pixelHeight:capturedAt:provenance:)`, and the `makeModelWithCatalogAssets(named:assets:)` helper copied from `Tests/TeststripAppTests/LibrarySourceTests.swift`).

**Before running, confirm the ribbon's shape:**

```bash
grep -n "struct TimelineYearRibbonPresentation" -A 12 Sources/TeststripApp/TimelinePresentation.swift
```

If the year rows expose a differently named count property, adapt only the two `assetCount` key paths and say so in your report.

- [ ] **Step 2: Run and verify the red**

Run: `swift test --filter TimelinePresentationTests 2>&1 | tail -30`
Expected: **compile failure**, `value of type 'AppModel' has no member 'timelinePresentation'`. Genuine red.

- [ ] **Step 3: Capture the red transcript into your task report**

- [ ] **Step 4: Commit**

```bash
git status
git add Tests/TeststripAppTests/TimelinePresentationTests.swift
git commit -m "test: pin the Timeline histogram to the selected source (red)"
```

---

## Task 10B: Timeline's histogram follows the source — implementation

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`TimelineWorkspaceView.presentation` `:7839-7845`)

**Interfaces:**
- Consumes: `TimelinePresentation.init(assets:totalAssetCount:calendar:)` (`TimelinePresentation.swift:10-17`).
- Produces: `AppModel.timelinePresentation`.

**You are the implementer. You are FORBIDDEN from modifying any file under `Tests/`.**

- [ ] **Step 1: Assemble the presentation on the model**

Add to `Sources/TeststripApp/AppModel.swift`, next to `scopeLine` (Task 7B):

```swift
    /// The Timeline lens over the selected source. Built from the loaded
    /// source rather than the catalog-wide `catalogTimelineDays` cache, whose
    /// `timelineDays()` query takes no scope: the year ribbon and scrubber
    /// used to show catalog-wide numbers over filtered thumbnails, papered
    /// over by "Showing N loaded of M photos".
    public var timelinePresentation: TimelinePresentation {
        TimelinePresentation(assets: assets, totalAssetCount: totalAssetCount)
    }
```

- [ ] **Step 2: Point the view at it**

In `Sources/TeststripApp/LibraryGridView.swift`, replace `TimelineWorkspaceView.presentation` (`:7839-7845`) with:

```swift
    private var presentation: TimelinePresentation {
        model.timelinePresentation
    }
```

- [ ] **Step 3: Run the tests and verify they pass**

Run: `swift test --filter TimelinePresentationTests`
Expected: 0 failures.

- [ ] **Step 4: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -30`
Expected: build succeeds; 0 failures. `model.catalogTimelineDays` keeps its other readers (it is still refreshed by `refreshCatalogFolders()`); nothing else regresses.

- [ ] **Step 5: Commit**

```bash
git status
git add Sources/TeststripApp/AppModel.swift Sources/TeststripApp/LibraryGridView.swift
git commit -m "fix: the Timeline histogram counts the selected source, not the whole catalog"
```

---

## Task 11: Rewrite the live-mockup ledger (design surface 4b and the workspace prose)

**Files:**
- Modify: `Sources/TeststripApp/LiveMockupPlaceholder.swift`
- Modify: `Tests/TeststripAppTests/PlaceholderTests.swift`

**Interfaces:** none (a ledger of prose plus the unit test that pins it).

This task edits a source file **and** the test that pins its strings, so it cannot use the NA/NB split: `PlaceholderTests.testImportCompleteLedgerTracksLiveActionsAndFaceReviewHandoff` (`:98-107`) asserts the exact 4b copy, and a source-only change turns it red. Both move in one commit.

- [ ] **Step 1: Rewrite the `.importCompleteSummary` placeholder**

In `Sources/TeststripApp/LiveMockupPlaceholder.swift`, replace `importCompleteSummary` (`:137-142`) with:

```swift
    public static let importCompleteSummary = LiveMockupPlaceholder(
        id: "import.complete-summary",
        title: "Import complete moment",
        intendedBehavior: "Announce a finished import without stealing the canvas, and keep the receipt somewhere durable.",
        currentFallback: "Thin top-right toast carrying the imported count, a skipped-file warning when the import had issues, and a Start culling button; it fades after about ten seconds and docks into the Activity Center bell, which keeps the receipt with the same counts, issue text, and Start culling. Existing-only imports get the same capsule with 'No new photos imported' copy and no Start culling. The follow-up work the old panel listed lives in the sidebar's Imports section — stacks, skipped files, preview failures, likely issues, faces found — and in the import row's context menu; automatic identity naming remains disabled and annotated."
    )
```

**The `.importCompleteSummary` marker stays registered** in `LiveMockupPlaceholders.all` (`:201`) and keeps its id, so nothing else in the registry moves — the surface it marks moved, it did not disappear. Its one render site changes in Step 3.

- [ ] **Step 2: Rewrite design surface 4b and the four stale workspace citations**

In `LiveMockupDesignSurfaces.all`, replace the `4b` entry's `currentImplementation` (`:293`) with:

```swift
            currentImplementation: "Import completion is a thin top-right toast (imported count, skipped-file warning, Start culling) that fades after about ten seconds and docks into the Activity Center bell as a durable receipt; the expanded nine-action panel is deleted. Follow-up work lives in the sidebar's Imports section (stacks, skipped files, preview failures, likely issues, faces found) and the import row's context menu (Cull stacks, Evaluate import, Manual Compare over the import); automatic naming remains disabled."
```

The other four entries cite the deleted workspace shell and must be corrected in the same pass — they are pre-existing prose, not this push's regression, but leaving them would make the ledger lie:

- `1a` Studio (`:237`): `"Library workspace (⌘2)"` → `"The Grid lens (⌘2)"`.
- `1b` Copilot (`:244`): `"the focused-workspaces chrome (Task 22, ⌘1/⌘2/⌘3)"` → `"the unified sources × lenses shell (⌘1–⌘6)"`, and `"the Cull sidebar's source picker"` → `"the sidebar's Smart Collections section"`. Apply the same two substitutions to the `copilotLibrary` placeholder's `currentFallback` (`:50`).
- `1c` Timeline (`:251`): `"Timeline sub-view (Library workspace, ⌘2)"` → `"The Timeline lens (⌘4)"`.
- `2a` Rapid cull (`:258`): `"Cull workspace (⌘1)"` → `"The Cull lens (⌘1)"`.
- `5a` People (`:300`): `"People workspace (⌘3)"` → `"The People lens (⌘6)"`.

- [ ] **Step 3: Move the placeholder marker to the toast**

In `Sources/TeststripApp/LibraryGridView.swift`, the `.liveMockupPlaceholder(.importCompleteSummary)` modifier was deleted with the banner in Task 9B. Re-attach it to the toast capsule, on `importCompletionToast(_:)`'s outermost modifier chain, immediately before `.accessibilityElement(children: .contain)`:

```swift
        .liveMockupPlaceholder(.importCompleteSummary)
```

- [ ] **Step 4: Update the pinned test**

In `Tests/TeststripAppTests/PlaceholderTests.swift`, replace `testImportCompleteLedgerTracksLiveActionsAndFaceReviewHandoff` (`:98-107`) with:

```swift
    func testImportCompleteLedgerTracksTheToastAndTheBellReceipt() throws {
        let placeholder = try XCTUnwrap(LiveMockupPlaceholders.all.first { $0.id == "import.complete-summary" })
        let surface = try XCTUnwrap(LiveMockupDesignSurfaces.all.first { $0.designID == "4b" })

        for text in [placeholder.currentFallback, surface.currentImplementation] {
            XCTAssertTrue(text.localizedCaseInsensitiveContains("toast"))
            XCTAssertTrue(text.localizedCaseInsensitiveContains("Start culling"))
            XCTAssertTrue(text.localizedCaseInsensitiveContains("Activity Center bell"))
            XCTAssertTrue(text.localizedCaseInsensitiveContains("Imports section"))
        }
        XCTAssertFalse(placeholder.currentFallback.localizedCaseInsensitiveContains("Expanded post-import panel"))
        XCTAssertFalse(surface.currentImplementation.localizedCaseInsensitiveContains("Expanded import-complete panel"))
    }

    // The ledger must not describe a shell that no longer exists.
    func testNoLedgerEntryDescribesTheDeletedWorkspaceShell() {
        let texts = LiveMockupPlaceholders.all.map(\.currentFallback)
            + LiveMockupDesignSurfaces.all.map(\.currentImplementation)

        for text in texts {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("workspace (⌘"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("⌘1/⌘2/⌘3"), text)
        }
    }
```

Also update the two stale comments in that file (`:171-174` and `:293-300`) so they say "the sidebar's Smart Collections section" and "the People lens (⌘6)" instead of "the workspace switcher (⌘3)".

- [ ] **Step 5: Run the tests and verify they pass**

Run: `swift test --filter LiveMockupPlaceholderTests`
Expected: 0 failures, including `testDesignSurfaceRegistryCoversDesignerMockupIds` (the id list is unchanged) and `testCopilotLedgerTracksAbsorbedRouteWithoutAutonomousActions` — check that one's substring expectations still hold after the `1b` edit and, if `"Cull sidebar's source picker"` is asserted there, update that assertion to `"Smart Collections section"` in the same commit.

- [ ] **Step 6: Verify the whole package builds and the full suite is green**

Run: `swift build && swift test 2>&1 | tail -20`
Expected: build succeeds; 0 failures.

- [ ] **Step 7: Commit**

```bash
git status
git add Sources/TeststripApp/LiveMockupPlaceholder.swift Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/PlaceholderTests.swift
git commit -m "docs: the live-mockup ledger describes the toast and the lens shell"
```

---

## Task 12: New scenario cards for the shell and the completion moment

**Files:**
- Create: `test/scenarios/app-019-lens-shell.md`
- Create: `test/scenarios/import-011-completion-toast-and-import-rows.md`
- Modify: `test/scenarios/LEDGER.md`

**Interfaces:** none (documentation).

Documentation-only, so no test/impl split. **Next free numbers verified at HEAD: `app-019` (highest is `app-018-default-card-destination.md`) and `import-011` (highest is `import-010-import-robustness.md`).** Follow the house card shape: `# <id>: <one-line contract>`, `**What this covers**`, `## Pre-state`, `## Steps`, `## Expected`, `## Cleanup`, `## Run status` (see `test/scenarios/lib-013-library-loupe.md` for the minimal example and `test/scenarios/cull-015-sidebar-sources.md` for a source-cited one).

- [ ] **Step 1: Write `app-019-lens-shell.md`**

Create `test/scenarios/app-019-lens-shell.md` covering, with source citations to the symbols this plan created:

1. **Pre-state:** `./script/build_and_run.sh --smoke`.
2. `script/ax_drive.sh wait-vended Teststrip`. Assert the toolbar's principal slot holds a control with AX label `"Lens"` containing six buttons labelled `Cull`, `Grid`, `Loupe`, `Timeline`, `Map`, `People` (`LibraryGridView.lensSwitcher`, `LibraryLens.allCases`).
3. Assert **absence** of the deleted controls: `ax_drive.sh find --role AXRadioButton --label "Workspace"` must fail, and no control labelled `"Library View"` exists.
4. Press ⌘1 through ⌘6 in turn. After each, assert `.navigationSubtitle` (`LibraryGridChromePolicy.windowSubtitle(for:)`) names the expected route and the scope line's source title is **unchanged**.
5. Select a source (a smart collection row in the sidebar), then cycle ⌘1–⌘6 again and assert the scope line still names that source after every switch — the ⌘1–⌘6 orthogonality contract.
6. Assert the sidebar is byte-identical across all six lenses (`ax_drive.sh find` the section headers `Library`, `Smart Collections`).
7. Select the `Analysis Failures` smart collection while in the Cull lens; assert the app falls back to Grid and the Cull segment renders disabled with AXHelp `"Nothing here is cullable"`.
8. Run a token search (`rating:5`), press **Cull these** in the result header, and assert the scope line names the search and the catalog gained a `culling` work session:
   ```bash
   sqlite3 "$DB" "SELECT kind, title FROM work_sessions WHERE kind='culling' ORDER BY created_at DESC LIMIT 1;"
   ```
9. Quit and relaunch; assert the source and lens come back (`SessionRestoreState` v2), and that a mid-cull quit relaunches in Grid on the same source.
10. **Every lens is source-scoped — assert it, don't assume it.** With a saved static Set selected, press ⌘5 (Map) and assert the coverage badge counts the **set**, not the catalog (spec behaviour change 11):
    ```bash
    sqlite3 "$DB" "SELECT COUNT(*) FROM json_each((SELECT json_extract(membership_json,'\$.manual._0') FROM asset_sets WHERE name='<set name>'));"
    ```
    Then press ⌘4 (Timeline) and assert the year ribbon's total matches the same number (behaviour change 7), and ⌘6 (People) and assert the people list holds only people present in the set (behaviour change 6).
11. Reopen a culling session from the sidebar's Recent Work section while in the Grid lens; assert the lens is **still Grid** (spec behaviour change 10 — it used to force the loupe).
12. **Sharp edge to record:** ⌥⌘1/⌥⌘2/⌥⌘3 remain the inspector-section scrolls and sit directly beneath ⌘1–⌘3; `inspect-001-toggle-tabs.md` is the card that pins them.

- [ ] **Step 2: Write `import-011-completion-toast-and-import-rows.md`**

Create `test/scenarios/import-011-completion-toast-and-import-rows.md` covering:

1. **Pre-state:** `./script/build_and_run.sh --isolated`, then import a seeded batch through the typed-path sheet.
2. On completion, assert the toast appears with AX label `"Import complete"`, a `Start culling` button, and (with a skipped-file fixture) a `"N files skipped"` line.
3. Assert **no banner chrome exists**: `ax_drive.sh find --contains "Review imported frames"` and `--contains "Cull stacks"` must both fail on the canvas.
4. Let ~10s elapse; assert the toast is gone and the bell's popover holds a `Recent Imports` receipt with the same counts and its own `Start culling`.
5. Relaunch; assert the toast does **not** reappear (the `isCurrentSessionActivity` guard, persona-7's zombie panel) while the receipt and the sidebar's Imports row survive.
6. Expand the newest import row; assert its children and their counts against the catalog:
   ```bash
   sqlite3 "$DB" "SELECT COUNT(*) FROM json_each((SELECT issues_json FROM work_sessions WHERE kind='ingest' ORDER BY created_at DESC LIMIT 1));"
   ```
   and the likely-issues/faces-found counts through the `.importBatch` predicate's membership join.
7. Assert a zero-count child is **absent**, not disabled.
8. Click `⚠ Skipped files`; assert it opens the issue-review sheet (`ImportIssueReview`) rather than an empty grid — skipped files are not in the catalog.
9. Right-click the import row; assert the context menu offers `Cull stacks`, `Evaluate import`, `Manual Compare over the import`. Press `Cull stacks` and assert per-stack `work-stack-` sets exist:
   ```bash
   sqlite3 "$DB" "SELECT COUNT(*) FROM asset_sets WHERE id LIKE 'work-stack-%';"
   ```
10. Import a second batch of the same files; assert the toast reads `No new photos imported — N already in catalog` and carries **no** Start culling button.
11. Cull an **older** import from its sidebar row and assert the run's input set matches that import, not the newest.

- [ ] **Step 3: Register both cards in the LEDGER**

Append two rows to `test/scenarios/LEDGER.md` in the existing column order (`ID | Card | Status | Test method | Defect type | Actual result | Notes / open questions`), both with status `Spec'd`, test method `VM e2e (ax+sql)`, and a note that they were authored for the unified-shell push and are pending a live VM run.

- [ ] **Step 4: Commit**

```bash
git status
git add test/scenarios/app-019-lens-shell.md test/scenarios/import-011-completion-toast-and-import-rows.md test/scenarios/LEDGER.md
git commit -m "test: scenario cards for the lens shell and the completion toast"
```

---

## Task 13: Reconcile the stale scenario cards (F18)

**Files:** the cards listed below, plus `test/scenarios/README.md` and `test/scenarios/LEDGER.md`.

**Interfaces:** none (documentation).

Documentation-only sweep, so no test/impl split. Work card by card and commit in small batches. **Every card you touch gets a dated reconciliation note appended to its `## Run status`, in the house style** — see `test/scenarios/cull-017-autopilot-review.md`'s status block for the pattern: state what was reconciled, then `supersedes prior status: <why the old evidence is no longer valid> — needs a fresh VM run.`

**Two cards are stale TODAY, independent of this push. Fixing them is in scope; flag them in your report as pre-existing failures this push inherited, not regressions it caused:**
- `app-003-workspace-switching.md` — titled "⌘1/⌘2/⌘3 … land on the right workspace" and asserting a **three**-workspace model, but `Workspace` has had two cases since People became a Library sub-view.
- `app-005-chrome-policy.md:59-60` — asserts "⌘I does not open an inspector column inside Cull — it switches to Library first", contradicted by `showsInspector` returning `true` unconditionally (`LibraryGridView.swift:8390-8392`) and `toggleInspector()` being a bare toggle (`AppModel.swift:4961-4963`).

- [ ] **Step 1: Retire and replace the two shell cards**

`test/scenarios/app-003-workspace-switching.md` — **replace wholesale.** Its contract (a workspace switcher and ⌘1/⌘2/⌘3) no longer exists. Rewrite the file as a stub whose body is a single pointer: "Superseded by `app-019-lens-shell.md` (unified shell, 2026-08-07). The two-workspace model and its ⌘1/⌘2 bindings were deleted; ⌘1–⌘6 now select lenses over a source." Keep the file so its LEDGER row and inbound cross-references stay resolvable.

`test/scenarios/lib-011-view-toggle-routing.md` — **rewrite in place** as the lens-binding contract: the five-tag `librarySubViewToggle` is gone; the authoritative control is `lensSwitcher` with six segments; `LibraryViewMode`'s remaining four cases (`.loupe`, `.compare`, `.abCompare`, `.cullGrid`) are Cull-lens sub-modes reached by g/c/b, not switcher tags.

- [ ] **Step 2: Reconcile the rest of the must-rewrite tier**

| Card | Change |
|---|---|
| `app-004-subview-menus.md` | The View menu now lists six lenses (⌘1–⌘6) then a divider then four cull sub-modes. Correct its stale "People excluded" header, and drop `LibraryViewMode.subViewMenuKey` — the successor is `cullSubModeMenuTitle`, and the bare g/c/b keys remain monitor-owned with **no** menu key equivalent. |
| `app-016-menu-coverage-invariants.md` | Re-anchor on `AppMenuCoveragePresentation.lensActionIDs` and `cullSubModeMenuModes`, and on the two rewritten tests in `MenuCoveragePresentationTests.swift`. State the F14 rule explicitly: a lens enum change must land in `AppMenuCoveragePresentation` in the same commit. |
| `app-002-window-floors.md` | One floor: `AppWindowLayoutMetrics.minimumWidth == 1000`. Delete the Library-vs-Cull comparison and the People-rides-the-Library-floor note. |
| `app-005-chrome-policy.md` | `WorkspaceChromePolicy` → `LensChromePolicy`; `showsLibraryViewToggle` is deleted; ⌘1/⌘2/⌘3 become ⌘1–⌘6. **Delete the stale `:59-60` inspector claim** and replace it with the true contract: ⌘I toggles the inspector in place, in every lens. |
| `cull-001-workspace-key-gating.md` | `CullingKeyCaptureGate.isActive(lens:selectedView:)`; the predicate is `lens == .cull && selectedView != .cullGrid`. Retitle to "…scoped to the Cull lens". |
| `import-009-cull-pick-journey.md` | Its `:32-33` AX elements "Start culling"/"Review imported frames" and its `:37` press come from the deleted banner. Replace with the toast's `Start culling`; delete the "Review imported frames" leg (that action is gone — Manual Compare moved to the import row's context menu). |
| `cull-004-stack-promote-return.md` | Its `:60-65` premise ("wired to exactly one UI affordance: the 'Cull stacks' button in the post-import completion banner") is dead. Rewrite it to the import row's context-menu `Cull stacks` action, backed by `AppModel.beginStackCulling(importSessionID:title:)`. |
| `app-006-session-restore.md` | `shouldShowImportCompletionSummary` (`:22`) no longer exists — replace with `ImportCompletionToastPresentation.toast(for:isCurrentSessionActivity:isImporting:)`. Keep the `:80` post-relaunch absence check but re-target it at the toast. Re-specify what persists: `SessionRestoreState` v2 restores **source + lens**, a v1 blob is discarded, and a mid-cull quit relaunches in Grid on the same source. |
| `cull-015-sidebar-sources.md` | The "Cull From" concept is gone. Rewrite as the **Smart Collections** section contract: zero-count rows omitted (not disabled), `AI Suggestions` present only while `autopilotGhostAssetIDs` is non-empty, `Analysis Failures` present as the tenth row, saved dynamic sets joining the section. The "Nothing to cull" empty state is replaced by the section simply not rendering. |
| `activity-002-popover-import.md` | With the banner gone this is the *sole durable receipt* — strengthen it. Add the `Recent Imports` receipt section, its `Start culling` action, the retention limit of 5, and the invariant that receipts never change the badge. |
| `lib-013-library-loupe.md` | `.libraryLoupe` is now the **Loupe lens** (⌘3) and it **is** session-restorable. Replace "the Library workspace's loupe" with "the Loupe lens" and the ⌘2 preamble with ⌘3. |
| `inspect-001-toggle-tabs.md` | Add a reconciliation note: ⌥⌘1/⌥⌘2/⌥⌘3 are unchanged and now sit directly beneath the new ⌘1–⌘3 lens keys. Its own 2026-07-13 preamble is the precedent for how a rebind is reconciled. |

- [ ] **Step 3: Commit that batch**

```bash
git status
git add test/scenarios/
git commit -m "test: reconcile the shell and completion cards to sources × lenses"
```

- [ ] **Step 4: Mechanical ⌘1/⌘2 preamble fixes**

For each card below, replace the workspace preamble with the lens equivalent (`⌘1` = Cull lens, unchanged in effect; `⌘2` = Grid lens, replacing "⌘2 for Library"; a stale `⌘3` becomes whichever lens the step actually wanted):

`app-008-batch-metadata.md:26`, `app-011-find-best-shots.md:22`, `cull-002-loupe-navigation.md:90`, `cull-003-rating-label-flag-keys.md:44`, `cull-005-scope-cycle.md:35`, `cull-006-zoom-and-face-zoom.md:47`, `cull-007-exif-overlay-cycle.md:52`, `cull-008-subview-keys-gcb.md:70`, `cull-009-keymap-overlay.md:73,77`, `cull-010-cullgrid-keys.md:54`, `cull-011-hud.md:80`, `cull-012-closeups-panel.md:97,113,118,209-211,234,329,333` (**load-bearing here** — the ⌘1/⌘2 round trip is the test; rewrite it as a ⌘1/⌘2 *lens* round trip and re-verify the assertion still means what the card claims), `cull-016-completion-stage.md:28`, `cull-017-autopilot-review.md:135`, `cull-018-compare-survey.md:74`, `cull-019-ab-compare.md:47`, `cull-022-flow-grammar-walk.md:152,224`, `cull-023-return-commit-undo.md:197`, `inspect-004-retry-surfaces.md:42`, `activity-005-conflict-deep-link.md:19` (stale ⌘3).

Also: `import-002-card-copy.md:93` has an either/or assertion whose first branch is the banner — trim to the surviving branch.

**False positives — check before touching:** `app-010-move-rejects.md:10,89` and `app-017-move-rejects-to-trash.md:57,96` say "completion banner" but mean the **reject-relocation** banner (`RejectRelocationBannerView`, `LibraryGridView.swift:167`), which this push does not touch. Leave them.

- [ ] **Step 5: Sweep for survivors**

```bash
grep -rn "⌘3\|Workspace\b\|workspace switcher\|Cull From\|Library View\|import completion banner\|shouldShowImportCompletionSummary\|ImportCompletionPresentation\|selectSidebarTarget\|SidebarRowTarget" test/scenarios/
```

Expected: hits only inside a card's `## Run status` history, where the note deliberately quotes what was removed, and the two reject-relocation false positives. Inspect each survivor and confirm it is a history line, not a live assertion.

- [ ] **Step 6: Update the LEDGER and README**

Set every card touched in Steps 1–5 to `Reconciled — NOT re-run` in `test/scenarios/LEDGER.md`, with a `supersedes prior status: …` note. Update `test/scenarios/README.md` wherever it describes the two-workspace shell or the import banner.

- [ ] **Step 7: Commit**

```bash
git status
git add test/scenarios/
git commit -m "test: reconcile the remaining scenario cards to the unified shell"
```

---

## Task 14: Citation sweep (final commit before whole-branch review)

**Files:** every doc and card that cites a `file:line` anchor this push moved.

**Interfaces:** none (documentation).

This is the last commit on the branch. Its job is that no doc or card sends a reader to a line that no longer says what the citation claims.

- [ ] **Step 1: Collect every citation of a file this push touched**

```bash
grep -rnoE '(Sources|Tests)/[A-Za-z/]+\.swift:[0-9]+(-[0-9]+)?' \
  test/scenarios/ docs/architecture/ docs/dogfooding.md docs/product/ \
  | sort -u > /tmp/citations.txt
wc -l /tmp/citations.txt
```

- [ ] **Step 2: Verify each citation against HEAD and fix the drifted ones**

For every citation naming `AppModel.swift`, `LibraryGridView.swift`, `main.swift`, `SidebarView.swift`, `CullingKeyCaptureView.swift`, `SessionRestoreState.swift`, `ActivityCenterPresentation.swift`, `ActivityCenterView.swift`, `PeopleView.swift`, `LiveMockupPlaceholder.swift`, `TimelinePresentation.swift`, or `CatalogRepository.swift`, open the cited line and confirm it still contains the symbol the surrounding prose names. Update the number when it drifted; replace the citation with the new symbol's anchor when the old symbol was deleted (e.g. `WorkspaceChromePolicy` → `LensChromePolicy`, `CullSidebarView.swift:15` → `UnifiedSidebarPresentation.swift`).

**Citations of deleted files are errors, not drift.** Any reference to `Sources/TeststripApp/CullSidebarView.swift` or `Tests/TeststripAppTests/WorkspacePresentationTests.swift` / `ImportCompletionPresentationTests.swift` must be repointed or removed.

- [ ] **Step 3: Verify no doc still describes the old shell**

```bash
grep -rn "Cull workspace\|Library workspace\|workspace switcher\|Cull|Library\|two workspaces" docs/ test/scenarios/README.md
```

Fix each hit in `docs/architecture/`, `docs/dogfooding.md`, and `docs/product/` so it describes sources × lenses. Do **not** edit `docs/superpowers/specs/` or `docs/superpowers/plans/` — those are historical records.

- [ ] **Step 4: Run the full headless gate**

Run: `make verify`
Expected: unit tests pass, the sandboxed build succeeds, and every headless verifier passes.

- [ ] **Step 5: Commit**

```bash
git status
git add docs/ test/scenarios/
git commit -m "docs: refresh file:line citations after the unified-shell cutover"
```

---

## Post-plan: the live VM run

After Task 14, `app-019-lens-shell.md` and `import-011-completion-toast-and-import-rows.md` must be driven live in the Tart VM per `test/scenarios/README.md` ("Running scenarios in a Tart VM"), and their `## Run status` plus the LEDGER rows updated with the real result. That run is a separate step in the controller's execution flow, not a task in this plan.

---

## Self-review (re-run by the plan author against the spec as amended at `edf4dea8`)

### 1. Spec coverage

| Spec requirement | Task |
|---|---|
| §Decisions 1 — sidebar-native import surface, every count in one place | 6 |
| §Decisions 2 — thin toast + Start culling, docks into the bell | 9 |
| §Decisions 3 — all imports listed and cullable; any search cullable | 6 (Imports section), 7 (Cull these) |
| §Decisions 4 — one sidebar, six lenses, ⌘1–⌘6 | 5, 6 |
| §Decisions 5 — People respects the source | 3 |
| §Decisions 6 — spec split, SP-D out of scope | Global Constraints |
| §Decisions 7 — no back-compat | 5 (Codable shim deleted), 8 (v2 discards v1) |
| §Decisions 8 — Analysis Failures survives; no Keywords child; g/c/b stay sub-modes | 1 (test), 6 (row), 5 (`cullSubModeMenuModes`) |
| §Decisions 9 — Folders + Recent Work stay sections | 6 |
| §Decisions 9 — dynamic searches relocate to Smart Collections | 6 |
| §Decisions 9 — the Map explicit-ID gap is fixed in this push | **4** |
| §Decisions 9 — `.reviewQueue` → `.smartCollection` rename | **1** |
| §Decisions 9 — lens switcher is a button row | 5B (`lensSwitcher`) |
| §Decisions 9 — receipt retention is a display cap of 5 | 9B (`ImportReceiptRow.retentionLimit`) |
| §IA — source/lens definitions, orthogonality, fallback | 5 |
| §IA — scope line | 7 |
| §IA — one 1000pt floor; ⌘I unchanged in every lens | 5 |
| §Sidebar — Library / Imports / Smart Collections / Sets / Folders / Recent Work / Selection, counts at the right edge, warning tones | 6 |
| §Sidebar — Sets is static membership only; live query = smart collection | 6 |
| §Sidebar — Imports from `workSessions(kind:statuses:)`, label from date + detail, recent 3 + overflow | 2, 6 |
| §Sidebar — "+ New from search…" reuses the existing save action | 6 |
| §Import rows — five children, nonzero only, diagnostic children open in Grid and disable Cull | 2, 5, 6 |
| §Import rows — context menu: Evaluate import, Manual Compare | 9 |
| §Completion — toast shape, ~10s, session-scoped, existing-only copy, Start culling | 9 |
| §Completion — the six named deletions; `latestImportCompletionSummary` survives | 9 |
| §Cull anything — Cull lens over any source; `SetQuery` handoff | 7 |
| §Lens rules — People source-scoped; availability; preserve source/selection/focused asset | 3, 5 |
| §Lens rules — session restore reshape | 8 |
| §Behaviour change 1 — banner gone, replaced by toast + sidebar + context menu | 9 |
| §Behaviour change 2 — ⌘1–⌘6 select lenses, no legacy bindings | 5 |
| §Behaviour change 3 — one sidebar, "Cull From" disappears | 6 |
| §Behaviour change 4 — import history visible, older imports cullable | 6 |
| §Behaviour change 5 — any search cullable; saving unchanged | 7 |
| §Behaviour change 6 — People source-scoped, global queue on All Photos | 3 |
| §Behaviour change 7 — Timeline histogram source-scoped | 10 |
| §Behaviour change 8 — restore returns source + browse lens; mid-cull → Grid | 8 |
| §Behaviour change 9 — receipts in the Activity Center, badge stays problems-only | 9 |
| §Behaviour change 10 — reopening a culling session keeps the current lens | **5B** (the `applyWorkSession` lens write is deleted), asserted by card `app-019` step 11 (Task 12) |
| §Behaviour change 11 — Map scoped for explicit-ID sources | **4**, asserted by card `app-019` step 10 (Task 12) |
| §Invariants re-asserted | Global Constraints; Task 9A asserts the badge stays problems-only; Task 1A asserts Analysis Failures still feeds it |
| §Testing — sidebar presentation bullets | 6A |
| §Testing — toast presentation bullets, banner types gone at compile level, chrome policy no longer special-cases imports | 9A |
| §Testing — lens scoping bullets | 3A, 4A, 5A |
| §Testing — Cull-these handoff bullet, save actions keep their tests | 7A |
| §Testing — E2E cards + audit existing cards in the same push | 12, 13 |

**Gaps found and closed during this re-review:** behaviour changes 10 and 11 were previously carried only as open decisions. 11 is now Task 4 (its own NA/NB pair) and 10 is now an explicit assertion in `app-019` rather than an unremarked consequence of Task 5B's deletion — a behaviour change with no test is a behaviour change nobody will notice regressing.

### 2. Placeholder scan

Searched the whole document, including all text added since the first review, for `TBD`, `TODO`, `implement later`, `add appropriate`, `handle edge cases`, `similar to Task`, and `write tests for the above`. No hits. Task 4's new prose carries verbatim Swift for the predicate, its SQL helper, all five switch arms, and `currentMapQuery()`; the two "confirm the API first" instructions that remained after the first review were both resolved into verified statements (`AssetTechnicalMetadata.init` labels, and the `public private(set)` map properties), so no step now defers a decision to the implementer.

### 3. Type consistency

Re-checked every name that crosses a task boundary after the rename and the insertion:

- **`SmartCollection`** (renamed from `ReviewQueue` in Task 1) — used with that spelling in Tasks 2B (`SmartCollection.likelyIssues.query`), 5A/5B (`LibrarySourceKind.smartCollection(SmartCollection)`, `LibrarySource.smartCollection(_:)`), 6A/6B (`smartCollectionCounts`, `SmartCollection.allCases`, `smartCollectionOrder`), 7A (`.smartCollection(.picks)`), 8A (`.smartCollection(.likelyIssues)`), 9B (`smartCollectionCounts[.providerFailures]`). Verified by grep: **zero** occurrences of `ReviewQueue`/`reviewQueue` survive after the Frozen-facts tables and Task 1, which are the only places that must name the pre-rename symbol.
- **`SmartCollection.query`** — defined 1B, consumed 2B, 5B (`applyImportChild`), 6B.
- **`applySmartCollection(_ collection:)`** — one spelling and one parameter name across 1B Step 4, 1B Step 7's falsification break, and 5B's `applySource`.
- **`SetQuery.Predicate.assetSet(AssetSetID)`** — defined 4B, consumed 4B (`currentMapQuery`) and nothing else; the five switch arms it forces are enumerated in 4B Step 3 and cross-checked against FF11's list.
- **`AppModel.currentMapQuery()`** — defined 4B, called only by `refreshPlaceData`; no later task re-derives a map scope.
- `LibraryLens` / `LibraryViewMode.lens` / `LensRules` / `LensChromePolicy` — defined 5B, used 5A, 6A, 7B, 8B.
- `LibrarySource` / `LibrarySourceKind` / `ImportChildKind` — defined 5B; every later task uses the same factories (`.allPhotos`, `.smartCollection(_:)`, `.folder(_:)`, `.workSession(_:titled:)`, `.search(_:titled:)`, `.importChild(session:child:)`, `.selection`).
- `AppModel.selectSource` / `selectLens` / `selectedSource` / `selectedLens` / `lensAvailabilities` — defined 5B; no `selectSidebarTarget` survives past Task 5, and Task 5A's Step 5 now migrates *every* occurrence by grep rather than by line number, which is what catches the calls Tasks 2A–4A added.
- `ScopeLinePresentation.line(source:lens:resultCount:activeFilterChips:cullProgress:stackCount:)` — 7A and 7B agree argument-for-argument.
- `ImportCompletionToastPresentation.toast(for:isCurrentSessionActivity:isImporting:)`, `ImportReceiptRow.rows(from:limit:)`, `AppModel.startCullingImport(sessionID:title:)` — 9A, 9B, and Task 13's card copy agree.
- `UnifiedSidebarPresentation.allImportsRowID` — defined 6B, asserted 6A, consumed by `toggleSidebarExpansion` in 6B.
- `AppModel.timelinePresentation` — defined 10B, used 10A.

One inconsistency found and fixed inline: Task 1B's `applySmartCollection` originally bound its parameter as `queue`, which the Step 7 falsification break then referred to as `collection`. Both now read `collection`, and the `smartCollectionCounts(repository:)` loop binding was renamed to match.

### 4. Open decisions — all seven resolved by Jesse (2026-08-07)

| # | Decision | Ruling | Where it lands |
|---|---|---|---|
| 1 | Folders and Recent Work are missing from the spec's sidebar list | **Keep both** as sections | Task 6; spec decision 9 + §Sidebar |
| 2 | Saved dynamic searches move to Smart Collections | **Yes** — live query = smart collection, frozen membership = set | Task 6; spec §Sidebar |
| 3 | Map over an explicit-ID source is catalog-wide | **Fix it in this push** | **Task 4** (new pair); spec behaviour change 11 |
| 4 | Reopening a culling session no longer forces the loupe | **Accepted** as a behaviour change | Task 5B + `app-019` step 11; spec behaviour change 10 |
| 5 | `.reviewQueue` vs the domain word | **Rename** | **Task 1** — and the plan author's call, per the controller's delegation, is to rename the payload type `ReviewQueue` → `SmartCollection` as well, so `LibrarySourceKind.smartCollection(SmartCollection)` reads in one vocabulary instead of two |
| 6 | Button row rather than segmented `Picker` | **Accepted** | Task 5B; spec decision 9 |
| 7 | Receipt retention of 5 | **Accepted** as a display cap | Task 9B; spec decision 9 |

### 5. One engineering deviation, flagged for the controller

The controller's instruction for the Map fix named a mechanism: "three `ids:`-taking overloads of the map repository reads (`placeClusters` / `topLocations` / `geotaggedCoverage`) plus plumbing." **Task 4 delivers the outcome by a different mechanism** — one new `SetQuery.Predicate.assetSet(AssetSetID)` — and the reasoning is written into the task itself so the implementer cannot silently drift back:

- Those three reads are **aggregates**, so an `IN`-list scope has to be chunked at 500 like every other id list here. Merging chunked results is **unsound for `topLocations`**: a location sitting just below the `LIMIT` cut in every chunk can still be the top location overall. It is merely error-prone for `placeClusters`, whose centroids are averages needing re-weighting across chunks.
- Every explicit-ID scope the new shell can produce **is a saved `AssetSet`** — `selectedExplicitAssetIDs` derives from `selectedAssetSet`, and both the Selection source and the preview-failed import child mint real sets — so one predicate closes the whole class through the `matching:` parameter that already exists.
- It is the smaller change (~35 lines plus five compiler-enforced switch arms, versus ~150 lines of bespoke overloads and merge logic), it uses the idiom `.importBatch`/`.workSession` already established, and it gives every other query surface set-scoping for free.

If the controller wants the literal `ids:` overloads instead, Task 4 is self-contained and can be swapped without touching any other task — but I do not recommend it, and the `topLocations` soundness problem is the reason.
