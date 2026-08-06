# Autopilot ghost derivation (SP-D0, split from kata #12) — design

**Decision date:** 2026-08-06. Brainstormed with Jesse. This is the
reconciliation half of SP-D, split out and shipped first so the run-lifecycle
spec builds on honest counts. Parent spec:
`docs/superpowers/specs/2026-07-16-culling-flow-implementation-design.md`.

## Problem

The machine's flag opinion lives in two places that drift: the unconfirmed
AI flag in asset metadata (the ✨ ghost) and an `autopilot_proposals` row
with a `status` column. The row's status is never reconciled — a direct
P/X/U leaves it `pending` forever, proposals suppressed by
`removed_ai_labels` still write `pending` rows that inflate counts, and
only a display-time kind-aware filter (kata #4) papers over the gap. The
completion summary's "✨ awaiting review" row is structurally unreachable
for flag proposals (completion requires undecided = 0) and so can only
ever nag about keyword proposals, which Jesse ruled are ambient and not
worth nagging about.

## Decisions (Jesse, 2026-08-06)

1. **Split SP-D; reconciliation ships first.** This spec is the small
   honest-data piece; the run-lifecycle spec follows separately.
2. **Keyword proposals are ambient.** Always created, removable like any
   AI label, "no big deal" — they exit the review pipeline entirely and
   never drive a review count or nag.
3. **No ✨ ink at completion.** The completion summary is purely about the
   user's decisions: picked / rejected / undecided / skipped / never
   viewed. No awaiting-review row, no superseded line, no
   Review-AI-suggestions ceremony.
4. **Derive, don't store.** The ghost — the unconfirmed AI flag in asset
   metadata — is the single source of truth for "the machine proposed a
   flag." No status machine anywhere; it must be possible for a frame to
   have no status at all.
5. **Gone is gone.** A direct user flag replaces the ghost; pressing `U`
   afterwards returns the frame to neutral undecided. Today's
   table-backed resurrection of the ghost badge is the bug (the tutorial
   already says "your P/X/U on a frame simply replaces its ghost").
6. **Drop `autopilot_proposals` entirely.** Verified before deciding:
   proposal `rationale`/`confidence` are write-only (the rendered
   rationales are the live stack-recommendation phrases, computed from
   evaluation signals at display time); `undoAutopilotRun` replays an
   in-memory change group and uses the table only for a status flip; the
   post-relaunch reconstruction exists only so badges/banner survive, and
   ghosts survive relaunch natively in `metadata_json`.
7. **Batch-clear undo atomicity stays out of scope.** Dispositioned in
   the SP-A final review as consistent-with-existing (AI-label removal
   has never been undoable); awareness only, no work here.

## Design

### Derivation (single source of truth)

An asset's autopilot ghost is its flag label when the label is AI-origin
and unconfirmed. Every proposal state is derived from metadata, never
stored:

- **Proposed** = the ghost exists. Its kind is the ghost's own value
  (pick/reject) — no table lookup.
- **Overridden** = a user-origin flag replaced the ghost. Gone is gone;
  `U` yields neutral undecided, nothing resurrects.
- **Dismissed** = ghost removed via the review surface, recorded in
  `removed_ai_labels`. [Corrected 2026-08-06 during plan authoring: this
  recording is NEW — today's `dismissAutopilotProposals` removes without
  recording, so a re-run could resurrect a dismissed ghost. Routing
  dismiss through `removeAIField` closes the gap and is what the
  no-resurrection invariant requires. Behavior change 6 below.]
- **Never applied** = `removed_ai_labels` suppressed the write at apply
  time, so no ghost exists and nothing counts it. The inflation bug
  vanishes by construction.
- **Keywords** = ambient AI labels from the moment `runAutopilot` applies
  them; invisible to all flag-ghost derivation.

One derivation helper, one home (a small pure function over
`AssetMetadata`, same single-computation-source discipline as SP-B);
every surface below reads it. No surface may re-derive ghost state with
its own metadata poking.

### Deletions

- `autopilot_proposals` table: `DROP TABLE` catalog migration (indexes go
  with it). The stale rows in the real catalog are bookkeeping, not
  truth; the ghosts in `metadata_json` are untouched.
- `CatalogRepository` proposal APIs: save, query-by-run, query-by-status,
  status update, count-by-status, delete-by-run, and the asset-delete
  cascade line.
- `AutopilotProposalStatus`.
- `AppModel.pendingAutopilotProposals`, `reconstructAutopilotStateAfterLoad`,
  `lastAutopilotRunIDByScopeKey` bookkeeping, and
  `distinctPendingAutopilotProposalAssetIDs`.
- The kata-4 kind-aware display filter and the completion call site's
  kind partition (LibraryGridView `cullCompletion`).
- `undoAutopilotRun`'s status-flip block (the in-memory change-group
  replay, with its merge-aware semantics, is untouched).
- `AutopilotProposal` may survive only as an in-memory working type
  inside `runAutopilot`; nothing persists it.

`runAutopilot` keeps its generation and apply logic (including the
`removed_ai_labels` and user-flag-present skip rules); it just stops
persisting proposals.

### Surfaces

- **Completion summary** (`CullCompletionPresentation`): drop the
  `sparkleAwaiting` count and the `.reviewAISuggestions` action; the
  `summary(...)` signature loses both pending-proposal-ID-set parameters;
  the run detail line drops "N AI suggestions awaiting review". The
  remaining ceremonies (Export picks, Move rejects, Move rejects to
  Trash, Review picks, Save picks as set) are unchanged.
- **Review surface** (`beginAutopilotReview`): the queue is "assets
  carrying a ghost," derived from metadata. Flags only. Commit stays
  promote-to-user-origin (sidecar written where eligible); dismiss removes
  the ghost via `removeAIField`, which records `removed_ai_labels` (a fix —
  today's dismiss records nothing; see behavior change 6). Universe:
  catalog-wide, matching
  today's global pending query — the review queue and the sidebar count
  must not silently shrink to the loaded scope. Badges and the completion
  summary keep operating on loaded assets, as today.
- **Sidebar "AI Suggestions" cull source** and its count: derived from
  ghosts; the source appears only when at least one ghost exists.
- **KEEP/CUT badges** in the cull view: read the ghost's own value
  instead of the in-memory proposals array.
- **Autopilot banner**: run-time-only. `AutopilotRunSummary` is still set
  by `runAutopilot`; it is never reconstructed after relaunch (its undo
  button was already dead post-relaunch). Ghost badges survive relaunch
  natively via metadata.

### Behavior changes (the honest list)

1. `U` after overriding a ghost leaves neutral undecided (was: the badge
   resurrected from the table).
2. Completion carries no ✨ ink and no Review-AI-suggestions ceremony;
   review stays reachable mid-run from the sidebar source and banner.
3. The review queue is flags-only; keyword proposals never enter it.
4. Suppressed proposals cannot inflate any count — they never exist.
5. The banner no longer survives relaunch; badges now survive it
   natively.
6. Dismissing a ghost in review now records `removed_ai_labels` (today's
   dismiss removes without recording, so a later autopilot run could
   resurrect a dismissed ghost — closing this is required by the
   no-resurrection invariant).

### Invariants (unchanged, re-asserted in tests)

Ghosts are `origin = ai`, unconfirmed: never written to sidecars, never
counted as decided, never fill progress, never enter the Picks set, never
export/relocate/trash. Commit flips origin to user and writes the sidecar
for sidecar-eligible fields; removal records `removed_ai_labels` so
nothing resurrects. Original bytes untouched.

## Out of scope

- Everything in the run-lifecycle spec: start card (⌘R), lenses, exact
  resume, completion one-key scoped mini-runs, unifying
  `CullingSessionCompletionSummary` with `CullCompletionPresentation`.
- Batch-clear undo atomicity (decision 7).
- Any change to how ambient AI keywords are applied, displayed,
  confirmed, or removed.
- Persisting run-undo across relaunch (was never supported; stays
  unsupported).

## Testing

**Unit (TDD):**

- Derivation: ghost → proposed with kind from the flag value; user-origin
  flag → no ghost state; no flag → nothing (a frame can have no status).
- Gone is gone (negative): apply ghost, override with user flag, clear
  with `U` → derivation reports nothing; no badge, no review-queue
  membership.
- Suppression: `removed_ai_labels` present → apply skips → derivation and
  every count report nothing.
- Completion: no `sparkleAwaiting`, no `.reviewAISuggestions` action, for
  scopes with and without ghosts.
- Review queue: ghost-carrying assets only; ambient AI keywords on an
  asset never enroll it.
- Commit/dismiss: asserted against metadata origin AND sidecar ground
  truth (commit writes the sidecar; dismiss records `removed_ai_labels`
  and writes none).
- Undo-run: merge-aware cases unchanged after the status-flip block is
  deleted; user-origin flags never reverted.
- Migration: a catalog containing `autopilot_proposals` rows opens clean;
  the table is gone; ghosts in metadata are untouched.

**End-to-end (scenario card, VM, seeded batch):** run autopilot; ghosts
render as badges; override one ghost with `X`, press `U`, assert against
`metadata_json` that no ghost returns; complete the run and assert the
summary carries no ✨ line; open review from the sidebar and assert it
lists exactly the ghost-carrying assets; relaunch and assert badges
survive while the banner is absent. Existing cards asserting the old ✨
completion line or review ceremony are reconciled in the same push
(audit cull-011, cull-023, cull-025 at implementation).
