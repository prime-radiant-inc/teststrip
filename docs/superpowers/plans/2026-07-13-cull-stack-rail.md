# Current-Stack Cull Rail — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reorganize the Cull loupe's current-stack rail from a horizontal text-chip strip on top into a vertical thumbnail rail on the left, enrich its cells, and remap the keyboard so ↑/↓ move within the current stack and ←/→ move across stacks.

**Architecture:** Reuse the existing `CullingStackRailPresentation` (extend its `Item` with a decision field); rewrite the `cullingStackRail` view as a vertical thumbnail rail and move it in the stage layout from below the loupe into the middle `HStack` as the leftmost element; remap `CullingShortcut` and add within-stack candidate navigation to `AppModel`. Presentation-layer only — no worker/queue/catalog changes.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI/AppKit. All source in `Sources/TeststripApp/`; tests in `Tests/TeststripAppTests/`.

## Global Constraints

- **Confirm-before-write:** the rail displays provisional evaluation reads (sharpness/eyes/duplicate) and pick/reject decision state; displaying them writes nothing. Assert nothing new is written to catalog/metadata by rendering the rail.
- **Non-destructive:** unchanged — no original bytes touched.
- **TDD** for the unit-testable tasks (presentation, nav, shortcuts); the two SwiftUI view tasks are verified by the Phase-D scenario card, not a unit test.
- **macOS 14+ / Swift 6.** Build with `make build`, unit-test with `make test`. Interactive verification runs in the Tart VM via `script/vm_scenario_run.sh`.
- **Keyboard mapping (verbatim target):** ↑/↓ = previous/next candidate within the current stack (stop at ends); ←/→ = previous/next stack (land on the new stack's AI-recommended frame); Space = linear advance (next candidate, then next stack's recommended frame); Return = promote-and-reject-siblings (unchanged); ⌥←/⌥→ = removed.

---

### Task 1: Add a `decision` field to `CullingStackRailPresentation.Item`

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`CullingStackRailPresentation` — struct at ~line 5930, `Item` at ~5931, init item-build at ~6012)
- Test: `Tests/TeststripAppTests/CullingStackRailPresentationTests.swift` (create, or extend an existing rail-presentation test file if one exists — search first)

**Interfaces:**
- Consumes: the existing filmstrip `DecisionState` enum (`{ undecided, picked, rejected }`, `init(flag: PickFlag?)`, defined on the filmstrip presentation struct near `LibraryGridView.swift:5847`) and `Asset.metadata.flag`.
- Produces: `CullingStackRailPresentation.Item.decision: <FilmstripPresentation>.DecisionState`, set per item from that item's asset flag.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import TeststripApp
import TeststripCore

final class CullingStackRailPresentationTests: XCTestCase {
    func testItemsCarryPickRejectDecisionFromAssetFlag() {
        let picked = TestAssets.make(id: "a", flag: .pick)
        let rejected = TestAssets.make(id: "b", flag: .reject)
        let undecided = TestAssets.make(id: "c", flag: nil)
        let presentation = CullingStackRailPresentation(
            assets: [picked, rejected, undecided],
            selectedAssetID: AssetID(rawValue: "a"),
            explicitStackScope: CullingStackScope(
                assetIDs: [picked.id, rejected.id, undecided.id],
                stackIndex: 1, stackCount: 1, rationaleText: nil
            )
        )
        let byID = Dictionary(uniqueKeysWithValues: presentation.items.map { ($0.assetID, $0.decision) })
        XCTAssertEqual(byID[picked.id], .picked)
        XCTAssertEqual(byID[rejected.id], .rejected)
        XCTAssertEqual(byID[undecided.id], .undecided)
    }
}
```

> Implementer: search `Tests/TeststripAppTests` for an existing `Asset` test factory (e.g. a `make(id:flag:)` helper used by filmstrip/stack tests) and reuse it instead of `TestAssets.make`; match the real `Asset`/`PickFlag` API. If `explicitStackScope` isn't the cleanest seam, pass the assets and `selectedAssetID` and let the builder derive the stack — mirror how existing `CullingStackRailPresentation` tests construct it.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CullingStackRailPresentationTests`
Expected: FAIL — `Item` has no `decision` member.

- [ ] **Step 3: Add the field and populate it**

In `Item`, add `var decision: <FilmstripPresentation>.DecisionState`. In the init's `items = stackScope.assetIDs.enumerated().map { ... }`, look up each asset by id and set `decision: DecisionState(flag: asset.metadata.flag)` (build an `[AssetID: Asset]` index from `assets` once before the map). Every `Item(...)` construction in the file must add the new argument — update the empty-state paths too (they return `items = []`, so no per-item change there, but confirm the type compiles).

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter CullingStackRailPresentationTests` then `make test`
Expected: PASS; no regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/CullingStackRailPresentationTests.swift
git commit -m "feat: carry pick/reject decision on stack-rail items"
```

---

### Task 2: Rewrite `cullingStackRail` as a vertical thumbnail rail

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`cullingStackRail(presentation:)` at ~line 4395, and the per-cell body)

**Interfaces:**
- Consumes: `CullingStackRailPresentation` (with `Item.decision` from Task 1), the same preview/thumbnail source `filmstripTile` uses (find how `filmstripTile` at ~`LibraryGridView.swift:4521` renders its image and reuse it), `model.select(_:)`.
- Produces: a vertical rail view. No new public interface.

> **UI task — verified by the Phase-D scenario card, not a unit test.** Keep the presentation reuse; only the view body changes.

- [ ] **Step 1: Replace the horizontal body with a vertical rail**

Rewrite `cullingStackRail` to a fixed-width vertical container:
- **Header**: `presentation.titleText` ("Stack N of M") + `presentation.positionText` ("Frame X of K") + optional `rationaleText`, styled like the current header labels.
- **Body**: a vertically scrolling stack (`ScrollView { LazyVStack(spacing:) { ForEach(presentation.items, id: \.assetID.rawValue) { cell } } }`) of **thumbnail cells** (extract `private func cullStackRailCell(_ item:) -> some View`). Each cell:
  - the preview thumbnail (reuse `filmstripTile`'s image source/caching),
  - a selection highlight when `item.isSelected`,
  - the recommended marker (`✦`/star) when `item.isRecommended`,
  - a decision overlay driven by `item.decision` (✓ picked / ✕ rejected / dim when rejected — reuse the filmstrip's `filmstripDecisionOverlay`/`filmstripDecisionBar` styling at ~`LibraryGridView.swift:4574,4603` so the rail and filmstrip read the same),
  - the AI-read badges: render each of `item.flawBadges` as its own small badge (sharpness / eyes / duplicate) instead of the single red dot; reuse the existing badge label/help (`stackChipFlawHelpText` at ~4489).
  - tap action: `model.select(item.assetID)`.
- **Footer**: the primary keep action (`presentation.actions.first`, calling `keepSelectedStackFrame()`) and the secondary-actions overflow `Menu` (as today), moved below the thumbnails.
- Preserve the `presentation.isVisible` guard (empty for single-frame stacks) and the accessibility values (`stackChipAccessibilityValue` at ~4494).

- [ ] **Step 2: Build**

Run: `make build`
Expected: Build complete. Fix any references to the removed horizontal-chip layout.

- [ ] **Step 3: Run the unit suite** (nothing should regress; view isn't unit-tested)

Run: `make test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: render the cull stack rail as vertical thumbnail cells"
```

---

### Task 3: Move the rail into the stage layout as the left column

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (the cull stage `body`, ~lines 3842–3872)

**Interfaces:**
- Consumes: `cullingStackRail(presentation:)` (Task 2), the existing stage `HStack`/`VStack` composition.

> **UI task — verified by the Phase-D scenario card.**

- [ ] **Step 1: Relocate the rail**

Today the stage renders, below the loupe column: `cullingStackRail(...)` then `cullingFilmstrip(...)`. Move `cullingStackRail(presentation:)` OUT of that bottom section and INTO the middle `HStack` (~line 3842) as its **leftmost** element, before the loupe `VStack`, gated by `presentation.showsCullChrome`:

```swift
HStack(spacing: 0) {
    if presentation.showsCullChrome {
        cullingStackRail(presentation: stackPresentation)
    }
    VStack(spacing: 0) {
        // ... existing loupe / completion / closeUps content unchanged ...
    }
}
```

Leave only `cullingFilmstrip(recommendedAssetID:)` in the bottom `showsCullChrome` block (delete the `cullingStackRail(...)` call there). The result is left-to-right `[rail] [loupe] [closeUps]`, filmstrip along the bottom.

- [ ] **Step 2: Build + test**

Run: `make build` then `make test`
Expected: Build complete; suite PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/TeststripApp/LibraryGridView.swift
git commit -m "feat: pin the cull stack rail to the left of the loupe stage"
```

---

### Task 4: Within-stack candidate navigation on `AppModel`

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (near `selectNextStackForCulling` / `selectPreviousStackForCulling` at ~6262)
- Test: `Tests/TeststripAppTests/CullStackNavigationTests.swift` (create, or extend the existing culling-nav test file — search first)

**Interfaces:**
- Consumes: the current-stack membership lookup already used by `CullingStackRailPresentation` / the stack-nav methods (the stack containing `selectedAssetID`), `model.select(_:)`.
- Produces:
  - `AppModel.selectNextCandidateInStack()` / `selectPreviousCandidateInStack()` — move `selectedAssetID` to the next/previous asset **within the current stack's ordered assetIDs**, stopping at the ends (no-op past the boundary).
  - Confirm `selectNextStackForCulling()` / `selectPreviousStackForCulling()` land on the new stack's **recommended** frame; if they currently land on the first frame, adjust to select the recommendation (reuse `CullingStackRecommendation.rankedCandidates(...).first`).

- [ ] **Step 1: Write the failing test**

```swift
func testNextCandidateMovesWithinStackAndStopsAtEnd() throws {
    let model = try CullNavFixture.stackOfThree(selected: "a") // a,b,c in one stack, a selected
    model.selectNextCandidateInStack()
    XCTAssertEqual(model.selectedAssetID?.rawValue, "b")
    model.selectNextCandidateInStack()
    XCTAssertEqual(model.selectedAssetID?.rawValue, "c")
    model.selectNextCandidateInStack()               // at end — stays put
    XCTAssertEqual(model.selectedAssetID?.rawValue, "c")
}
```

> Implementer: build the fixture the way existing culling-nav tests seed a model with a known stack (search `Tests/TeststripAppTests` for how `selectNextStackForCulling` is tested and mirror it). If landing-on-recommended needs its own test, add one asserting `selectNextStackForCulling()` selects the ranked-first frame of the next stack.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter CullStackNavigationTests`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement the within-stack nav**

Add the two methods: resolve the current stack's ordered `assetIDs` (same builder/lookup the rail uses), find `selectedAssetID`'s index, and `select` the neighbor if in range. Guard the boundaries (no wrap). Verify/adjust the stack-nav landing frame to the recommendation.

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CullStackNavigationTests` then `make test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/TeststripApp/AppModel.swift Tests/TeststripAppTests/CullStackNavigationTests.swift
git commit -m "feat: within-stack candidate navigation for culling"
```

---

### Task 5: Remap the culling keyboard axes

**Files:**
- Modify: `Sources/TeststripApp/CullingKeyCaptureView.swift` (`CullingShortcut` enum + `init(event:)` at ~line 126; the ⌥ branch at ~130, the main `switch` at ~165)
- Modify: `Sources/TeststripApp/AppModel.swift` (the shortcut-action dispatch at ~5846–5869) to route the new/rewired actions
- Modify: wherever the key-map overlay text is defined (search `showKeyMap` / the overlay text) so the advertised bindings match
- Test: `Tests/TeststripAppTests/` — the existing `CullingShortcut` mapping tests (search `testCullingShortcut`)

**Interfaces:**
- Consumes: `AppModel.selectNextCandidateInStack()` / `selectPreviousCandidateInStack()` (Task 4), existing `selectNextStackForCulling` / `selectPreviousStackForCulling`, existing linear `nextPhoto` / `previousPhoto` handlers.
- Produces: new `CullingShortcut` cases `.nextCandidateInStack` / `.previousCandidateInStack`; the arrow keys remapped.

- [ ] **Step 1: Update the failing shortcut-mapping tests**

Change the existing mapping tests (and add cases) to assert the new axes:

```swift
XCTAssertEqual(CullingShortcut(event: keyEvent(.upArrow)), .previousCandidateInStack)
XCTAssertEqual(CullingShortcut(event: keyEvent(.downArrow)), .nextCandidateInStack)
XCTAssertEqual(CullingShortcut(event: keyEvent(.leftArrow)), .previousStack)
XCTAssertEqual(CullingShortcut(event: keyEvent(.rightArrow)), .nextStack)
XCTAssertEqual(CullingShortcut(event: keyEvent(.space)), .nextPhoto)          // linear advance
XCTAssertEqual(CullingShortcut(event: keyEvent(.returnKey)), .promoteAndRejectSiblings)
XCTAssertNil(CullingShortcut(event: keyEvent(.leftArrow, modifiers: [.option]))) // ⌥← retired
```

> Reuse the existing `keyEvent(...)` helper the current shortcut tests use; match its signature.

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CullingShortcut`
Expected: FAIL — old mapping still returns `.previousPhoto`/`.previousStack` etc.

- [ ] **Step 3: Remap**

In `CullingShortcut`: add cases `.nextCandidateInStack` / `.previousCandidateInStack`. In `init(event:)`: delete the `⌥←/⌥→` option branch; in the main `switch`, set leftArrow→`.previousStack`, rightArrow→`.nextStack`, upArrow→`.previousCandidateInStack`, downArrow→`.nextCandidateInStack`, space→`.nextPhoto` (unchanged linear advance), returnKey/keypadEnter→`.promoteAndRejectSiblings` (unchanged). In `AppModel`'s dispatch, route `.nextCandidateInStack`/`.previousCandidateInStack` to the Task-4 methods; `.previousStack`/`.nextStack`/`.nextPhoto` keep their existing handlers.

- [ ] **Step 4: Update the key-map overlay** so the displayed bindings read: "↑/↓ frame in stack · ←/→ stack · Space next · Return keep+cut". (Find the overlay text near `showKeyMap`.)

- [ ] **Step 5: Run tests**

Run: `swift test --filter CullingShortcut` then `make test`
Expected: PASS. Update any other test that asserted the old arrow mapping.

- [ ] **Step 6: Commit**

```bash
git add Sources/TeststripApp/CullingKeyCaptureView.swift Sources/TeststripApp/AppModel.swift Tests/
git commit -m "feat: remap cull keys — up/down within stack, left/right across stacks"
```

---

### Task 6: E2E scenario card (VM)

**Files:**
- Create: `test/scenarios/cull-<nnn>-stack-rail.md` (follow `test/scenarios/README.md` conventions; pick the next free cull-NNN number)

**Interfaces:**
- Consumes: `script/vm_scenario_run.sh` (setup/sync/launch/ax/sql), `script/ax_drive.sh`.

- [ ] **Step 1: Write the scenario card.** Launch a seeded catalog with a multi-frame stack (a burst — `faces` or a folder import that produces near-duplicates); enter the Cull loupe; assert the **left vertical rail** shows the current stack's frames as thumbnails with a recommended marker and AI-read badges (`ax_drive.sh find`); press **↓** and assert selection moves to the next frame **within the stack** (SQL/AX: `selectedAssetID` advances within the stack's ids, not to another stack); press **→** and assert it moves to the **next stack** landing on its recommended frame; **click** a rail cell and assert it loupe's that frame; press **Return** and assert the rail shows ✓ on the pick and ✕ on siblings, and the catalog reflects the promote/reject (`work`/asset flags via `sql`); re-assert **confirm-before-write** — no metadata/sidecar/people writes occurred from merely rendering the rail (only the explicit Return gesture wrote flags).
- [ ] **Step 2: Run it in the VM** per `test/scenarios/README.md` (keep the app warm; drive promptly). Iterate the card against reality until it passes.
- [ ] **Step 3: Commit the card** (+ a ledger row per the scenario convention).

```bash
git add test/scenarios/
git commit -m "test: e2e scenario — vertical current-stack cull rail + remapped nav"
```

---

## Self-Review

**Spec coverage:**
- Vertical left rail with thumbnails → Tasks 2 (view) + 3 (placement). ✅
- Rich cells (decision + recommended + AI badges) → Task 1 (decision field) + Task 2 (render badges/overlay/marker). ✅
- Keyboard: ↑/↓ within stack, ←/→ across stacks, Space linear, Return promote, ⌥ retired → Tasks 4 (nav) + 5 (remap). ✅
- Reuse `CullingStackRailPresentation` → Task 1 extends it; Tasks 2–3 reuse it. ✅
- Confirm-before-write display-only → asserted in Task 6. ✅
- Testing: unit (Tasks 1, 4, 5), e2e (Task 6); view tasks (2, 3) covered by the scenario. ✅
- Open items from the spec: header/footer placement decided in Task 2 (header = title/position/rationale; footer = keep + menu); decision-state source resolved in Task 1 (reuse filmstrip `DecisionState`). ✅

**Placeholder scan:** No "TBD/handle edge cases". The `<FilmstripPresentation>` and test-factory references are directed to concrete existing code the implementer must locate (named with line numbers), not blanks.

**Type consistency:** `Item.decision: DecisionState` introduced in Task 1 and rendered in Task 2. `selectNextCandidateInStack`/`selectPreviousCandidateInStack` defined in Task 4, consumed by the `.nextCandidateInStack`/`.previousCandidateInStack` shortcuts in Task 5. `nextStack`/`previousStack`/`nextPhoto` names match the existing enum.
