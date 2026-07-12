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

### 3. Pre-fill

When the card-import sheet's `ImportCardPathDraft` is created, initialize
`destinationPath` from `defaultCardImportDestination` when it is non-empty.
`ImportCardPathDraft` is `@State`-initialized in `LibraryGridView`; the pre-fill
must apply when the card-import flow is *opened* (so a default set after launch
is honored), and must not clobber a destination the user has already typed in an
open sheet. The field stays fully editable; editing it does not write back to
the default.

A stale default (folder unplugged/missing) needs no special handling: the
existing `CardImportDestinationPreflight.blockingReason` already blocks review
with "Destination folder is missing," so a stale default fails safe at review
rather than copying anywhere wrong.

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
- **Presentation (pre-fill):** an `ImportCardPathDraft` opened with a non-empty
  default pre-fills `destinationPath`; an empty default leaves it blank; a
  user-entered destination is not overwritten when the flow re-evaluates.
- **Presentation (Preferences):** the Card-import section binds to the model
  value and carries the footer copy; Choose/Clear update the bound value.
- **E2E scenario card (run live in the Tart VM):** new
  `test/scenarios/app-018-default-card-destination.md` — in ⌘, Settings set a
  card-import destination; assert `defaults read com.teststrip.app
  AppModel.defaultCardImportDestination` shows it; ⌘Q and relaunch against the
  same run dir; open the card-import flow and assert the destination field is
  pre-filled with the saved value; assert the value is pre-fill only (no catalog
  write). Add a ledger row. The card is the spec; it must be executed, not just
  authored.

## Out of scope

Everything the card-import path already does. This spec adds one persisted
setting and its pre-fill, nothing else.
