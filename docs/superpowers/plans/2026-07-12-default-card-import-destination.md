# Default Card-Import Destination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user set a canonical card-import destination once (in ⌘, Settings) and have it apply to every card import, editable per import, never silently re-pinned.

**Architecture:** A persisted `AppModel.defaultCardImportDestination` (UserDefaults, byline pattern) feeds both card-import entry routes: the automation typed-path sheet pre-fills its editable destination field; the real-user panel route skips the destination panel and uses the default, with a per-import "Change…" override on the confirmation sheet. Preferences (⌘,) gains a Card-import section to set/clear the value.

**Tech Stack:** Swift 6, SwiftUI/AppKit, SwiftPM. Persistence via `UserDefaults` (`sessionRestoreDefaults`). Tests: XCTest in `Tests/TeststripAppTests/`.

## Global Constraints

- **Non-destructive / confirm-before-write:** the setting is pre-fill only — setting or changing it writes nothing to any photo or catalog. Assert the negative where relevant.
- **Editable per import, no sticky override:** overriding the destination for one import (typed field or Change…) never mutates the saved default.
- **Filing scheme unchanged:** `destination/YYYY/YYYY-MM-DD/`. No `/MM/` level. No change to dedup proposal, second-copy flow, or folder (add-in-place) import.
- **Copy register:** actions Title Case; explanatory copy sentence case; icon-only controls carry `.help`. One primary accent verb per surface (the confirmation sheet's primary stays Import; Change… is a plain button).
- **Persistence idiom:** mirror `AppModel.defaultCreator`/`defaultCopyright` exactly — property with `didSet` writing to `sessionRestoreDefaults`, load line beside the byline loads. Key string: `"AppModel.defaultCardImportDestination"`.
- Every commit ends with the trailer: `Claude-Session: https://claude.ai/code/session_013nWAUJofcxs69ZyPgXi6uH`.

---

### Task 1: Persisted `defaultCardImportDestination` on AppModel

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift` (byline block ~2312-2326; load block ~4123-4124)
- Test: `Tests/TeststripAppTests/AppModelSessionRestoreTests.swift`

**Interfaces:**
- Produces: `public var defaultCardImportDestination: String` (folder path, `""` = unset), persisted under `static let defaultCardImportDestinationDefaultsKey = "AppModel.defaultCardImportDestination"`.

- [ ] **Step 1: Failing test** — in `AppModelSessionRestoreTests.swift`, mirror the existing `defaultCreator` persistence test: set `model.defaultCardImportDestination = "/Volumes/Photos"` against an injected `UserDefaults`, assert the defaults key holds it; construct a fresh model from the same defaults and assert it loads `/Volumes/Photos`; assert the unset default loads as `""`.
- [ ] **Step 2: Run it, verify it fails** (property/key undefined).
- [ ] **Step 3: Implement** — add the property with a `didSet` persisting to `sessionRestoreDefaults` under the new key (copy the `defaultCreator` shape verbatim), the `static let` key, and a load line beside `model.defaultCreator = …` in the model factory: `model.defaultCardImportDestination = sessionRestoreDefaults.string(forKey: defaultCardImportDestinationDefaultsKey) ?? ""`.
- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit.**

---

### Task 2: Apply the default at both card-import entry routes

**Files:**
- Modify: `Sources/TeststripApp/ImportFolderPathDraft.swift` (`ImportCardPathDraft`)
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`showImportCardPathSheet` ~2695; `showImportCardPanel` ~2716; `LibraryGridChromePolicy` ~7764)
- Test: `Tests/TeststripAppTests/LibraryGridChromeTests.swift`

**Interfaces:**
- Consumes: `AppModel.defaultCardImportDestination` (Task 1).
- Produces:
  - `ImportCardPathDraft.applyDefaultDestination(_ path: String)` — mutating; sets `destinationPath = path` only when `path` is non-empty (never clobbers with "").
  - `enum CardDestinationResolution { case useSaved(URL); case promptPanel }` and `LibraryGridChromePolicy.cardDestinationResolution(savedDefault: String) -> CardDestinationResolution` — non-empty ⇒ `.useSaved(URL(fileURLWithPath: savedDefault, isDirectory: true))`, empty ⇒ `.promptPanel`.

- [ ] **Step 1: Failing tests** — (a) `applyDefaultDestination("/Volumes/Photos")` sets `destinationPath`; `applyDefaultDestination("")` leaves an existing value untouched. (b) `cardDestinationResolution(savedDefault: "/Volumes/Photos")` == `.useSaved(...)` with that path; `cardDestinationResolution(savedDefault: "")` == `.promptPanel`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — add `applyDefaultDestination` to `ImportCardPathDraft`; add the enum + policy function. Wire: in `showImportCardPathSheet()`, after `importCardPathDraft.reset()`, call `importCardPathDraft.applyDefaultDestination(model.defaultCardImportDestination)`. In `showImportCardPanel()`, after choosing the source, switch on `LibraryGridChromePolicy.cardDestinationResolution(savedDefault: model.defaultCardImportDestination)`: `.useSaved(let dest)` → `presentImportConfirmation(.card(source: source, destinationRoot: dest))`; `.promptPanel` → existing `chooseCardDestinationFolder()` path (unchanged).
- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit.**

---

### Task 3: Per-import "Change…" destination override on the confirmation sheet

**Files:**
- Modify: `Sources/TeststripApp/ImportConfirmationDraft.swift`
- Modify: `Sources/TeststripApp/LibraryGridView.swift` (`importConfirmationSheet` ~1862, Destination row ~1876)
- Test: `Tests/TeststripAppTests/` (the ImportConfirmationDraft test file; create if absent)

**Interfaces:**
- Consumes: `ImportConfirmationDraft` (card mode has `destinationRoot`, `destinationName`, `destinationUnavailableReason`).
- Produces: `ImportConfirmationDraft.setDestinationRoot(_ url: URL)` — mutating; updates the stored destination root and recomputes any derived destination name/availability reason. No-op semantics unchanged for folder (add-in-place) drafts (guard to card mode).

- [ ] **Step 1: Failing test** — build a card `ImportConfirmationDraft`, call `setDestinationRoot(URL(fileURLWithPath: "/Volumes/Other"))`, assert `destinationName`/root reflect the new folder and the availability reason recomputes. Assert calling it does not mutate any saved default (there is none on the draft — this documents the boundary).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — add `setDestinationRoot`. In `importConfirmationSheet`, when `draft.mode == .card`, render the Destination `LabeledContent` with a trailing plain `Button("Change…")` carrying `.help("Choose a different destination for this import")` that opens `FolderSelectionPanel.chooseCardDestinationFolder()` (seeded at the current destination) and, on a pick, applies `importConfirmationDraft?.setDestinationRoot(url)`. Do not alter `model.defaultCardImportDestination`.
- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit.**

---

### Task 4: Preferences (⌘,) Card-import section

**Files:**
- Modify: `Sources/TeststripApp/PreferencesView.swift`
- Test: `Tests/TeststripAppTests/` (add a small presentation test; a pure helper if the view logic needs one)

**Interfaces:**
- Consumes: `AppModel.defaultCardImportDestination`, `FolderSelectionPanel.chooseCardDestinationFolder()`.

- [ ] **Step 1: Failing test** — a presentation helper returns the display string for the field: non-empty path shows the path (or its abbreviated form), empty shows "None"; and a "clear" transform yields "". Assert the footer copy constant equals the exact sentence-case string.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — add a second `Section` (header "Card import") below the byline: a row showing the current destination (path or "None") with a **Choose…** button (opens `chooseCardDestinationFolder()`, sets `model.defaultCardImportDestination = url.path`) and, when non-empty, a **Clear** button (sets `""`); footer (`.font(.caption).foregroundStyle(.secondary)`): "Pre-fills the destination for new card imports. Originals are copied — never moved — into dated folders (YYYY/YYYY-MM-DD)."
- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit.**

---

### Task 5: E2E scenario card + ledger, run live in the VM

**Files:**
- Create: `test/scenarios/app-018-default-card-destination.md`
- Modify: `test/scenarios/LEDGER.md` (add a `Spec'd` row; orchestrator promotes after the run)

- [ ] **Step 1: Author the card** using the e2e-scenario-testing format. Pre-state: VM launch with a seed (smoke) and `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path` so the typed-path sheet is drivable. Steps: open ⌘, Settings; set a card-import destination (type/paste a VM path); assert `defaults read com.teststrip.app AppModel.defaultCardImportDestination` shows it; ⌘Q; relaunch against the same run dir (not a fresh launch — see app-006 sharp edge); open the card-import path sheet; assert the Destination field is pre-filled with the saved value; assert pre-fill only — `SELECT count(*) FROM assets WHERE …` unaffected, no catalog write from merely setting the default. Sharp edges: the panel-route skip/Change… path is not AX-drivable through native open panels; it is covered by Tasks 2-3 unit/presentation tests.
- [ ] **Step 2: Add the ledger row** (`Spec'd`).
- [ ] **Step 3 (orchestrator):** run the card live in the Tart VM per the harness; capture per-assertion verdicts; on pass, promote the ledger row to Verified with evidence.

## Self-Review Notes

- Every spec section maps to a task: persistence → T1; both-route application → T2; per-import override → T3; Preferences → T4; e2e → T5.
- Type consistency: `applyDefaultDestination`, `cardDestinationResolution`/`CardDestinationResolution`, `setDestinationRoot` are the exact names used across tasks.
- No placeholders; exact key strings and footer copy are inline.
