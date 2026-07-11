# Focused Workspaces — open decisions and known gaps

Carried out of the 2026-07 focused-workspaces implementation
(`docs/superpowers/specs/2026-07-09-focused-workspaces-design.md`). Each item
is deliberately deferred, not forgotten — resolve during dogfooding.

## Product decisions awaiting dogfood judgment

- **Two vs. three workspaces.** A design reviewer argued People should collapse
  into Library plus a generic "decide" queue. Kept three because face
  identification is its own sitting in practice. Revisit if People feels thin.
- **Star concept triplication.** Three star-adjacent concepts coexist: the
  Starred collection (assets), Starred Work (sessions), and star-a-job in the
  Activity popover. Needs a naming/concept pass of its own.
- **HUD counts are session-wide, not scope-filtered.** In a picks-only pass the
  undecided/pick/reject pills still show whole-session numbers. Scoped counts
  would need repository-level queries (the in-memory page would lie under
  pagination). Decide whether session-wide is actually right ("will I finish
  tonight") or worth the query work.
- **Esc on a focused People review card is a no-op** (suggestion cards dismiss).
  Decide what Esc should mean there.
- **Matched-work sidebar rows replace the starred-work rows** while a Library
  query is active; clearing the query restores them. Defensible, possibly
  surprising.
- **Cull end-of-set Export popover anchors to the toolbar button**, not the
  stage button that opened it. Cosmetic.
- **Toolbar Cull button takes a selection fast-path** (culls the current
  selection when one exists). Confirm that's the wanted gesture.
- **Timeline/Map have no arrow-key navigation** (the culling monitor no longer
  reaches them; they never had their own). Add if it comes up in use.

## Known test-fixture gaps

- **`--smoke` pre-seeds metadata**: 11/24 photos arrive flagged and 4/24 rated 3.
  Scenario assertions must be baseline-relative, never assume a clean slate.
- **`--smoke` has no persisted stacks**, so the Return
  promote-frame-and-reject-siblings gesture (and its single-undo-group
  guarantee) is unit-tested but has never been exercised live end-to-end. A
  stack-bearing seed variant would close this.
- **No UI-reachable trigger exists for the metadata-sync-conflict or
  source-availability rescans** — both fire only off worker-queue events. This
  makes the Activity item's badge states impossible to scenario-test
  (`quiet-activity-badge` and `activity-icon-states` are PARTIAL for this
  reason) and may also be a real product gap: a user who fixes a sidecar or
  remounts a drive has no way to ask for a re-check.
- **The Sparkle install handshake** (`com.teststrip.app-spki`/`-spks`) can only
  be exercised by a real published release; the first v0.x → v0.x+1 update on
  a real install is the acceptance test. If post-update state looks off, try
  adding Sparkle's `shared-preference.read-write` temporary exception (its
  reference sandboxed app carries it; we omitted it).

## Scenario-authoring lessons (also see test/scenarios/README.md)

- Ground truth comes from the app's **advertised** semantics, not assumptions:
  `rating:3` means rating ≥ 3 (per the search-tips help text), so card SQL must
  use `>=`. Three initial card failures were all card bugs of this kind.
- Seed catalogs bake absolute `original_path` values at seed time; any
  relocation (e.g. into the Tart VM's per-launch directory) must rewrite the
  prefix or every file-fidelity assertion (sidecars, Move Rejects) silently
  breaks. `script/vm_scenario_run.sh`'s launch verb does this.

## Watch items (persona loop)

- **Inert trash-confirm ghost** (2 sightings, different signatures): persona-1 was the disabled-primary trap (fixed dd60a59e); persona-4 reported an enabled-looking primary with no inline error and no action on a post-fix build — NOT reproduced by two follow-up live sessions. If it recurs, instrument the moveRejects* entry points (note: the app currently has no logging framework — adding one is its own decision).
- **On-canvas cull controls in Loupe for mouse users** — spec tension with minimal-chrome; Jesse call.
- **Export overwrite prompting** vs silent -2/-3 suffixing — Jesse call.
