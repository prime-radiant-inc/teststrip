# People as a library view + face-group review redesign

_Date: 2026-07-14 · Sub-project 2 of the People/agentic-tags redesign_
_Builds on `2026-07-14-machine-label-provenance.md` (the foundation)._

## Problem

Two coupled shortcomings in the People surface:

**A. People is a top-level mode it doesn't earn.** Today `People` is both a
`Workspace` case (⌘3, peer of Cull and Library) and a `LibraryViewMode`. It is
not a distinct workspace — it browses the same catalog as Library, just scoped
to faces. Making it a top-level workspace inflates the three-way workspace
switcher and separates People from the Grid/Loupe/Timeline/Map views it belongs
beside. It should be a **view** of the Library, selected from the same toggle.

**B. The face-group review cards ask you to name people blind.** The
"Is this <name>?" / "Who is this?" suggestion cards show one tiny circular crop
of a single representative face and a one-tap Confirm. You confirm a whole group
(often many photos) without ever seeing the other faces in it, and there is no
way to drop a wrong face from the group before confirming. The foundation spec
(`machine-label-provenance`) explicitly deferred the "prominent, review-first
people surface" to here.

## Goals

- **A.** People is a `.library` view, a peer of Grid | Loupe | Timeline | Map in
  the Library sub-view toggle. The top-level People workspace (⌘3) is removed;
  Library is ⌘2, Cull is ⌘1. People keeps its non-browse chrome: no search
  field, filter tokens, import, footer, cull/export/more toolbar actions — only
  the sub-view toggle (to leave), the inspector, and Activity.
- **B.** Tapping a face-group suggestion opens a **review surface** that shows
  every face in the group as a large tile zoomed to the face; hovering or
  clicking a tile reveals the whole photo; a per-tile control removes that face
  from the group (a sticky reject for a matched person, a dismiss for a new
  cluster); a bottom bar confirms/names the person over the faces that remain.
  Review-first: look, prune, then name.

## Non-goals

- The ✨ tag/inspector chrome for non-identity labels (sub-project 3).
- Global filter persistence across views/modes (sub-project 4, which also edits
  `AppModel.swift`/`LibraryGridView.swift` — coordinate merges).
- Changing how faces are detected, embedded, matched, or promoted
  (`promoteFaceMatches`, `FaceSuggestionBuilder`, confirmed-only centroids) —
  all reused as-is.
- The per-photo People **inspector** section (`PhotoFacesSectionView`) — it
  already does per-face confirm/remove and is untouched here.

## Architecture

### A. People as a Library view

**`Workspace` loses `.people`.** The enum becomes `{ .cull, .library }`
(⌘1/⌘2). `LibraryViewMode.people.workspace` returns `.library`. The exhaustive
`switch`es on `Workspace` (`defaultSubView`, `title`, `keyEquivalent`,
`sidebarSections(for:)`, `AppWindowLayoutMetrics.minimumWidth(for:)`) drop their
`.people` arms; People inherits the Library window floor and empty sidebar.

**The sub-view toggle gains People.** `librarySubViewToggle` becomes
Grid | Loupe | Timeline | Map | People, and the View-menu sub-view switcher
(`WorkspaceCommands` / `AppMenuCoveragePresentation.subViewMenuModes` /
`LibraryViewMode.subViewMenuTitle`) gains a "People" item — menus stay the
system of record.

**`WorkspaceChromePolicy` becomes view-aware (the main structural work).** Every
predicate is re-keyed from `Workspace` to `LibraryViewMode`. Browse chrome
(search field, filter tokens, import button/menu, footer, cull/export/more
toolbar actions) shows for a **browse view**: `view.workspace == .library &&
view != .people`. The sub-view toggle shows for *any* `.library` view (People
included) so People is escapable. The inspector shows everywhere. Because People
is now a Library-workspace view, keying on `Workspace` alone would leak full
browse chrome onto it — the view-aware policy is what preserves People's focused
chrome. Call sites pass `model.selectedView` instead of `model.selectedWorkspace`.

**Search/Export from a non-browse view.** `requestFocusSearch` and
`requestExport` currently switch to the Library *workspace* when elsewhere. With
People inside Library, "already in Library" is no longer sufficient — from
People (or Cull) they must land on a browse view. They switch to `.grid` when
the current view can't show that chrome (`!showsSearchField` / `!showsExportButton`).

**Entry points.** People is reached by the toggle, the View menu, ⌘1→toggle, or
the existing `SidebarRowTarget.people`/`selectSidebarTarget(.people)` route
(unchanged — it already sets `selectedView = .people`). The old ⌘3 workspace
shortcut is gone.

### B. Face-group review surface

**Card → link.** A suggestion card's primary gesture opens the review surface
for that group instead of one-tap confirming or jumping to the grid. The card
stays a compact link (representative crop, "Is this <name>?" / "Who is this?",
face/photo count) with its dismiss affordance; Confirm/Name move into review.
The keyboard queue (`PeopleQueuePresentation`) is unchanged.

**`FaceGroupReviewPresentation` (testable core).** Built by the model from a
`PeopleFaceSuggestion` by resolving each `faceID` to its bounding box via
`faceObservations(assetID:)` (grouped by asset). Produces:
- `title` — "Is this <name>?" (matchExisting) or "Who is this?" (newPerson).
- `tiles: [FaceReviewTile]` — `{ faceID, assetID, boundingBox }`, one per face,
  stable order (asset id, then face index).
- `remainingFaceCount` / `remainingPhotoCount` and a `summary` string.
- `confirmActionTitle` — the person's name (matchExisting) or "Name…" (newPerson).
- `isConfirmEnabled` — false when the group is empty.

Because removal is a real catalog gesture (below), the presentation is a pure
projection of the *current* suggestion; the view recomputes it from
`model.peopleFaceSuggestions` after each mutation. No divergent local
include/exclude set — one source of truth.

**Removal reuses foundation gestures.** "Remove this face" dispatches on kind
via a new `removeFaceFromReviewGroup(_ suggestion:, faceID:)`:
- matchExisting → `rejectFaceSuggestion(faceID, personID:)` (deletes the AI row,
  records `rejected_face_people` — sticky, per the foundation).
- newPerson → `dismissPeopleFaceSuggestion` over just that face (`dismissFaces([faceID])`).
Either way `refreshPeopleFaceSuggestions` runs; the group shrinks or vanishes.
The confirm-before-write negative holds: removing a face writes **no** person
assignment.

**Confirm/Name over what remains.** The review's confirm bar calls the existing
`confirmPeopleFaceSuggestion(_:)` (matchExisting) or, for newPerson, the naming
sheet → `confirmPeopleFaceSuggestion(_:personName:)`, operating on the
suggestion as it now stands (already pruned).

**Whole-photo reveal.** Each tile shows a large rectangular face crop by
default; hover or click swaps to the full preview image (fit). Pure view state.
The crop loader (`FaceCropAvatar.loadCroppedFace`) is extracted to a shared
`FaceCropLoader.loadCroppedFace(previewURL:boundingBox:)` reused by the avatar
and the new tile, so the rectangular tile does not duplicate it.

## Testing

- **Chrome policy:** `WorkspaceChromePolicy` view matrix — every browse view
  shows browse chrome; `.people` shows the toggle and inspector but no search /
  filter tokens / import / footer / cull / export / more; cull views show none.
- **Workspace:** `Workspace.allCases == [.cull, .library]`; `.people.workspace
  == .library`; ⌘ equivalents 1/2; `selectWorkspace` restore still works with
  People as a Library sub-view; window floor for a People view is the Library floor.
- **Toggle / menu:** People is in the sub-view toggle options and the View-menu
  sub-view set; `subViewMenuTitle(.people) == "People"`.
- **Search/Export routing:** `requestFocusSearch` / `requestExport` from
  `.people` (and `.loupe`) land on `.grid` and bump their token.
- **Review presentation:** tiles carry the right bounding box/asset per face in
  stable order; counts and confirm title/enabled reflect matchExisting vs
  newPerson and shrink as faces are removed; empty group disables confirm.
- **Review removal (catalog ground truth):** removing a matched face records
  `rejected_face_people` and writes no `person_assets`/`person_faces user` row;
  removing a clustered face dismisses it; the suggestion shrinks; confirming the
  remainder assigns only the kept faces.
- **Scenario card (authored, not run):** open People from the Library toggle,
  open a face group, remove a wrong face, confirm the rest, assert catalog
  ground truth and the negative before confirm.

## Risks

- **Chrome-policy re-key is the biggest regression risk** — a missed call site
  leaks Library browse chrome onto People or hides it on a browse view. Every
  `WorkspaceChromePolicy` consumer is enumerated and switched to `selectedView`.
- **Workspace enum shrink** touches several exhaustive switches and a number of
  tests that named `Workspace.people`; all are updated together.
- **Merge coordination:** sub-project 4 (global filter persistence) also edits
  `AppModel.swift` and `LibraryGridView.swift`. Regions changed are listed in the
  plan/handoff for conflict planning.
</content>
</invoke>
