# Focused Workspaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restructure Teststrip's UI into three intent-based workspaces (Cull ⌘1 / Library ⌘2 / People ⌘3) with per-workspace chrome, a quiet Activity status item, one token-field query surface, and a tabbed on-demand inspector — relocating (never cutting) every existing capability per the normative ledger in the spec.

**Spec:** `docs/superpowers/specs/2026-07-09-focused-workspaces-design.md` — **read it before any task.** Its §9 relocation ledger is normative.

**Architecture:** Keep one persistent `NavigationSplitView` (in `Sources/TeststripApp/main.swift`); a new `Workspace` value on `AppModel` drives which sidebar content, main content, and chrome each workspace shows. All new logic lands first in unit-testable presentation structs (the existing pattern: `ABComparePresentationTests`, `CullingCommandMenuPresentation`), then gets thin view wiring. `LibraryGridView.swift` (~9600 lines) shrinks by extracting workspace-specific views into new files.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, XCTest (`swift test`), `script/ax_drive.sh` scenario harness (`test/scenarios/README.md`).

## Global Constraints

- **Refactor, not cut**: every ledger row in spec §9 must remain reachable. If a task would orphan a capability, stop and flag it.
- **Invariants** (spec §8): provisional machine labels never write without a user gesture; no sidecar writes without a user metadata gesture; originals untouched.
- TDD for every behavior change: failing test → minimal code → pass → commit. Presentation logic in testable structs, not in view bodies.
- Match surrounding code style; never reformat untouched code.
- Build/test: `swift build` and `swift test --filter <TestClass>`; full `swift test` before each commit.
- Existing keyboard handling lives in `GridKeyCaptureView.swift` / `CullingKeyCaptureView.swift` NSEvent monitors; menu items for character keys are built from `CullingCommandMenuPresentation` (`main.swift:206-246`) — arrows/Return stay monitor-only to avoid double-fire. Follow that split for all new keys.
- Each task's implementer MUST first read the files listed under **Files** plus `CLAUDE.md`. Line numbers below are from the 2026-07-09 audit; re-locate by symbol name if drifted.

---

## Phase 1 — Workspace shell

### Task 1: `Workspace` model and view-mode mapping

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (near `LibraryViewMode`, line ~5)
- Test: `Tests/TeststripAppTests/WorkspacePresentationTests.swift` (create)

**Interfaces:**
- Produces: `enum Workspace: String, CaseIterable { case cull, library, people }`; `extension LibraryViewMode { var workspace: Workspace }`; `AppModel.selectedWorkspace: Workspace { get }` (derived from `selectedView`) and `func selectWorkspace(_ w: Workspace)` which sets `selectedView` to that workspace's last-used sub-view (defaults: cull→`.loupe`, library→`.grid`, people→`.people`). Session restore of `selectedView` must keep working (see `AppModelSessionRestoreTests`).

- [ ] **Step 1: Write failing tests**

```swift
import XCTest
@testable import TeststripApp

final class WorkspacePresentationTests: XCTestCase {
    func testEveryViewModeMapsToExactlyOneWorkspace() {
        for mode in LibraryViewMode.allCases {
            _ = mode.workspace // exhaustive switch compiles = every mode owned
        }
        XCTAssertEqual(LibraryViewMode.loupe.workspace, .cull)
        XCTAssertEqual(LibraryViewMode.compare.workspace, .cull)
        XCTAssertEqual(LibraryViewMode.abCompare.workspace, .cull)
        XCTAssertEqual(LibraryViewMode.grid.workspace, .library)
        XCTAssertEqual(LibraryViewMode.search.workspace, .library)
        XCTAssertEqual(LibraryViewMode.timeline.workspace, .library)
        XCTAssertEqual(LibraryViewMode.map.workspace, .library)
        XCTAssertEqual(LibraryViewMode.copilot.workspace, .cull) // queues feed culling
        XCTAssertEqual(LibraryViewMode.people.workspace, .people)
    }

    func testSelectWorkspaceRestoresLastSubView() {
        let model = AppModel.makeForTesting() // reuse existing test factory; find it in AppCatalogTests setup
        model.selectedView = .timeline
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedView, .loupe)
        model.selectedView = .compare
        model.selectWorkspace(.library)
        XCTAssertEqual(model.selectedView, .timeline) // remembered
        model.selectWorkspace(.cull)
        XCTAssertEqual(model.selectedView, .compare) // remembered
    }
}
```

(Adapt the factory call to whatever existing AppModel tests use to construct a model without a catalog; do not invent a new bootstrap path.)

- [ ] **Step 2: Run** `swift test --filter WorkspacePresentationTests` — expect compile failure (no `Workspace`).
- [ ] **Step 3: Implement** `Workspace`, the `LibraryViewMode.workspace` switch, `selectedWorkspace`, `selectWorkspace(_:)` with a `private var lastSubView: [Workspace: LibraryViewMode]` remembered per workspace.
- [ ] **Step 4: Run** the filter, then full `swift test` (session-restore tests must stay green). Expect PASS.
- [ ] **Step 5: Commit** `feat: Workspace model mapping view modes to Cull/Library/People`

### Task 2: Toolbar workspace switcher, ⌘1/2/3, window title identity

**Files:**
- Modify: `Sources/TeststripApp/main.swift` (scene + commands), `Sources/TeststripApp/LibraryGridView.swift` (`libraryTopBar` ~:371, remove catalog-identity block ~:418 and breadcrumb ~:436, remove view-switcher segmented control ~:548)
- Test: `Tests/TeststripAppTests/WorkspacePresentationTests.swift` (extend), scenario in Task 23

**Interfaces:**
- Consumes: `AppModel.selectWorkspace(_:)`, `selectedWorkspace` (Task 1).
- Produces: `ToolbarItem(placement: .principal)` hosting a segmented `Picker` bound to `selectedWorkspace`; View-menu commands "Cull ⌘1 / Library ⌘2 / People ⌘3"; window title = catalog display name (set via `.navigationTitle(model.catalogDisplayName)`, reusing whatever string fed the old top-bar identity block — find it in `libraryTopBar`).

- [ ] **Step 1: Add test** that `Workspace` exposes `title: String` ("Cull"/"Library"/"People") and `keyEquivalent: KeyEquivalent`/number (1/2/3) used by both toolbar and menu (single source of truth). Run — fails.
- [ ] **Step 2: Implement** the properties; wire the `.principal` toolbar Picker in the window `.toolbar` block of `LibraryGridView` (it already owns `.toolbar`, :137) and the View menu `CommandGroup` in `main.swift` calling `model.selectWorkspace(...)` with ⌘1/2/3.
- [ ] **Step 3: Delete** the top-bar catalog identity + breadcrumb + old view-switcher from `libraryTopBar`; add `.navigationTitle`. The old switcher's grid/loupe/compare/ab entries return as Cull sub-views in Task 18 — until then Cull sub-views stay reachable via the existing Culling menu; verify menu still lists them before deleting.
- [ ] **Step 4:** `swift build && swift test`; launch `./script/build_and_run.sh --smoke` and eyeball: switcher present, title shows catalog name.
- [ ] **Step 5: Commit** `feat: workspace switcher in toolbar with ⌘1/2/3, catalog name in window title`

### Task 3: Per-workspace chrome gating

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`topInsetContent` :579, `filterBar` gate :582, bottom inset :267, key-capture overlays :297)
- Test: `Tests/TeststripAppTests/WorkspaceChromePolicyTests.swift` (create)

**Interfaces:**
- Produces: `struct WorkspaceChromePolicy { static func showsSearchField(_ w: Workspace) -> Bool; static func showsFilterTokens(_ w: Workspace) -> Bool; static func showsImportButton(_ w: Workspace) -> Bool; static func showsFooter(_ w: Workspace) -> Bool; static func showsInspector(_ w: Workspace) -> Bool }` — Library: all true; Cull/People: all false. Views branch on this policy only, never on raw workspace, so tests pin the matrix.

- [ ] **Step 1: Write test** asserting the full 5×3 matrix (Library all-true; Cull and People all-false). Run — fails.
- [ ] **Step 2: Implement** the policy struct; gate `libraryTopBar`'s search field + Import button, `filterBar`, `footer`, and the inspector column on it. Keep import progress banner visible in ALL workspaces until Task 5 rehomes it (imports must stay cancellable).
- [ ] **Step 3:** `swift test`; smoke-launch, switch ⌘1/⌘2/⌘3, confirm Cull and People show no search/import/filter/footer/inspector.
- [ ] **Step 4: Commit** `feat: per-workspace chrome policy — Cull and People drop browse chrome`

---

## Phase 2 — Quiet Activity status

### Task 4: `ActivityCenterPresentation` aggregation model

**Files:**
- Create: `Sources/TeststripApp/ActivityCenterPresentation.swift`
- Read first: `Sources/TeststripApp/ActivityView.swift`, `AppModel.swift` sidebar sections `:10842-10860` (sources, AI, sync counts), import-progress state used by the footer (`LibraryGridView.swift:2506`)
- Test: `Tests/TeststripAppTests/ActivityCenterPresentationTests.swift` (create)

**Interfaces:**
- Produces:

```swift
struct ActivityCenterPresentation {
    enum Badge: Equatable { case none, problems(Int) }
    var badge: Badge          // .problems = xmpConflicts + offlineSources + providerFailures; zero → .none
    var isWorking: Bool       // any running/queued job or active import → determinate icon state
    var jobs: [ActivityJobRow]        // existing Activity rows, full control set incl. star/pause/resume/cancel/stopIdle
    var importProgress: ImportProgressRow?  // phase label, fraction, cancel action id
    var importError: String?
    var sources: [SourceStatusRow]    // name, availability, reconnect/refresh action ids
    var xmpConflicts: [ConflictRow]   // asset ids + display names, deep-link payload
    init(model snapshot fields…)      // pure function of value inputs, no AppModel reference
}
```

- [ ] **Step 1: Write failing tests**

```swift
final class ActivityCenterPresentationTests: XCTestCase {
    func testHealthyIdleShowsNoBadgeAndNotWorking() { /* all inputs empty → .none, isWorking false */ }
    func testRunningJobsSetWorkingButNoBadge() { /* jobs running → isWorking true, badge .none */ }
    func testConflictsAndOfflineSourcesSumIntoProblemBadge() { /* 3 conflicts + 1 offline → .problems(4) */ }
    func testImportProgressAndErrorSurface() { /* import active → importProgress non-nil; error string carried */ }
}
```

Write these with real constructed inputs (small value fixtures), not comments. Run — fails.
- [ ] **Step 2: Implement** the struct as a pure transform. Minimal code to pass.
- [ ] **Step 3:** `swift test --filter ActivityCenterPresentationTests` then full suite. PASS.
- [ ] **Step 4: Commit** `feat: ActivityCenterPresentation aggregates work, import, sources, and sync status`

### Task 5: Activity toolbar item + popover; retire status furniture

**Files:**
- Create: `Sources/TeststripApp/ActivityCenterView.swift` (popover UI, reusing row views from `ActivityView.swift`)
- Modify: `LibraryGridView.swift` (toolbar :137 — add trailing item; remove import banner from `topInsetContent`; footer loses progress/errors), `AppModel.swift` (`defaultSidebarSections` :10768 — delete Sources/AI/Sync sections), `InspectorView.swift` (remove pinned Activity panel :499), `main.swift` (Window ▸ Activity menu item toggling the popover)
- Test: extend `ActivityCenterPresentationTests` for any new derived fields; scenario in Task 23

**Interfaces:**
- Consumes: `ActivityCenterPresentation` (Task 4).
- Produces: trailing `ToolbarItem` — icon-only when `badge == .none && !isWorking`; circular determinate progress when working; red numeric badge for `.problems(n)`. Popover hosts jobs / import / sources / conflicts sections with all existing actions. No permanent spinner anywhere.

- [ ] **Step 1:** Build `ActivityCenterView` from the presentation; wire toolbar item + popover + Window menu item.
- [ ] **Step 2:** Delete the sidebar Sources/AI/Sync sections, the inspector Activity panel, footer progress/error, and the top-inset import banner. Check each removed affordance against the popover: reconnect, refresh-source, cancel-import, star, stop-idle must all exist there before the old surface is deleted. AI *rows* are replaced by `signal:` tokens (Task 8) — until Task 8 lands, the AI-signal filter picker in `filterBar` still covers it; note this in the commit message.
- [ ] **Step 3:** `swift test`; smoke-launch; verify icon quiet at idle, working during import, and that killing a source (rename a seeded folder) badges it.
- [ ] **Step 4: Commit** `feat: quiet Activity toolbar item replaces Sources/AI/Sync sections, pinned Activity panel, and footer progress`

### Task 6: Conflict deep-link

**Files:**
- Modify: `ActivityCenterView.swift`, `AppModel.swift` (navigation), `InspectorView.swift` (conflict UI already exists, `InspectorMetadataConflictActionPresentation` :1133 — stays)
- Test: `Tests/TeststripAppTests/ActivityCenterPresentationTests.swift` (extend)

**Interfaces:**
- Produces: `AppModel.revealConflicts(_ assetIDs: [AssetID])` — switches to `.library`, selects the assets, opens the inspector (Info tab once Task 11 lands; whole inspector until then). Popover conflict rows call it.

- [ ] **Step 1: Test** (model-level): after `revealConflicts`, `selectedWorkspace == .library`, selection equals the ids, inspector-visible flag true. Run — fails.
- [ ] **Step 2: Implement + wire** the popover row tap.
- [ ] **Step 3:** `swift test`. Commit `feat: XMP conflict rows deep-link to affected photos in Library`

---

## Phase 3 — Library

### Task 7: Sidebar cut to Collections / Saved Sets / Folders

**Files:**
- Modify: `AppModel.swift` (`defaultSidebarSections` :10768), `SidebarView.swift` (context menus stay)
- Test: `Tests/TeststripAppTests/SidebarSectionsTests.swift` (create; if an existing sidebar test file exists, extend it instead — search `Tests/` for "sidebar" first)

**Interfaces:**
- Produces: Library sidebar sections exactly: **Collections** (All Photographs, Recent Import, Starred, Recent Work — the old Recent Work + Starred Work rows fold under a Recent Work row/group), **Saved Sets** (unchanged, context menus intact), **Folders** (unchanged). Search/Review/Timeline/People/Places rows are deleted (their destinations are now the switcher, view toggle, and Cull source picker). Review-queue rows move to the Cull sidebar (Task 13) — keep the data source, drop the Library rows.

- [ ] **Step 1: Test:** `model.sidebarSections(for: .library)` yields exactly the three sections with expected row identifiers; saved-set context-menu actions still resolve. Run — fails.
- [ ] **Step 2: Implement.** Keep `defaultSidebarSections` building blocks; add the `for workspace:` shape (Cull/People return their own in later tasks; People returns `[]`).
- [ ] **Step 3:** `swift test`; smoke-launch and verify three sections, working folder tree.
- [ ] **Step 4: Commit** `feat: Library sidebar is navigation only — Collections, Saved Sets, Folders`

### Task 8: Token query field replaces the filter bar

**Files:**
- Read first: `Sources/TeststripApp/LibrarySearchIntent.swift` (deterministic token parser — the grammar already exists), `filterBar` (`LibraryGridView.swift:608`)
- Create: `Sources/TeststripApp/LibraryQueryTokenField.swift`
- Modify: `LibraryGridView.swift` (header; delete `filterBar`), `AppModel.swift` if filter state needs a unified representation
- Test: `Tests/TeststripAppTests/LibraryQueryTokenTests.swift` (create)

**Interfaces:**
- Produces: `struct LibraryQueryToken: Equatable, Identifiable { let field: LibrarySearchField; let display: String; let value: … }` plus bidirectional bridge: existing structured filter state ⇄ `[LibraryQueryToken]` ⇄ query text via `LibrarySearchIntent`. The view is a `.searchable(text:tokens:)`-style token field with an autocomplete menu listing every old picker's options (sort excluded — sort becomes a separate persistent header `Picker`). Free text that parses to no token stays as the agentic ask. Search-tips popover retained.

- [ ] **Step 1: Tests:** round-trip — each of the 13 old pickers' example values (rating≥3, flag=pick, keyword, folder, camera, lens, iso≥800, date range, color, source, signal, xmp-pending) converts filterState→tokens→filterState losslessly; removing a token clears exactly its filter; `"person:\"Maya\" rating:3 golden hour"` parses to 2 tokens + free text `"golden hour"`. Run — fails.
- [ ] **Step 2: Implement** the bridge on top of `LibrarySearchIntent` (do not fork the grammar).
- [ ] **Step 3: Wire the view**; delete `filterBar`; move sort into the header as a persistent control; keep clear-all as a small "Clear" affordance when tokens exist.
- [ ] **Step 4:** `swift test`; smoke-launch: type `rating:3`, see token + filtered grid; remove token, grid restores.
- [ ] **Step 5: Commit** `feat: one query surface — token search field replaces the filter bar; sort stays persistent`

### Task 9: Result header — interpretation line + Save ▾

**Files:**
- Read first: `SearchWorkspaceView` (`LibraryGridView.swift:7128`) and its refine rail :7207 — this task absorbs it; delete the `search` view mode route after.
- Modify: `LibraryGridView.swift`, `AppModel.swift` (`LibraryViewMode.search` removal + migration in restore)
- Test: `Tests/TeststripAppTests/LibraryResultHeaderTests.swift` (create)

**Interfaces:**
- Produces: `struct LibraryResultHeaderPresentation { var matchCount: Int; var interpretation: String?; var suggestedTokens: [LibraryQueryToken]; var saveActions: [SaveAction] }` where `SaveAction` covers **dynamic search / frozen snapshot / manual set** (reuse the three existing save paths from filterBar/SearchWorkspace — find their model calls before writing new ones). Interpretation string comes from `LibrarySearchIntent`'s parse; suggested tokens absorb "Generated Refinements"/"Related Filters" and feed the token field's menu.

- [ ] **Step 1: Tests:** empty query → nil interpretation + no header; tokened query → interpretation text + count; three save actions present and mapped to the distinct model calls. Run — fails.
- [ ] **Step 2: Implement** presentation + header row under the Library header; Save ▾ menu; migrate `.search` restore to `.grid` + tokens.
- [ ] **Step 3: Delete** `SearchWorkspaceView` and the `.search` case once tests and a smoke pass confirm all its capabilities (interpretation, refinements, 3 saves, metrics) exist in the new surfaces.
- [ ] **Step 4:** `swift test`; smoke. Commit `feat: search results are a Library state — interpretation line, suggested tokens, Save menu`

### Task 10: Library view toggle — Grid / Loupe / Timeline / Map

**Files:**
- Modify: `LibraryGridView.swift` (header toggle; `TimelineWorkspaceView` :7672 and `PlacesWorkspaceView` :7513 become views of the current result set; loupe reuse from `LoupeView` :3520), `AppModel.swift` (`.timeline`/`.map` stay as `LibraryViewMode`s under `.library`; add `.libraryLoupe` or equivalent)
- Test: `Tests/TeststripAppTests/WorkspacePresentationTests.swift` (extend mapping), scenario Task 23

**Interfaces:**
- Produces: header segmented toggle Grid/Loupe/Timeline/Map bound to the Library sub-view; **Enter/Space on a grid cell opens Loupe on that asset** (wire in `GridKeyCaptureView.swift`); Library Loupe = `LoupeView` with a `showsCullChrome: Bool` (or split subviews) flag that hides the cull HUD, stack rail, pick/reject pills, and assist — plain navigation + EXIF overlay only. Timeline/Map render the current filtered result set (they already read model scope — verify tokens flow through).

- [ ] **Step 1: Test:** `.libraryLoupe.workspace == .library`; chrome flag matrix (cull loupe shows HUD, library loupe doesn't) via a small `LoupePresentation` struct if one doesn't exist — create it to carry the flag rather than branching in the view.
- [ ] **Step 2: Implement**; Enter/Space handling; Esc returns to grid.
- [ ] **Step 3:** `swift test`; smoke: filter to a token, flip through all four views, confirm same result set everywhere.
- [ ] **Step 4: Commit** `feat: Loupe/Timeline/Map are Library views of the current result set`

### Task 11: Tabbed on-demand inspector

**Files:**
- Modify: `Sources/TeststripApp/InspectorView.swift` (restructure into tabs), `LibraryGridView.swift`/`main.swift` (`.inspector(isPresented:)` + ⌘I command), delete the fixed detail column in `main.swift:29-35`
- Test: `Tests/TeststripAppTests/InspectorTabsPresentationTests.swift` (create)

**Interfaces:**
- Produces: `enum InspectorTab { case info, describe, ai }` with `⌥⌘1..3` menu items; `struct InspectorTabPresentation` assigning every existing inspector element to exactly one tab:
  - **info**: preview, identity header, rating/flag/label *display*, EXIF (`InspectorTechnicalRows`), sync status incl. per-field conflict resolver, preview-retry.
  - **describe**: keyword chips + field, caption/creator/copyright fields, **suggested keywords and OCR caption suggestions inline beside their fields** (move from their current blocks), multi-select "applies to all N selected" note, rating/flag/label *edit buttons* (they're metadata authoring; keys still work everywhere).
  - **ai**: "What Teststrip Sees" verdict groups, technical-details disclosure + provenance, provider-failure retry, needs-eyes/diagnostics text (from Copilot, Task 13 routes it here).
  ⌘I toggles in Library/People; in Cull it calls `model.selectWorkspace(.library)` first (spec: works everywhere).

- [ ] **Step 1: Test:** every element identifier from the current inspector appears in exactly one tab (enumerate them in the test — this is the anti-orphan check); ⌘I-in-Cull behavior at model level. Run — fails.
- [ ] **Step 2: Implement** tab presentation + restructure `InspectorView` into three tab bodies reusing existing section views; adopt `.inspector()`.
- [ ] **Step 3:** `swift test`; smoke: ⌘I toggles; conflict resolver reachable via Activity deep-link (Task 6) lands on Info.
- [ ] **Step 4: Commit** `feat: inspector is on-demand (⌘I) with Info/Describe/AI tabs; suggestions inline in Describe`

### Task 12: Library footer cleanup

**Files:**
- Modify: `LibraryGridView.swift` (`footer` :2506)
- Test: covered by `WorkspaceChromePolicyTests` + smoke

**Interfaces:**
- Produces: footer = counts + selection · density control · zoom slider only, with View-menu ⌘+/⌘- zoom equivalents. Load Previous/More stay **only if** grid virtualization isn't already handling it — check how paging works in `assetGrid` first; if the pager is load-on-scroll plumbing, keep the buttons; do not build virtualization in this task.

- [ ] **Step 1:** Trim footer (progress/errors already moved in Task 5); add ⌘+/⌘- menu items adjusting the existing `@AppStorage` thumbnail size.
- [ ] **Step 2:** `swift test`; smoke. Commit `feat: Library footer slims to counts, density, zoom (⌘+/⌘-)`

---

## Phase 4 — Cull

### Task 13: Cull sidebar — source picker + stacks

**Files:**
- Read first: stack rail (`LibraryGridView.swift:3603`), review queues (`AppModel.swift` `ReviewQueue` :238), `CopilotView.swift`
- Create: `Sources/TeststripApp/CullSidebarView.swift`
- Modify: `AppModel.swift` (`sidebarSections(for: .cull)`), `LibraryGridView.swift` (remove in-stage stack rail), `CopilotView.swift` (delete route after capabilities verified re-homed)
- Test: `Tests/TeststripAppTests/CullSourcePresentationTests.swift` (create)

**Interfaces:**
- Produces: `struct CullSourcePresentation { var sources: [CullSource] }` where `CullSource` ∈ recent imports, `ReviewQueue` entries (Top Picks, Needs Eyes — reusing the queue models Copilot reads), and a handed-off Library selection (`AppModel.cullCurrentSelection()` — new: switches to `.cull` scoped to selection; expose as a Library context-menu item "Cull These" and the existing toolbar Cull action). Stack list below sources (existing stack rows). Needs-eyes *reasons* surface via Inspector ▸ AI (Task 11) and the HUD verdict; Copilot diagnostics text moves under the AI tab's disclosure.

- [ ] **Step 1: Tests:** sources list contains recent import + both queues; `cullCurrentSelection` scopes the cull session to the selected ids and switches workspace. Run — fails.
- [ ] **Step 2: Implement** sidebar view + model; move stack rows into it; delete the in-stage rail.
- [ ] **Step 3: Delete Copilot route** only after asserting Top Picks/Needs Eyes counts appear in the source picker and diagnostics text renders under AI tab.
- [ ] **Step 4:** `swift test`; smoke. Commit `feat: Cull sidebar hosts source picker (imports, review queues, selection) and stacks; Copilot route absorbed`

### Task 14: Cull HUD consolidation

**Files:**
- Modify: `LibraryGridView.swift` (`LoupeView` header :3740, assist pill, loupe metadata overlay :4287)
- Create: `Sources/TeststripApp/CullHUDPresentation.swift`
- Test: `Tests/TeststripAppTests/CullHUDPresentationTests.swift` (create)

**Interfaces:**
- Produces: `struct CullHUDPresentation { var filename: String; var rating: Int; var colorLabel: ColorLabel?; var progressFraction: Double; var undecidedCount: Int; var pickCount: Int; var rejectCount: Int; var scope: CullScope; var verdict: String? }` — one top row over the stage; assist verdict is HUD text, never an image overlay. Command rail (:4138) is deleted — its buttons duplicate keys that stay; verify each rail control has a key + menu item before deleting.

- [ ] **Step 1: Tests:** presentation computed from a fixture cull session (counts, undecided = total − picks − rejects within scope, verdict passthrough). Run — fails.
- [ ] **Step 2: Implement** + rewire `LoupeView` header; delete command rail and bottom assist pill.
- [ ] **Step 3:** `swift test`; smoke: keystroke 3 visibly updates HUD stars. Commit `feat: single-row Cull HUD with rating echo, undecided count, and inline verdict`

### Task 15: Cull scope cycle (S)

**Files:**
- Modify: `AppModel.swift`, `CullingKeyCaptureView.swift`, `main.swift` (Culling menu item)
- Test: `Tests/TeststripAppTests/CullScopeTests.swift` (create)

**Interfaces:**
- Produces: `enum CullScope: CaseIterable { case unrated, picks, rejects, all }` with `next()`; `AppModel.cullScope` filtering the cull ordering (loupe advance, filmstrip, grid sub-view all honor it); key `s` + Culling ▸ "Cycle Scope" menu item; HUD chip shows it (Task 14 field).

- [ ] **Step 1: Tests:** cycle order unrated→picks→rejects→all→unrated; scoped ordering only contains matching frames; current frame stays if it matches, else advances to nearest match. Run — fails.
- [ ] **Step 2: Implement**; wire key + menu.
- [ ] **Step 3:** `swift test`; smoke a picks-only second pass. Commit `feat: in-cull scope cycle (S) — unrated/picks/rejects/all`

### Task 16: Stack decide-and-advance

**Files:**
- Modify: `AppModel.swift` (stack actions), `CullingKeyCaptureView.swift` (Return, ⌥→/⌥←)
- Test: `Tests/TeststripAppTests/StackDecisionTests.swift` (create)

**Interfaces:**
- Produces: `AppModel.promoteCurrentFrameAndRejectSiblings()` — flags current frame Pick, siblings in stack Reject, advances to first undecided frame of next stack (single undo group: one ⌘Z reverts the whole gesture — check how the undo manager batches metadata ops in the existing undo tests); `nextStack()/previousStack()` on ⌥→/⌥⌥←. Return already means "Accept Stack Selection" (`AppModel.swift:187-220`) — this replaces that binding; confirm the old accept semantics are subsumed (promote = accept + reject rest) and update `CullingCommandMenuPresentation` text.

- [ ] **Step 1: Tests:** 4-frame stack, promote frame 2 → frame 2 pick, 1/3/4 reject, position lands on next stack's first undecided; single undo reverts all four flags; confirm-before-write: promoting never touches assets outside the stack. Run — fails.
- [ ] **Step 2: Implement**; rebind Return; add ⌥ arrows (monitor-only, no menu equivalents per the double-fire rule; document in `?` overlay Task 19).
- [ ] **Step 3:** `swift test`; smoke. Commit `feat: Return promotes frame and rejects stack siblings; ⌥arrows jump stacks`

### Task 17: Decision toast + stack-aware filmstrip

**Files:**
- Modify: `LibraryGridView.swift` (filmstrip in `LoupeView`), create `Sources/TeststripApp/CullFilmstripPresentation.swift`
- Test: `Tests/TeststripAppTests/CullFilmstripPresentationTests.swift` (create)

**Interfaces:**
- Produces: `struct CullFilmstripPresentation { var items: [Item /* frame or stackDivider */]; var positionText: String /* "frame 121 / 318 · stack 34 / 96" */ }`; toast: last decision line ("✕ DSCF1023 rejected — U undoes") auto-fading, driven by the existing last-decision feedback state (:3740 already has a feedback pill — reuse its source).

- [ ] **Step 1: Tests:** dividers appear exactly between stacks; position string math; toast text for pick/reject/rating events. Run — fails.
- [ ] **Step 2: Implement**; render dividers + readout + toast.
- [ ] **Step 3:** `swift test`; smoke. Commit `feat: stack-aware filmstrip with position readout; decision toast with undo hint`

### Task 18: Cull sub-views G/C/B + compare refill

**Files:**
- Modify: `CullingKeyCaptureView.swift`, `main.swift` (View menu), `LibraryGridView.swift` (`CompareView` :6072)
- Test: `Tests/TeststripAppTests/CompareRefillTests.swift` (create)

**Interfaces:**
- Produces: keys `g`/`c`/`b` switch `.grid-sub-view`/`.compare`/`.abCompare` within Cull (grid sub-view = asset grid scoped to the cull session, keeps autopilot KEEP/CUT badges) + View-menu items; **compare refill**: rejecting a frame in Compare removes it and appends the next undecided frame from the same stack (if any). Entering Compare from a stack auto-populates with the stack's frames (cap 8, recommended-first).

- [ ] **Step 1: Tests:** refill pulls next stack member; no refill when stack exhausted; auto-populate ordering. Run — fails.
- [ ] **Step 2: Implement** keys + menu + refill.
- [ ] **Step 3:** `swift test`; smoke. Commit `feat: G/C/B cull sub-views; Compare rejects refill from the stack`

### Task 19: Z zoom-to-face, I EXIF overlay cycle, ? key map

**Files:**
- Read first: existing `z` 1:1 zoom handling, Close-Ups face-crop source (`LibraryGridView.swift:3685` — face boxes already computed), loupe metadata overlay :4287
- Modify: `CullingKeyCaptureView.swift`, `LoupeView`, `main.swift` (menu items for Z/I; `?` overlay is view-only)
- Test: `Tests/TeststripAppTests/LoupeOverlayPresentationTests.swift` (create)

**Interfaces:**
- Produces: `Z` (shift-z) zooms 1:1 centered on the nearest detected face; while zoomed, ←/→ cycle detected faces (fall back to plain 1:1 center when no faces); `I` cycles `enum ExifOverlayLevel { off, exposureLine, full }` restructuring the existing metadata overlay; `?` shows a key-map overlay generated from `CullingCommandMenuPresentation` (single source of truth — includes monitor-only keys like ⌥ arrows with a flag so the menu builder still skips them).

- [ ] **Step 1: Tests:** overlay level cycle; key-map presentation includes every shortcut incl. monitor-only ones; face-cycle index wraps. Run — fails.
- [ ] **Step 2: Implement**; reuse face boxes from the Close-Ups pipeline for zoom targets.
- [ ] **Step 3:** `swift test`; smoke: Z on a seeded face photo. Commit `feat: zoom-to-face (Z), EXIF overlay cycle (I), and ? key map in Cull`

### Task 20: End-of-set handoff

**Files:**
- Modify: `LibraryGridView.swift` (`LoupeView` completion banner area), `AppModel.swift`
- Test: `Tests/TeststripAppTests/CullCompletionTests.swift` (create)

**Interfaces:**
- Produces: `struct CullCompletionPresentation { var picks: Int; var rejects: Int; var actions: [Export, MoveRejects, ReviewPicks] }` shown as a stage-replacing state when `undecidedCount == 0` in the current scope; Export and Move Rejects invoke the existing model actions (find them behind the toolbar Export and More ▸ Move Rejects); ReviewPicks sets scope to `.picks`. Existing completion + autopilot review banners merge into this state.

- [ ] **Step 1: Tests:** presentation appears only at zero undecided; actions map to the right model calls (spy/inspect action ids). Run — fails.
- [ ] **Step 2: Implement.** `swift test`; smoke a 24-photo full cull to completion. Commit `feat: end-of-set state offers Export, Move Rejects, review picks`

---

## Phase 5 — People, menus, sizing, scenarios

### Task 21: People queue keyboard flow + scan rehoming

**Files:**
- Modify: `Sources/TeststripApp/PeopleView.swift`, `AppModel.swift`, `main.swift` (People menu: "Scan for Faces")
- Test: `Tests/TeststripAppTests/PeopleQueuePresentationTests.swift` (create; check for existing People presentation tests first and extend)

**Interfaces:**
- Produces: card focus model — `PeopleQueuePresentation { var cards: [Card]; var focusedIndex: Int }`, ←/→ move focus, **Return = confirm on the focused card** (the explicit write gesture; Space does nothing), Esc dismisses; review cards ("Unnamed faces", "face quality") join the same queue as cards; the scan button leaves the canvas — scanning triggers via People ▸ Scan for Faces and reports through the Activity item; person tap opens Library with a `person:` token (uses Task 8 tokens).

- [ ] **Step 1: Tests:** focus wrap; Return fires confirm only on focused card; **negative assertion: no `people`/`person_assets` rows before Return** (existing invariant tests show the pattern — search for them and mirror). Run — fails.
- [ ] **Step 2: Implement**; wire menu + Activity reporting; person→Library token.
- [ ] **Step 3:** `swift test`; smoke with `--faces` seed. Commit `feat: keyboard-driven People queue; scan moves to menu + Activity`

### Task 22: Menu bar completion + per-workspace window minimums

**Files:**
- Modify: `main.swift` (menus, `AppWindowLayoutMetrics` :4-10), `LibraryGridView.swift` (frame constraints)
- Test: `Tests/TeststripAppTests/MenuCoveragePresentationTests.swift` (create)

**Interfaces:**
- Produces: full menu tree per spec §6 (File/View/Culling/Metadata/Go/Window/Support). Coverage test: every action id in `CullingCommandMenuPresentation` + workspace/sub-view/inspector-tab/zoom actions has a menu item (monitor-only keys exempt via their flag). Window minimums: replace the global 1520×720 with per-workspace floors — Library ≈1000pt, Cull ≈800pt, People ≈700pt wide (tune to what actually fits; the requirement is no workspace pays for another's chrome). Sidebar/inspector collapse before content squeezes.

- [ ] **Step 1: Test** menu coverage (presentation-level: enumerate expected action ids vs menu-built ids). Run — fails.
- [ ] **Step 2: Implement** remaining menu items; per-workspace `frame(minWidth:)` driven by `selectedWorkspace`.
- [ ] **Step 3:** `swift test`; smoke at narrow widths in each workspace. Commit `feat: complete menu coverage; per-workspace window minimums replace the 1520pt floor`

### Task 23: End-to-end scenarios

**Files:**
- Read first: `test/scenarios/README.md` (mandatory — isolation, `ax_drive.sh` realities, idle-wedge), `script/verify_people_clustering.sh` (reference pattern)
- Create: `test/scenarios/focused_workspaces_smoke.sh` (or per-flow scripts matching the existing naming convention — follow what's in `test/scenarios/`)
- Test: the scenarios ARE the tests

**Interfaces:**
- Consumes: everything above. Launch via `./script/build_and_run.sh --smoke` (24 seeded photos) and `--faces` for People.

Scenarios (each asserts catalog ground truth in `$ISOLATED/Teststrip/catalog.sqlite`, not renders):
1. **Workspace switching:** drive ⌘1/⌘2/⌘3 and the toolbar switcher; assert AX tree shows the right workspace roots.
2. **Quiet Activity:** at idle, no badge AX element; seed an XMP conflict (edit a sidecar out-of-band, per existing sync tests' technique) → badge appears → popover row → lands in Library with the asset selected.
3. **Token query:** type `rating:3` into the field, press return; assert grid count matches `SELECT count(*) ... rating=3`; remove token; count restores.
4. **Cull pass:** enter Cull, P/X a few frames, S to picks scope, assert scope; Return on a stack → assert pick+sibling rejects in sqlite as one gesture; ⌘Z reverts all.
5. **End-of-set:** decide all 24 → completion state visible; Move Rejects moves files (assert on disk).
6. **Library loupe:** Enter on a cell → loupe without pick/reject pills (AX); Esc back.
7. **Inspector:** ⌘I opens; Describe tab accepts a suggested keyword with one click → keyword in sqlite + sidecar written.
8. **People:** with `--faces`, arrow to a card, Return confirms → `person_assets` row appears **only after** Return (query before and after).

- [ ] **Step 1:** Write scenarios 1–4; run each (`wait-vended` on every poll; keep app frontmost). Fix app bugs they surface (they will).
- [ ] **Step 2:** Write scenarios 5–8; run.
- [ ] **Step 3:** Full `swift test` + all scenarios green. Commit `test: end-to-end scenarios for focused workspaces`
- [ ] **Step 4:** Update `docs/dogfooding.md` for the new chrome (launch expectations, where import/activity/status now live) and mark the relevant `LiveMockupDesignSurfaces` entries. Commit `docs: dogfooding guide reflects focused workspaces`

---

## Self-review notes

- Spec coverage: §1→T1-3, §2→T4-6, §3→T13-20, §4→T7-12, §5→T21, §6/§7→T22, §11→T23. Ledger rows each named in a task's Interfaces/Steps; T11 Step 1 and T5 Step 2 are explicit anti-orphan checks.
- Preload-ahead engineering invariant (spec §3) is intentionally not a task: verify during T23 scenario 4 that advance never blocks; if it does, flag to Jesse before building anything (perf-restraint rule in CLAUDE.md).
- Deferred by spec §10: workspace-count revisit, star-concept cleanup — no tasks, correct.
