# Default Card-Import Destination

**Date:** 2026-07-12
**Status:** Approved direction (Jesse: "do it"; build with subagent-driven
development; ship a live e2e scenario card, not just unit tests)

## Context

Card import already does the substantive work this feature is usually asked to
add, so this spec is deliberately narrow. Today the card-import path
(`IngestPlan.mode == .copyToDestination`) already:

- copies originals into a destination root, filing them by capture date into
  `destinationRoot/YYYY/YYYY-MM-DD/` (the `capturedDate` destination policy;
  date from EXIF `DateTimeOriginal` → TIFF → file mtime, with timezone care);
- detects duplicates **at proposal time** — the review sheet shows
  "N new · M already in catalog" before any copy, computed by content hash, with
  a dedupe toggle;
- supports an optional second-copy/backup destination;
- is fully wired through the worker with progress and within-batch dedup.

Two of the three things the original ask named — the canonical dated directory
structure and proposal-time duplicate detection — already exist and are being
kept as-is. Jesse confirmed the existing two-level `YYYY/YYYY-MM-DD` scheme is
fine (no month level added).

The one genuine gap: **the destination is retyped every import.** The macOS
open panel remembers the last-used *parent* directory
(`FolderSelectionPanel.cardDestinationParentKey`), but the destination field in
the card-import sheet (`ImportCardPathDraft.destinationPath`) starts blank every
time. There is no persisted, user-visible "this is my photo library root"
default.

## Goal

Let the user set a canonical card-import destination once and have it pre-fill
every card import, editable per import, never silently re-pinned.

## Decisions (from brainstorming)

- **Filing scheme:** unchanged (`YYYY/YYYY-MM-DD`).
- **Dedup proposal:** unchanged (already exists).
- **Behavior:** a persisted default set in ⌘, Settings, pre-filled into the
  card-import sheet, **editable per import**. Overriding it for one import does
  **not** change the saved default (no sticky override).
- **Scope of the setting:** the **primary destination only.** The second-copy
  (backup) folder and the dated-folders toggle keep their current per-import
  behavior (backup blank, toggle on by default).

## Design

### 1. Persisted value

Add `AppModel.defaultCardImportDestination` (a folder-path `String`, `""` when
unset), persisted to `UserDefaults` under key
`AppModel.defaultCardImportDestination`, following the existing
`defaultCreator` / `defaultCopyright` byline pattern exactly: a `didSet` that
writes to `sessionRestoreDefaults`, plus a load line alongside the byline load
in the model factory. Empty string means unset.

### 2. Preferences UI

`PreferencesView` (⌘,) gains a second `Section` below the byline, header
"Card import":

- a path display bound to `model.defaultCardImportDestination` plus a
  **Choose…** button that opens `FolderSelectionPanel.chooseCardDestinationFolder`
  and stores the chosen folder's path (with a **Clear** affordance to return to
  unset);
- a one-line, sentence-case footer: "Pre-fills the destination for new card
  imports. Originals are copied — never moved — into dated folders
  (YYYY/YYYY-MM-DD)."

The value is pre-fill only; setting it writes nothing to any photo or catalog.

### 3. Applying the default across both entry routes

Card import has two entry routes (`LibraryGridChromePolicy.primaryCardImportRoute`):

- **`.userGrantedPanel`** — the real-user route on macOS. Opens a source panel,
  then a **destination panel**, then a read-only confirmation sheet. This is
  where Jesse's "retype the destination every import" friction lives.
- **`.typedPathSheet`** — automation only (`TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`,
  set by the VM/scenario launcher). Has an editable destination text field.

The default must remove the friction in **both**:

- **Panel route:** when `defaultCardImportDestination` is set, the source panel
  still opens (the card changes every import), but the **destination panel is
  skipped** and the saved default is used — the "standard setting, don't ask me"
  behavior. Per-import override: the confirmation sheet's Destination row (card
  mode only) gains a small trailing **Change…** button that opens the
  destination panel (seeded at the current destination) and updates the draft's
  `destinationRoot`, re-running the existing destination availability check. When
  no default is set, the route is unchanged (destination panel as today).
- **Typed-path sheet route:** `ImportCardPathDraft.destinationPath` is pre-filled
  from the default when the sheet is opened (after its `reset()`), non-empty
  only. The field stays fully editable; editing it does not write back to the
  default.

Editing the destination for one import (Change… or the typed field) never
mutates the saved default — the "editable per import, no sticky override" choice.

A stale default (folder unplugged/missing) needs no special handling: the
existing `CardImportDestinationPreflight.blockingReason` and the confirmation
sheet's `destinationUnavailableReason` already surface "Destination folder is
missing" and block the import, so a stale default fails safe rather than copying
anywhere wrong. The Change… button lets the user point at a reachable folder.

## Non-goals

- No change to the filing scheme, the dedup proposal, the second-copy flow, or
  folder (add-in-place) import.
- No persisted default for the second-copy destination or the dated-folders
  toggle.
- No sticky "last used becomes the default" behavior.

## Testing

- **Unit (persistence):** `defaultCardImportDestination` round-trips through an
  injected `UserDefaults` and loads on model construction — mirror the existing
  byline persistence tests.
- **Presentation (typed-sheet pre-fill):** an `ImportCardPathDraft` opened with a
  non-empty default pre-fills `destinationPath`; an empty default leaves it
  blank; a user-entered destination is not overwritten when the flow
  re-evaluates.
- **Unit (panel-route selection):** a helper decides "skip destination panel and
  use the default" vs. "open the destination panel" from the saved default —
  test both branches (default set → use it; default unset → open panel).
- **Presentation (confirmation Change… affordance):** the confirmation sheet
  exposes a destination-change control in card mode only, and applying a new
  folder updates the draft's `destinationRoot` (and its availability reason)
  without touching the saved default.
- **Presentation (Preferences):** the Card-import section binds to the model
  value and carries the footer copy; Choose/Clear update the bound value.
- **E2E scenario card (run live in the Tart VM):** new
  `test/scenarios/app-018-default-card-destination.md` — in ⌘, Settings set a
  card-import destination; assert `defaults read com.teststrip.app
  AppModel.defaultCardImportDestination` shows it; ⌘Q and relaunch against the
  same run dir; drive the automation (`typed-path`) card-import route and assert
  the destination field is pre-filled with the saved value; assert the value is
  pre-fill only (no catalog write). Add a ledger row. The card is the spec; it
  must be executed, not just authored. (The panel-route skip/Change… behavior is
  not AX-drivable through native open panels — it is covered by the unit and
  presentation tests above and noted in the card's Sharp edges.)

## Out of scope

Everything the card-import path already does. This spec adds one persisted
setting and its pre-fill, nothing else.
