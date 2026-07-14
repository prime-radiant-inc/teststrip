# Current-stack rail: vertical thumbnail candidates in the Cull loupe

_Date: 2026-07-13_

## Problem

When culling in the loupe, you judge one big image at a time but you are
really choosing *within a stack* of near-duplicate shots — the burst you want
to reduce to the keeper(s). Today the loupe stage does not let you see the
candidate set clearly: to know "what am I culling from," you have to read the
horizontal filmstrip (all stacks, mixed) or the small text-chip rail at the
top of the stage. Neither shows the **images** of the current stack's frames
side by side with the signals that distinguish them.

We want a **vertical rail of the current stack's frames** down the left of the
loupe stage — thumbnails you can compare at a glance, each showing its
decision, whether it is the AI pick, and the provisional reads (sharpness,
eyes, duplicate) that tell near-duplicates apart.

## What already exists (this is a reorganization, not a new component)

- `CullingStackRailPresentation` (in `LibraryGridView.swift`) already computes,
  for the current stack, an ordered list of `Item`s each with `assetID`,
  `label`, `isSelected`, `isRecommended`, and `flawBadges: [CompareDecisionBadge]`,
  plus `titleText`, `positionText`, `rationaleText`, a keep action, and a
  secondary-actions menu. The "current stack" is the stack containing
  `selectedAssetID`.
- `cullingStackRail(presentation:)` renders it today as a **horizontal**
  `HStack` at the **top** of the loupe stage (rendered when `showsCullChrome`),
  as small (24–32pt) **text chips** showing each frame's `label`, a `✦` for the
  recommended frame, an orange fill for the selected one, and a single red dot
  when a frame has any `flawBadges`. Clicking a chip calls `model.select(...)`.
- `cullingFilmstrip` renders the horizontal, stack-divided filmstrip across the
  whole scope, below the rail.
- The collapsible `CullSidebarView` ("Cull From" + an all-stacks list) is a
  separate left sidebar toggled by the standard sidebar control.

So the rail *concept* and its presentation exist; this work relocates and
enriches the **view**, adds decision state to the cells, and remaps the
keyboard.

## Decisions (settled during brainstorming)

- **In-stage vertical rail on the left**, coexisting with the collapsible "Cull
  From" sidebar — collapse the sidebar and the stack rail remains. (This
  restores an in-stage rail, scoped to just the current stack.)
- **Two views, two jobs**: the left rail shows the *current stack's* candidates;
  the horizontal filmstrip stays the *across-everything* navigator.
- **Rich cells**: thumbnail + decision (✓ pick / ✕ reject / ★ rating) +
  highlight on the loupe'd frame + a marker on the AI-recommended frame + small
  badges for the provisional AI reads (sharpness, eyes-open/blink, duplicate).
- **Signals are display-only.** Showing provisional evaluation reads does not
  write anything — confirm-before-write is unchanged.
- **Keyboard axes match the layout** (a deliberate inversion of today's mapping,
  because the rail is vertical and the filmstrip is horizontal):
  - **↑ / ↓** — previous / next candidate **within the current stack** (up/down
    the rail); stops at the stack's ends.
  - **← / →** — previous / next **stack**; landing on a new stack selects its
    AI-recommended frame.
  - **Space** — linear advance: next candidate down the stack, then roll into
    the next stack's recommended frame at the bottom.
  - **Return** — unchanged: promote the loupe'd frame + reject its siblings; the
    rail immediately shows ✓ on the pick and ✕ on the siblings.
  - **⌥← / ⌥→** — retired (redundant with the new ← / →).

## Goals

- The loupe stage shows a vertical, left-edge rail of the current stack's frames
  as thumbnails, updating as the selection moves between stacks.
- Each cell surfaces enough to choose without loupe'ing every sibling: image,
  decision, recommended marker, and the sharpness/eyes/duplicate reads.
- Keyboard navigation matches the visual axes (↑/↓ within stack, ←/→ across
  stacks) and Return still promotes-and-rejects.
- No regression to confirm-before-write or non-destructive invariants.

## Non-goals

- No change to how stacks are built (`AssetStackBuilder`) or how the AI
  recommendation is computed.
- No change to the collapsible "Cull From" sidebar or the horizontal filmstrip's
  own layout (it stays; only its keyboard role shifts to ←/→).
- No new evaluation signals; the rail displays existing provisional reads.
- Not a compare/survey redesign — this is the single-loupe stack rail only.

## Architecture

### Layout

The loupe stage becomes, left to right: **[current-stack rail] [loupe]**, with
the **filmstrip** along the bottom of the loupe column — inside, and to the
right of, the collapsible `CullSidebarView`.

```
[ Cull From      | [stack] | [        loupe        ] ]
[ sidebar        | [ rail  | [                      ] ]
[ (collapsible)  | [ this  | [                      ] ]
[                | [ stack]| [   filmstrip (all)    ] ]
```

The rail is rendered only when `showsCullChrome` is true (same gate as today's
horizontal rail and filmstrip). Its width is fixed (wide enough for a legible
thumbnail + badges); it scrolls vertically when a stack has more frames than
fit.

### Presentation (`CullingStackRailPresentation`)

Reuse the existing struct; extend `Item` with the one thing it lacks for the
richer cells:

- Add a `decision` field to `Item` capturing pick / reject / rating / none for
  that frame (the same decision state the filmstrip tiles show — reuse that
  source rather than recomputing). `isSelected`, `isRecommended`, and
  `flawBadges` already exist.
- `flawBadges: [CompareDecisionBadge]` already enumerates the per-frame reads;
  the view renders them as individual badges (sharpness / eyes / duplicate)
  instead of collapsing them to one red dot.
- `titleText` / `positionText` / `rationaleText` / the keep action / the
  secondary-actions menu carry over; they move into the rail's **header**
  (title + "stack N of M · K frames") and **footer** (keep action + overflow
  menu), so the rail is self-contained.

The "current stack = stack containing `selectedAssetID`" lookup is unchanged.

### View (`cullingStackRail`)

Rewrite the view body from a horizontal `HStack` of text chips into a vertical
rail:

- A header (title + position/rationale).
- A vertically scrolling list of **thumbnail cells**, one per `Item`, each:
  a preview thumbnail (same preview source the filmstrip tiles use), a
  selection highlight, a `✦`/star recommended marker, a decision overlay
  (✓/✕/★) matching the filmstrip's decision styling, and the AI-read badges
  from `flawBadges`. Tapping a cell calls `model.select(item.assetID)` (as
  today).
- A footer with the keep action (primary) and the secondary-actions menu.

Extract the per-cell view into a focused subview (`CullStackRailCell` or a
private `func`) so the stage view file does not grow a large inline body.

### Keyboard (`CullingKeyCaptureView`)

Remap in `CullingShortcut.init(event:)`:

- ↑ / ↓ → new within-stack actions (previous / next candidate in the current
  stack), replacing today's `previousStack` / `nextStack` on those keys.
- ← / → → `previousStack` / `nextStack`, replacing today's `previousPhoto` /
  `nextPhoto`.
- Space → linear advance (next candidate; at the stack's last frame, advance to
  the next stack's recommended frame).
- Drop the `⌥← / ⌥→` stack-jump branch.
- Return / promote unchanged.

Add the corresponding `AppModel` navigation methods (next/previous candidate
within the selected stack; select a stack's recommended frame) if they do not
already exist; the stack membership and recommendation logic already do.

Update the key-map overlay (Shift+/) and any menu equivalents so the displayed
bindings match the new mapping.

## Data flow

`selectedAssetID` + stacks + assets + per-asset evaluation signals + decision
states + recommendation → `CullingStackRailPresentation` (pure) → `cullingStackRail`
view. Clicking a cell or pressing a nav key changes `selectedAssetID` through
the existing select path; the presentation recomputes; the rail and filmstrip
both follow. No worker, queue, or catalog changes — presentation layer only.

## Testing

- **Unit (`CullingStackRailPresentation`)**: for a selected frame in a
  multi-frame stack, the items are the current stack's frames in order with
  correct `isSelected` / `isRecommended` / `decision` / `flawBadges`; moving the
  selection to another stack swaps the items; the no-stack / no-selection case
  yields empty. Cover the new `decision` field and the per-badge expansion.
- **Unit (`CullingShortcut`)**: ↑/↓ map to within-stack prev/next, ←/→ map to
  prev/next stack, Space to linear advance, Return to promote — update the
  existing shortcut-mapping tests to the new axes; assert the retired ⌥←/⌥→ no
  longer map.
- **E2E scenario card (VM)**: in the Cull loupe, the left rail shows the current
  stack's frames as thumbnails with recommended marker and AI badges; ↓ moves
  down the rail within the stack; → moves to the next stack and lands on its
  recommended frame; clicking a cell loupe's it; Return promotes and the rail
  shows ✓/✕; verify catalog ground truth for the promote/reject and re-assert
  confirm-before-write (the displayed signals wrote nothing).

## Risks and open items

- **Muscle-memory change.** Inverting ←/→ ↔ ↑/↓ changes existing culling
  reflexes. It is deliberate (axes now match the layout) and the key-map overlay
  advertises it, but it is the one behavior change to flag for dogfood.
- **Header/footer placement.** The existing rail's title/position/keep/menu must
  fit the vertical rail's header/footer without crowding the thumbnails; if the
  keep action reads better elsewhere (e.g. the HUD), decide during
  implementation and note it.
- **Thumbnail cost.** The rail renders one preview per current-stack frame;
  reuse the filmstrip's preview source and caching so a large stack does not
  add a new fetch path.
- **Decision source.** Confirm the filmstrip's per-frame decision state is
  reusable for the rail `Item.decision`; if it lives in a different presentation,
  thread the same input rather than recomputing.

## Out of scope

- Compare/survey (A-B) redesign; stack-building heuristics; new AI signals;
  changes to the "Cull From" sidebar or the filmstrip's own tile layout.
