# Culling Flow Shell (SP-A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the Cull workspace loupe into the validated culling-flow shell: burst rail left, photo-only stage, faces+reads panel right, run strip bottom, uniform keys with or without bursts, honest AI states, user-origin-only progress, and a full completion summary.

**Architecture:** Evolve `LoupeView` (stays a private struct in `LibraryGridView.swift`) and `AppModel`'s existing culling machinery. New pure logic lands as `<Feature>Presentation.swift` files with unit tests; view code re-plumbs proven parts. No schema changes, no worker changes.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md` (SP-A section). UX contract: `docs/design-spikes/2026-07-16-culling-redesign/tutorial.md`.

## Global Constraints

- Bare culling keys are handled ONLY by the local key monitor (`CullingKeyCaptureView`), never as SwiftUI `.keyboardShortcut` menu equivalents (double-dispatch regression documented in `main.swift` near the menu setup).
- Every new bare key gets a row in `CullingCommandMenuPresentation.sections` (single source for the `?` overlay and the Culling menu) plus decode tests in `Tests/TeststripAppTests/CullingKeyCaptureTests.swift`.
- ✨ tentative flags never count as decided: all "decided" math goes through `metadata.confirmedProjection.flag`. Assert the negative in tests wherever a count or done-state is computed.
- Machine-fact stack labels only (file-range · count · time) — never content names.
- One home per fact in the loupe: stage = image + shimmer + toast + hover controls only; reads/faces = right panel only; ✦/✨/decisions/rank = rail and strip only; position/progress = status bar only.
- New pure presentation types go in their own `Sources/TeststripApp/<Feature>Presentation.swift` file; view structs stay in `LibraryGridView.swift`.
- ALL line numbers in this plan are approximate (they drift daily) — locate by symbol name (`grep -n`) before editing.
- Each task: TDD (failing test first), run the named test file(s) with `swift test --filter <TestClass>`, commit per task. `make verify` runs once at branch end (controller handles sample-data symlinks in the worktree).
- Match surrounding code style exactly; smallest reasonable change; no whitespace churn.

---

### Task 1: H/L/J/K aliases + standalone frame-key fallback

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`CullingShortcut.init?(key:)` character switch; `moveSelectionWithinCurrentCullingStack(by:)`; `CullingCommandMenuPresentation.sections`)
- Test: `Tests/TeststripAppTests/CullingKeyCaptureTests.swift`, `Tests/TeststripAppTests/CullStackNavigationTests.swift`

**Interfaces:**
- Consumes: existing `CullingShortcut` cases `.previousStack/.nextStack/.nextCandidateInStack/.previousCandidateInStack`; `selectNextAssetForCulling()`/`selectPreviousAssetForCulling()`; `selectedCullingStackScope`.
- Produces: `"h"/"l"/"j"/"k"` decode to the four existing cases; frame keys fall back to stop-to-stop advance on standalone frames (no dead keys). No new public API.

- [ ] **Step 1: Write failing decode tests** in `CullingKeyCaptureTests.swift`, following the existing `testCullingShortcutMaps*` naming and style:

```swift
func testCullingShortcutMapsVimStackAliases() {
    XCTAssertEqual(CullingShortcut(key: .character("h")), .previousStack)
    XCTAssertEqual(CullingShortcut(key: .character("l")), .nextStack)
    XCTAssertEqual(CullingShortcut(key: .character("H")), .previousStack)
    XCTAssertEqual(CullingShortcut(key: .character("L")), .nextStack)
}

func testCullingShortcutMapsVimFrameAliases() {
    XCTAssertEqual(CullingShortcut(key: .character("j")), .nextCandidateInStack)
    XCTAssertEqual(CullingShortcut(key: .character("k")), .previousCandidateInStack)
}
```

(Adapt constructor spelling to the file's existing tests — they already build `.character(...)` keys.)

- [ ] **Step 2: Write the failing standalone-fallback test** in `CullStackNavigationTests.swift`, modeled on that file's existing fixtures (it already builds an AppModel over a seeded catalog): select a standalone (non-stacked) asset, apply `.nextCandidateInStack` via `applyCullingShortcut`, assert the selection advanced to the next asset (today it stays put); mirror test for `.previousCandidateInStack`.

- [ ] **Step 3: Run to verify failures**

Run: `swift test --filter CullingKeyCaptureTests 2>&1 | tail -5` and `swift test --filter CullStackNavigationTests 2>&1 | tail -5`
Expected: the three new tests FAIL (nil decode / unmoved selection); everything else passes.

- [ ] **Step 4: Implement decode aliases.** In `CullingShortcut.init?(key:)`'s `case .character(let character): switch character.lowercased()` block, add `"h"`/`"l"`/`"j"`/`"k"` to the same case values as the arrow keys (`.previousStack`, `.nextStack`, `.nextCandidateInStack`, `.previousCandidateInStack`). No event-decoder change needed — bare characters already flow through the generic path in `CullingKeyCaptureView.swift`.

- [ ] **Step 5: Implement the standalone fallback.** In `moveSelectionWithinCurrentCullingStack(by:)`, where the guard on `selectedCullingStackScope` currently returns early, fall back instead:

```swift
guard let scope = selectedCullingStackScope else {
    if delta > 0 { try selectNextAssetForCulling() }
    else { try selectPreviousAssetForCulling() }
    return
}
```

(Match the function's real signature/throws-ness and feedback-clearing conventions — mirror what the `.nextPhoto` dispatch arm does around `selectNextAssetForCulling`.)

- [ ] **Step 6: Update discoverability.** In `CullingCommandMenuPresentation.sections`, amend the existing navigation rows' key text to disclose the aliases (e.g. `"← / H"`, `"→ / L"`, `"↑ / K"`, `"↓ / J"` — match the table's existing key-string format). Update `CullingCommandMenuPresentationTests` expectations if they assert those strings.

- [ ] **Step 7: Run tests + commit**

Run: `swift test --filter CullingKeyCaptureTests && swift test --filter CullStackNavigationTests && swift test --filter CullingCommandMenuPresentationTests`
Expected: PASS. Commit: `feat: vim-style culling aliases (H/L/J/K) and standalone frame-key fallback`

---

### Task 2: Auto-advance toggle (`A`) + advance-to-next-undecided

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (new state + `CullingShortcut` case + dispatch arm + `applyCullingCommandAndAdvance` advance target; `CullingCommandMenuPresentation.sections`)
- Test: `Tests/TeststripAppTests/CullAutoAdvanceTests.swift` (new), `Tests/TeststripAppTests/CullingKeyCaptureTests.swift`

**Interfaces:**
- Consumes: `applyCullingCommandAndAdvance` (locate by symbol; it currently advances linearly after P/X), `selectedCullingStackScope`, `metadata.confirmedProjection.flag`, `selectCullingStack`/`recommendedStackLandingAssetID`.
- Produces: `public private(set) var cullAutoAdvanceEnabled: Bool = true` + `func toggleCullAutoAdvance()`; `CullingShortcut.toggleAutoAdvance` decoded from `"a"`. Advance semantics after a P/X decision: next *undecided* (confirmed-flag nil) frame in the current stack searching forward with wrap; if none, the next stack's landing frame (existing landing machinery); if auto-advance is off, no movement.

- [ ] **Step 1: Write failing tests** in new `CullAutoAdvanceTests.swift` (fixture pattern copied from `CullStackNavigationTests.swift`): (a) decode: `"a"` → `.toggleAutoAdvance`; (b) P on frame 1 of a 3-frame stack with frame 2 already user-picked advances to frame 3 (next *undecided*, skipping decided); (c) deciding the last undecided frame advances out of the stack to the next stop's landing frame; (d) with `cullAutoAdvanceEnabled == false`, P leaves selection unchanged; (e) **negative (invariant):** a sibling with only a tentative ✨ flag (metadata flag set but field present in `aiUnconfirmedFields`) still counts as *undecided* for the advance search.
- [ ] **Step 2: Run to verify failures.** Run: `swift test --filter CullAutoAdvanceTests 2>&1 | tail -5`. Expected: FAIL (missing symbol / wrong advance target).
- [ ] **Step 3: Implement.** Add the state + toggle + shortcut case + dispatch arm (dispatch shows a feedback toast "Auto-advance on/off" via the existing `cullingMetadataDecisionFeedback` mechanism). Rework the advance target inside `applyCullingCommandAndAdvance`: when the decided asset sits in a multi-frame `selectedCullingStackScope`, scan stack members from the next index (wrapping) for the first with `confirmedProjection.flag == nil` and select it; otherwise (or if none) use the existing next-stop path. Honor `cullAutoAdvanceEnabled == false` by skipping all movement.
- [ ] **Step 4: Menu row.** Add an `A — Toggle auto-advance` row to `CullingCommandMenuPresentation.sections`; update its tests.
- [ ] **Step 5: Run + commit.** Run: `swift test --filter CullAutoAdvanceTests && swift test --filter CullingKeyCaptureTests && swift test --filter CullingCommandMenuPresentationTests && swift test --filter StackDecisionTests`. Expected: PASS (StackDecisionTests still green — its advance expectations may need updating if they asserted linear advance; update them to the new next-undecided semantics, they are part of this task's spec). Commit: `feat: culling auto-advance toggle with next-undecided advance target`

---

### Task 3: Machine-fact stack labels (pure)

**Files:**
- Create: `Sources/TeststripApp/CullStackLabelPresentation.swift`
- Test: `Tests/TeststripAppTests/CullStackLabelPresentationTests.swift`

**Interfaces:**
- Consumes: `Asset.originalURL`, `Asset.technicalMetadata?.capturedAt`.
- Produces: `struct CullStackLabelPresentation` with `static func label(for assets: [Asset]) -> String` (multi-frame: `"R5A_4021–4026 · 6 · 14:02"`) and `static func standaloneLabel(for asset: Asset) -> String` (`"R5A_4030 · 14:05"`). Later tasks (5, 6) render these verbatim.

- [ ] **Step 1: Write failing tests** covering: numeric-suffix range collapse (`IMG_0412`…`IMG_0417` → `IMG_0412–0417 · 6 · <time>`); mixed/non-numeric stems fall back to `first…last` stems; missing `capturedAt` omits the time segment cleanly (no dangling separator); single-asset standalone label; time uses `Date.FormatStyle` `.shortened` (assert via formatting the same fixture date, not a hard-coded locale string).
- [ ] **Step 2: Run to verify failure.** Run: `swift test --filter CullStackLabelPresentationTests 2>&1 | tail -5`. Expected: FAIL (type missing).
- [ ] **Step 3: Implement** (complete logic — adapt only naming conventions):

```swift
import Foundation
import TeststripCore

/// Machine-derived stack labels for culling surfaces: file range, frame
/// count, start time. Stacks are auto-grouped — labels must never imply
/// curated names.
struct CullStackLabelPresentation {
    static func label(for assets: [Asset]) -> String {
        guard let first = assets.first else { return "" }
        if assets.count == 1 { return standaloneLabel(for: first) }
        var segments = [fileRange(for: assets), "\(assets.count)"]
        if let time = timeText(for: first) { segments.append(time) }
        return segments.joined(separator: " · ")
    }

    static func standaloneLabel(for asset: Asset) -> String {
        var segments = [stem(of: asset)]
        if let time = timeText(for: asset) { segments.append(time) }
        return segments.joined(separator: " · ")
    }

    private static func stem(of asset: Asset) -> String {
        asset.originalURL.deletingPathExtension().lastPathComponent
    }

    private static func timeText(for asset: Asset) -> String? {
        asset.technicalMetadata?.capturedAt?.formatted(date: .omitted, time: .shortened)
    }

    private static func fileRange(for assets: [Asset]) -> String {
        let stems = assets.map(stem(of:))
        guard let first = stems.first, let last = stems.last else { return "" }
        // Collapse "IMG_0412"…"IMG_0417" to "IMG_0412–0417" when both share
        // a prefix and end in digits; otherwise fall back to "first…last".
        let firstDigits = trailingDigits(of: first)
        let lastDigits = trailingDigits(of: last)
        let firstPrefix = String(first.dropLast(firstDigits.count))
        let lastPrefix = String(last.dropLast(lastDigits.count))
        if !firstDigits.isEmpty, !lastDigits.isEmpty, firstPrefix == lastPrefix {
            return "\(first)–\(lastDigits)"
        }
        return "\(first)…\(last)"
    }

    private static func trailingDigits(of stem: String) -> String {
        String(stem.reversed().prefix(while: \.isNumber).reversed())
    }
}
```

- [ ] **Step 4: Run + commit.** Run: `swift test --filter CullStackLabelPresentationTests`. Expected: PASS. Commit: `feat: machine-fact stack labels for culling surfaces`

---

### Task 4: Honest ranking states — tied leaders + strict reads gating

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`CullingStackRecommendation` — locate by symbol; `CullingStackRailPresentation`; the `recommendedAssetID` computation threaded to rail + strip)
- Create: `Sources/TeststripApp/CullReadsCardPresentation.swift`
- Test: `Tests/TeststripAppTests/CullReadsCardPresentationTests.swift` (new), `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift`, `Tests/TeststripAppTests/CullingAssistPresentationTests.swift`

**Interfaces:**
- Consumes: `CullingStackRecommendation.rankedCandidates(...)` and `.normalizedQualityRead(for:) -> (score: Double, kindCount: Int)?` (the 0…1 confidence-weighted mean — the ONLY valid basis for cross-frame margins; the raw `qualityScore` sum is kind-count-dependent and must not be compared across frames).
- Produces:
  - `CullingStackRecommendation.tiedLeaderIDs(...) -> [AssetID]?` — non-nil (≥2 IDs, capture order) when the leaders' normalized reads sit within `tooCloseToCallMargin`; `static let tooCloseToCallMargin = 0.03` with a doc comment stating it is an initial value chosen below the composite read's frame-to-frame repeatability, to be revisited against corpus data.
  - When tied: `recommendedAssetID` is nil everywhere (no ✦ in rail or strip), the rail presentation carries `tooCloseBanner: String?` (`"too close to call — 2·3·5"`, 1-based frame numbers), and stack landing selects the first tied leader.
  - `CullReadsCardPresentation` — the right-panel reads card model: `verdict` (existing Keep/Toss/Mixed read), `rationalePhrases`, `signalRows: [(kind, score)]` for the bars, and `emptyState: String?` = `"No read yet"` whenever `normalizedQualityRead.kindCount < 2` (strictly gating the WHOLE card — deliberately stricter than the old HUD line, which rendered off one signal).

- [ ] **Step 1: Write failing tests.** In `CullReadsCardPresentationTests`: card with 3 synthetic signals renders verdict + rows; exactly 1 signal → `emptyState == "No read yet"`, no verdict, no rows; zero signals → same. In `CullingStackRailPresentationTests` (or a new `CullingStackRecommendationTests` if the ranked logic has no direct test home — check first): two frames with normalized reads 0.80/0.79 → tied (margin 0.03); 0.80/0.76 → not tied; three-way tie returns all three in capture order; tie ⇒ `recommendedAssetID` nil and banner text `"too close to call — 1·2"` format; tie ⇒ landing = first tied leader.
- [ ] **Step 2: Run to verify failures.** Run: `swift test --filter CullReadsCardPresentationTests 2>&1 | tail -5` (and the rail tests). Expected: FAIL.
- [ ] **Step 3: Implement `tiedLeaderIDs`** alongside `rankedCandidates` (same input shape). Core logic:

```swift
/// Leaders whose normalized reads are indistinguishable at the margin.
/// nil when a single frame genuinely leads (or <2 frames have reads).
/// 0.03 on the 0...1 normalized mean is an initial floor chosen below the
/// composite read's frame-to-frame repeatability; revisit with corpus data.
static let tooCloseToCallMargin = 0.03

static func tiedLeaderIDs(/* same inputs as rankedCandidates */) -> [AssetID]? {
    // rank by normalizedQualityRead (NOT raw qualityScore); leaders =
    // every candidate within tooCloseToCallMargin of the top read;
    // return nil unless leaders.count >= 2; order by capture order.
}
```

Then thread it: wherever `rankedCandidates(...).first` currently defines the ✦/`recommendedAssetID`, return nil when `tiedLeaderIDs` is non-nil; give the rail presentation its `tooCloseBanner`; make `recommendedStackLandingAssetID` fall back to the first tied leader when the recommendation is suppressed.

- [ ] **Step 4: Implement `CullReadsCardPresentation`** in its own file, reusing `CullingAssistPresentation`'s existing verdict/rationale computations (call through or relocate the pure helpers — do NOT duplicate the scoring code; if relocating helpers out of `CullingAssistPresentation`, keep its public behavior identical and its tests green).
- [ ] **Step 5: Contenders coverage.** Where Compare's contenders-only mode picks its top-N, ensure N ≥ the tied-leader count so every tied frame appears (locate the contenders limit near `CullingStackRecommendation`'s usages in `CompareView`; smallest change that guarantees inclusion).
- [ ] **Step 6: Run + commit.** Run: `swift test --filter CullReadsCardPresentationTests && swift test --filter CullingStackRailPresentationTests && swift test --filter CullingAssistPresentationTests && swift test --filter CullingFilmstripPresentationTests`. Expected: PASS. Commit: `feat: too-close-to-call tied leaders and strictly-gated reads card`

---

### Task 5: Layout re-plumb — faces+reads panel, stage/HUD cleanup, rail label, `/` toggle

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`LoupeView.body`, `cullHUD`, `closeUpsPanel`, `cullingStackRail`), `Sources/TeststripApp/AppModel.swift` (`.toggleFacesPanel` case + `showsCullFacesPanel` state + dispatch + menu row)
- Test: `Tests/TeststripAppTests/CullHUDPresentationTests.swift`, `Tests/TeststripAppTests/CullingKeyCaptureTests.swift`, `Tests/TeststripAppTests/CullingCommandMenuPresentationTests.swift`

**Interfaces:**
- Consumes: Task 3's `CullStackLabelPresentation`, Task 4's `CullReadsCardPresentation`.
- Produces: right panel (fixed ~300pt) = close-ups on top + reads card below with reserved space (empty states render, panel never vanishes while cull chrome shows); HUD no longer renders the verdict line (one home per fact — the reads card owns it); burst rail header renders `CullStackLabelPresentation.label(for:)`; `AppModel.showsCullFacesPanel: Bool = true` toggled by `/`.

- [ ] **Step 1: Failing tests:** decode `"/"` → `.toggleFacesPanel` (CullingKeyCaptureTests — note bare `/` is unclaimed; Shift+/ remains `.showKeyMap` via the shift-aware event branch, add a test asserting BOTH still decode correctly); menu-row addition; `CullHUDPresentationTests` updated to assert the HUD presentation no longer carries the verdict text (adjust whatever field/fixture asserts it today — that removal IS the spec).
- [ ] **Step 2: Run to verify failures.** Expected: new decode test fails; HUD test fails against current behavior.
- [ ] **Step 3: Implement state + dispatch + menu row** (toast feedback "Faces panel shown/hidden" through the existing feedback mechanism).
- [ ] **Step 4: Re-plumb the view.** In `LoupeView.body`: wrap `closeUpsPanel` and a new `readsCard` view in one right-panel `VStack` (~300pt wide, gated on `showsCullChrome && model.showsCullFacesPanel`); remove the verdict line from `cullHUD`; render the stack label in the rail header via Task 3. AX per existing conventions (label + value text; `.help` naming the key on icon-only controls): the panel container gets `.accessibilityLabel("Reads")`, the empty states are the accessibility VALUE so `ax_drive.sh` can assert "No read yet". Keep `CullLoupeHoverControlsPresentation` untouched.
- [ ] **Step 5: Build + full app test pass** (view plumbing has no presentation test of its own; the compiler and the neighboring suites are the net): `swift build && swift test --filter CullingKeyCaptureTests && swift test --filter CullHUDPresentationTests && swift test --filter CullingCommandMenuPresentationTests && swift test --filter CullLoupeHoverControlsTests`. Expected: PASS.
- [ ] **Step 6: Commit.** `feat: faces+reads right panel, verdict out of HUD, machine-fact rail label, / toggle`

### Task 6: Run strip + status bar (replace the 12-thumb filmstrip)

**Files:**
- Create: `Sources/TeststripApp/CullRunStripPresentation.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`LoupeView.cullingFilmstrip` → `runStrip`; status bar), delete the old `CullingFilmstripPresentation` struct (NOT `CullFilmstripPresentation` — the similarly-named position-text type in its own file survives and gets extended)
- Test: `Tests/TeststripAppTests/CullRunStripPresentationTests.swift` (new), `Tests/TeststripAppTests/CullFilmstripPresentationTests.swift`; delete `Tests/TeststripAppTests/CullingFilmstripPresentationTests.swift` with its struct (coverage replaced, not reduced)

**Interfaces:**
- Consumes: `model.allCullingStacks(for: scopedAssets)` (the live path — NEVER `cullingStackListEntries()`, which is empty outside persisted sessions); Task 3 labels; Task 4 tie suppression; `metadata.confirmedProjection.flag`; `pendingAutopilotProposals`; `gridPreviewURL(for:)` + `CachedPreviewImage` for thumbs.
- Produces: `struct CullRunStripPresentation` — `static func stops(assets:stacks:selectedAssetID:pendingSparkleAssetIDs:visibleLimit:) -> (stops: [Stop], windowStart: Int)` where `Stop` = `{ id, assetIDs, label, isCurrent, isDone, sparkleCount, isStandalone, leadAssetID }`; `isDone` = every member has non-nil `confirmedProjection.flag`. Also the status-bar triple counter: extend `CullFilmstripPresentation`'s position text to `tripleCounterText` = `"N of T · stack S of Σ · frame F of M"` (frame segment omitted on standalones).

- [ ] **Step 1: Failing tests** in `CullRunStripPresentationTests.swift`: mixed scope (2 stacks + 2 standalones) produces 4 stops in capture order with correct labels (Task 3), lead assets, and `isStandalone`; `isCurrent` follows the selected asset's containing stop; `isDone` true only when ALL members carry confirmed flags — **negative (invariant): a member whose flag is tentative-✨ (in `aiUnconfirmedFields`) keeps the stop un-done**; `sparkleCount` counts pending proposals inside the stop; windowing centers the current stop within `visibleLimit`. In `CullFilmstripPresentationTests`: `tripleCounterText` for a mid-stack selection and for a standalone.
- [ ] **Step 2: Run to verify failures.** Run: `swift test --filter CullRunStripPresentationTests 2>&1 | tail -5`. Expected: FAIL (type missing).
- [ ] **Step 3: Implement the presentation** (pure; build stops by walking `stacks` — assets not in any multi-frame stack become standalone stops; derive everything from inputs, no model access).
- [ ] **Step 4: Re-plumb the view.** Replace `cullingFilmstrip(...)` with `runStrip`: multi-frame stops render as pills (label + count + ✨ chip + done ✓ + current highlight), standalones as small `CachedPreviewImage` thumbs; clicking a stop selects its landing frame (existing `selectCullingStack` path). Preserve the old filmstrip's `.task` preview-request side-effect for visible stops' lead assets. Status bar below: `tripleCounterText`, user-origin-only progress bar (from `cullingProgressSummary` — already confirmed-flag based), auto-advance chip (Task 2 state), scope chip (existing `cullScope`), key-hint text. AX: each stop `.accessibilityLabel("Stop <label>")` with `.accessibilityValue` composing "Current"/"Done"/"N frames"/"N suggestions".
- [ ] **Step 5: Delete the superseded `CullingFilmstripPresentation`** struct + its test file (verify no remaining references: `grep -rn CullingFilmstripPresentation Sources/ Tests/`).
- [ ] **Step 6: Run + commit.** Run: `swift build && swift test --filter CullRunStripPresentationTests && swift test --filter CullFilmstripPresentationTests`. Expected: PASS, no references to the deleted type. Commit: `feat: run strip with stack pills and triple-counter status bar`

---

### Task 7: Return render gate + toast disclosure + force-flip test

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (`promoteCurrentFrameAndRejectSiblings`, `promoteDecisionFeedback`)
- Test: `Tests/TeststripAppTests/StackDecisionTests.swift`

**Interfaces:**
- Consumes: `previewURL(for:levels:)` (public; `levels: [.large]` = one file stat); existing decision-feedback toast mechanism.
- Produces: Return is inert (feedback "Rendering full preview…", no metadata writes) when the staged frame's `.large` preview is not yet cached; toast wording becomes `"Kept <filename>[ (was ✕)] · rejected N · ⌘Z undoes"` (picked-sibling protection still disclosed as today where applicable).

- [ ] **Step 1: Failing tests** in `StackDecisionTests.swift` (its fixtures already control the preview-cache directory): (a) `testPromoteForceFlipsRejectedStagedFrameAndDisclosesInToast` — stage a frame already user-rejected, Return: it flips to pick, siblings reject, toast contains `"(was ✕)"`, all in ONE undo group (one `undoMetadataChange()` restores the staged frame's reject AND siblings); (b) `testPromoteInertWhenLargePreviewMissing` — remove/withhold the staged frame's `.large` cached preview, Return: NO flags change, feedback text says rendering, a second Return after the preview exists commits normally; (c) update existing toast-string assertions to the new format.
- [ ] **Step 2: Run to verify failures.** Run: `swift test --filter StackDecisionTests 2>&1 | tail -8`. Expected: new tests FAIL; old toast assertions FAIL against new expected strings (they encode the new spec).
- [ ] **Step 3: Implement.** At the top of `promoteCurrentFrameAndRejectSiblings`, after resolving the staged context: `guard previewURL(for: context.selectedAssetID, levels: [.large]) != nil else { <set feedback "Rendering full preview…"> ; return }`. Rework `promoteDecisionFeedback` to the new format, adding the `(was ✕)` segment when the staged frame's prior confirmed flag was `.reject`.
- [ ] **Step 4: Run + commit.** Run: `swift test --filter StackDecisionTests`. Expected: PASS. Commit: `feat: render-gated stack commit with force-flip disclosure and undo hint`

---

### Task 8: Run tracker (viewed/skipped) + completion summary growth

**Files:**
- Create: `Sources/TeststripApp/CullRunTracker.swift`
- Modify: `Sources/TeststripApp/AppModel.swift` (tracker wiring: record viewed on cull-loupe selection, skipped on the `.nextPhoto` Space arm; reset when the cull source/batch changes — NOT on `S` scope cycling), `Sources/TeststripApp/CullCompletionPresentation.swift`
- Test: `Tests/TeststripAppTests/CullRunTrackerTests.swift` (new), `Tests/TeststripAppTests/CullCompletionTests.swift`

**Interfaces:**
- Consumes: Space dispatch arm (Task's skipped hook), `cullingProgressSummary`/`cullUndecidedCount` (existing confirmed-flag math), `pendingAutopilotProposals`.
- Produces: `struct CullRunTracker` — `viewedAssetIDs: Set<AssetID>`, `skippedAssetIDs: Set<AssetID>`, `mutating func recordViewed(_:)`, `recordSkipped(_:)`, `mutating func reset()`; in-memory only (persistence for exact resume is SP-D). `CullCompletionPresentation` gains `undecided`, `skipped`, `neverViewed`, `sparkleAwaiting` counts and two more actions (`reviewAISuggestions`, `savePicksAsSet`) alongside its existing four; skipped = skipped∖decided; neverViewed = scope∖viewed.

- [ ] **Step 1: Failing tests.** `CullRunTrackerTests`: record/reset semantics; skipped-then-decided asset counts as decided not skipped (set subtraction at presentation time). `CullCompletionTests`: extended presentation math over a synthetic scope — picked/rejected/undecided/skipped/neverViewed/sparkleAwaiting all correct; **negative (invariant): an asset with only a tentative ✨ flag counts in `undecided` AND in `sparkleAwaiting`, never in picked/rejected**; new actions present.
- [ ] **Step 2: Run to verify failures.** Expected: FAIL (missing type/fields).
- [ ] **Step 3: Implement** tracker + wiring (viewed: wherever cull-loupe selection lands — the same choke point `requestVisibleLoupePreview` hangs off is a candidate; pick the single selection path all culling navigation funnels through; skipped: the `.nextPhoto` arm records the asset being left *if* it is still undecided). Reset on cull-source change (the "Cull From" selection change path), not on scope cycle. Extend `CullCompletionPresentation` + its stage rendering with the new counts row and the two actions wired to existing flows (autopilot review surface; `refreshCullingSessionOutputSet`-backed save-picks path — locate the existing action used elsewhere; reuse, don't reimplement).
- [ ] **Step 4: Run + commit.** Run: `swift test --filter CullRunTrackerTests && swift test --filter CullCompletionTests`. Expected: PASS. Commit: `feat: run tracker and full completion summary counts`

---

### Task 9: Scenario cards (authored, NOT RUN)

**Files:**
- Create: `test/scenarios/cull-022-flow-grammar-walk.md`, `test/scenarios/cull-023-return-commit-undo.md`, `test/scenarios/cull-024-honest-states.md`, `test/scenarios/cull-025-run-strip-completion.md`, `test/scenarios/cull-026-tentative-never-commits.md`

**Interfaces:**
- Consumes: everything Tasks 1–8 shipped; `cull-021-stack-rail-nav.md` as the structural template (title line, What this covers, Source with re-verified citations, Pre-state via `vm_scenario_run.sh`, Steps pairing `ax_drive.sh` actions with SQL ground-truth checks, Expected with per-step fail conditions, Cleanup via `reset_isolated_test_data.sh --delete`, Sharp edges, Run status: NOT RUN).
- Produces: five runnable cards covering the SP-A surface.

- [ ] **Step 1: Author the five cards.** Required coverage per card:
  - **cull-022**: H/L/J/K + arrows walk a seeded burst batch AND a no-burst batch with identical grammar; standalone frame-keys walk stops (the fixed dead-key case); landing on ✦ vs frame-1 preference; `A` toggle behavior observable via AX value.
  - **cull-023**: Return on a mid-burst frame — toast text (incl. `(was ✕)` variant), catalog flags via SQL (`SELECT` confirmed flags for all members), single `⌘Z` restores every member (SQL re-check), render-gate note in Sharp edges.
  - **cull-024**: unevaluated frame shows "No read yet" (AX value on the reads panel); too-close-to-call banner + absent ✦ — with the honest-branch instruction pattern from cull-021 (the fixture may or may not produce a tie; assert whichever branch is real, never force one).
  - **cull-025**: run-strip stops (pills/thumbs/done ✓/✨ chips via AX values), triple counter text, completion summary counts cross-checked against SQL (picked/rejected/undecided/✨ awaiting).
  - **cull-026**: the invariant card — seed a tentative ✨ reject; verify progress bar/summary counts it as undecided, move-rejects excludes it (SQL: original untouched, no relocation row), and confirming then rejecting behaves per provenance rules.
  Every citation re-grepped against the working tree (line numbers drift — cull-021's own citations drifted within 3 days; note re-verification in each Source section).
- [ ] **Step 2: Self-check each card** against the falsification rule: every step states what failure looks like; silence is never success.
- [ ] **Step 3: Commit.** `test: scenario cards for the culling-flow shell (cull-022…026)`

---

## Self-review notes (plan author)

- Spec coverage: layout (T5, T6), keys/aliases/dead-keys (T1), auto-advance (T2), labels (T3), honest states (T4), Return gate/toast (T7), progress/completion/tracker (T8), scenario cards (T9). Hover controls: explicitly untouched (spec). Lenses/start card/resume/one-key jumps: SP-D, not here. Whole-burst prefetch: SP-C (T7 ships only the cheap gate).
- Type-name consistency: `CullStackLabelPresentation` (T3 → T5, T6), `CullReadsCardPresentation` (T4 → T5), `CullRunStripPresentation`/`Stop` (T6), `CullRunTracker` (T8), `tooCloseToCallMargin`/`tiedLeaderIDs` (T4), `cullAutoAdvanceEnabled` (T2 → T6 chip), `showsCullFacesPanel` (T5).
- Known risks the reviewer should watch: T2 touches `applyCullingCommandAndAdvance`, whose current advance expectations StackDecisionTests may encode (updating them is in-scope and called out); T5/T6 are view-heavy with compiler+neighbor-suite nets rather than direct view tests; T6 deletes a presentation type — coverage must move, not vanish.

