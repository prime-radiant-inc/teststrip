# Plan: People as a library view + face-group review redesign

Spec: `docs/superpowers/specs/2026-07-14-people-library-view-and-face-review.md`.
Branch: `feat/people-library-view-and-face-review`. Strict TDD, small commits.

## Part A — People becomes a Library view

### A1. `WorkspaceChromePolicy` re-keyed to `LibraryViewMode`
- Test (`WorkspaceChromePolicyTests`): rewrite to a view matrix. Browse views
  (`.grid/.timeline/.map/.libraryLoupe`) show browse chrome; `.people` shows the
  toggle + inspector only; cull views show none.
- Impl: change every predicate signature `Workspace` → `LibraryViewMode`.
  `showsBrowseChrome(view) = view.workspace == .library && view != .people`
  drives search/filter/import(button+menu)/footer/cull/export/more.
  `showsLibraryViewToggle(view) = view.workspace == .library`. `showsInspector`
  → true.
- Update call sites in `LibraryGridView.swift` (toolbar, top bar, footer, top
  inset), `main.swift` (inspector binding), `AppModel.scrollInspector` to pass
  `selectedView`.

### A2. Remove `.people` from `Workspace`
- Test (`WorkspacePresentationTests`): `Workspace.allCases == [.cull, .library]`;
  `.people.workspace == .library`; key equivs 1/2; selectWorkspace restore.
- Impl: drop `.people` from the enum and its `defaultSubView`/`title`/
  `keyEquivalent` switches; `LibraryViewMode.people.workspace = .library`;
  `sidebarSections(for:)` `case .cull` only; `AppWindowLayoutMetrics` drop
  `.people`.
- Fix fallout tests: `AppWindowLayoutTests`, `SidebarSectionsTests`,
  `InspectorTabsPresentationTests`, `AppModelTests` (People via `selectedView`/
  `selectSidebarTarget`, not `selectWorkspace(.people)`).

### A3. People in the sub-view toggle + View menu
- Test (`MenuCoveragePresentationTests` / a toggle presentation test):
  `subViewMenuTitle(.people) == "People"`; `.people` in `subViewMenuModes`.
- Impl: add `.people` tag to `librarySubViewToggle`; add People to
  `subViewMenuModes` and `subViewMenuTitle`.

### A4. Search/Export routing from non-browse views
- Test (`AppModelTests`/`InspectorTabsPresentationTests`): from `.people` and
  `.loupe`, `requestFocusSearch`/`requestExport` set `selectedView == .grid` and
  bump the token.
- Impl: guard on `!WorkspaceChromePolicy.showsSearchField(selectedView)` /
  `!showsExportButton(selectedView)` → `selectedView = .grid`.

## Part B — Face-group review surface

### B1. Extract `FaceCropLoader`
- Test (`FaceCropAvatarTests` or new): `FaceCropLoader.loadCroppedFace` returns a
  crop for a valid preview (reuse existing avatar coverage).
- Impl: lift `FaceCropAvatar.loadCroppedFace` into a shared enum; avatar calls it.

### B2. `FaceGroupReviewPresentation` + model builder
- Test (`FaceGroupReviewPresentationTests`): given a suggestion + observations,
  tiles carry correct box/asset in stable order; counts, title, confirm
  enable/disable for matchExisting vs newPerson.
- Impl: `struct FaceReviewTile`, `struct FaceGroupReviewPresentation`, and
  `AppModel.faceGroupReview(for:) -> FaceGroupReviewPresentation` resolving boxes
  via `faceObservations`.

### B3. Removal gesture
- Test (`FaceGroupReviewTests`, catalog ground truth): `removeFaceFromReviewGroup`
  on a matchExisting group records `rejected_face_people`, writes no user
  assignment, suggestion shrinks; on a newPerson group dismisses the face.
- Impl: `removeFaceFromReviewGroup(_:faceID:)` dispatching to
  `rejectFaceSuggestion` / `dismissPeopleFaceSuggestion`.

### B4. Review view + card retarget
- Presentation-tested where possible; the SwiftUI `FaceGroupReviewView` (sheet)
  and `FaceReviewTileView` (crop ↔ whole-photo reveal) are wired in `PeopleView`.
- Card primary gesture opens the review sheet.

## Part C — Verify + document
- `swift test` green, `swift build` clean, `make verify` once near the end.
- Author scenario card `people-021-face-group-review.md` (do not run live).
- Update `CLAUDE.md`/docs only if a stated fact drifts (People is a view now).
- Report changed `AppModel.swift`/`LibraryGridView.swift` regions for merge
  planning.
</content>
