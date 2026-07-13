# activity-007-per-kind-lanes: Preview and evaluation worker lanes run concurrently, each with its own Activity bar and cancel

**What this covers**: the headline feature of the parallel-worker-lanes
branch (`docs/superpowers/specs/2026-07-13-parallel-worker-lanes-design.md`)
— preview generation (`.previewGeneration`) and AI evaluation (`.recognition`)
used to share one FIFO worker lane and compete; they now run as independent
concurrent lanes, each capped at one in-flight command
(`managedWorkerKindRunningLimits`, `Sources/TeststripApp/AppCatalog.swift:35-43`
— every worker-dispatched kind capped at 1) while the queue's global cap and
the worker's dispatch cap are both raised past the lane count
(`BackgroundWorkQueue(maxRunningCount: 8, ...)`,
`WorkerSupervisor(..., maxDispatchedCommandCount: 8)`,
`Sources/TeststripApp/AppCatalog.swift:126,131`) so lane concurrency is no
longer gated by a shared slot pool. This card proves that concurrency is
observable end to end: **two separate Activity Center bars advance at the
same wall-clock time** ("Generate previews" and "Evaluate photos"), catalog
ground truth lands for both (cached previews, `evaluation_signals` rows), the
confirm-before-write invariant holds throughout, and per-kind cancel on one
lane leaves the sibling lane running — the concurrent-lanes analogue of the
old single-worker "cancel stops everything" behavior.

## Pre-state
```bash
ROOT_DIR="$(git rev-parse --show-toplevel)"
IMPORT_DIR="$ROOT_DIR/sample-data/photos/jesse-pictures"   # 79 real JPEGs, no GPS/faces fixture needed
TESTSTRIP_CARD_IMPORT_ROUTE=typed-path ./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
PREVIEWS="$ISOLATED/Teststrip/Previews"
```
`--smoke`'s 24 synthetic photos are pre-rendered (0 pending previews at idle,
established in `worker-001-preview-lifecycle.md`), so this card imports the
79-photo `jesse-pictures` fixture mid-session to get a batch that genuinely
starts queued — large enough that preview generation and evaluation both
take several seconds, giving a real window to sample both lanes advancing
rather than needing sub-second timing precision. `TESTSTRIP_CARD_IMPORT_ROUTE=typed-path`
(read by `LibraryGridView.swift:7797`) routes the card-import sheet through a
typed path field instead of a native file panel, so `script/submit_import_path.sh`
can drive it headlessly (per `worker-001-preview-lifecycle.md`'s proven
pattern).

Confirm idle baseline before importing:
```bash
sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue;"                              # expect 0
sqlite3 "$DB" "SELECT count(*) FROM work_sessions WHERE status IN ('queued','running');"    # expect 0
sqlite3 "$DB" "SELECT count(*) FROM people;"                                                # expect 0
sqlite3 "$DB" "SELECT count(*) FROM person_assets;"                                         # expect 0
```

**`jesse-pictures` ships with a pre-existing `.xmp` sidecar next to every
JPEG** (`find "$IMPORT_DIR" -name "*.xmp" | wc -l` reads 79, one per photo,
checked into the repo — confirmed 2026-07-13; this is the same fixture the
`real-corpus-smoke` bench's `adjacent_sidecars`/`imported_sidecar_sync_items`
metrics are built to exercise, `Sources/TeststripBench/RealCorpusSmoke.swift`).
That means "no `.xmp` file exists" is **not** a valid confirm-before-write
check for this fixture — sidecars are already there before this card ever
launches the app. Snapshot their content instead, to diff against after the
run:
```bash
XMP_BEFORE="$(mktemp)"
find "$IMPORT_DIR" -name "*.xmp" -exec shasum {} \; | sort > "$XMP_BEFORE"
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`. Confirm the idle-baseline
   queries above before importing, so any activity observed afterward is
   attributable to this card's import, not a stale prior run.
2. **Import `$IMPORT_DIR`, don't wait for completion** — the concurrency race
   is the point: `script/submit_import_path.sh Teststrip "$IMPORT_DIR"`,
   leaving defaults (including "Evaluate after import" checked — evaluation
   is enabled by default, `importAutoEvaluationEnabled = true`,
   `Sources/TeststripApp/AppModel.swift:2299`).
3. **Open the Activity popover promptly** (toolbar Activity button) and keep
   re-asserting frontmost on every poll (`ax_drive.sh wait-vended` each
   iteration — a backgrounded app parks its AX tree, per
   `test/scenarios/README.md`'s idle-wedge warning). Within the import's
   draining window, assert **two separate kind rows are visible at the same
   time**:
   - `"Generate previews"` (`.previewGeneration`,
     `ActivityKindRow.title(for:)`, `Sources/TeststripApp/ActivityCenterPresentation.swift:88`)
   - `"Evaluate photos"` (`.recognition`, same map, line 89)
   (`"Import photos"` for `.ingest` may also be briefly visible while
   cataloging finishes — that's fine and expected; it's not one of the two
   lanes under test here, since ingest is the fast up-front step before
   previews/evaluations begin.) Two simultaneously-rendered rows are only
   possible because `activeWorkKindRows`
   (`Sources/TeststripApp/AppModel.swift:2783-2786`) is folding items from
   two lanes the worker is running **at the same time** — under the old
   single-lane worker, only one kind's items could ever be `.running` at
   once, so this popover would never have shown two active rows
   simultaneously for more than an instant.
4. **Prove both lanes actually advance, not just render.** Sample twice, a
   few seconds apart, while both rows are still visible:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue;"   # sample 1 (pending previews)
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"          # sample 1
   # wait ~3-5s, staying frontmost via ax_drive.sh wait-vended
   sqlite3 "$DB" "SELECT count(*) FROM preview_generation_queue;"   # sample 2 — expect lower
   sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"          # sample 2 — expect higher
   ```
   Assert the pending-preview count **decreased** and the evaluation-signal
   count **increased** between the two samples — both moving inside the same
   window is the falsifiable core of "concurrent lanes," mirroring the
   headless bench's own `overlap_observed` metric definition ("at least one
   sample caught a `.previewGeneration` item and a `.recognition` item both
   running... at once", `script/lane_overlap_verifier_metrics.sh`) but
   observed live through the popover and catalog instead of the
   `TeststripBench lane-overlap` harness (`script/verify_lane_overlap.sh`).
5. **Per-kind cancel — the sibling lane survives.** While both rows are
   *still* active (haven't fully drained — if they have, see Sharp edges),
   press cancel on the **"Evaluate photos"** row (`xmark.circle`, AXHelp
   `"Cancel this work item"`, `Sources/TeststripApp/ActivityCenterView.swift:109-121`).
   This calls `model.cancelWork(kind: .recognition)`
   (`Sources/TeststripApp/AppModel.swift:7847-7852`), which cancels only
   `.recognition`'s currently-active items one at a time via
   `WorkerSupervisor.cancel(id:)`
   (`Sources/TeststripCore/Worker/WorkerSupervisor.swift:195-211` — the
   comment at lines 198-201 documents this leaves the item's lane occupied
   only until its natural terminal event, and never touches other lanes).
   Assert:
   - the "Evaluate photos" row disappears from the popover (or shows no
     remaining active items) while "Generate previews" **remains** and its
     pending count keeps dropping across two further samples a few seconds
     apart.
   - ground truth: `evaluation_signals`' row count goes flat (two samples,
     unchanged) while `preview_generation_queue`'s pending count keeps
     falling:
     ```bash
     sqlite3 "$DB" "SELECT kind, status FROM work_sessions WHERE kind='recognition' ORDER BY updated_at DESC LIMIT 5;"
     sqlite3 "$DB" "SELECT kind, status FROM work_sessions WHERE kind='previewGeneration' ORDER BY updated_at DESC LIMIT 5;"
     ```
     the `recognition` rows read `cancelled`; the `previewGeneration` rows
     still show `queued`/`running` activity.
6. **Let preview generation finish draining** — poll
   `SELECT count(*) FROM preview_generation_queue;` until it reads 0, staying
   frontmost each poll.
7. **Catalog ground truth for both lanes' output**, once settled:
   ```bash
   ls "$PREVIEWS" | wc -l                                                                    # cached preview dirs landed
   sqlite3 "$DB" "SELECT count(DISTINCT asset_id) FROM evaluation_signals a
     JOIN assets b ON b.id = a.asset_id WHERE b.original_path LIKE '%jesse-pictures%';"
   ```
   Assert cached previews landed for (close to) all 79 imported assets, and
   at least *some* `evaluation_signals` rows landed for the batch before
   Step 5's cancel cut evaluation off partway through — don't assert full
   79-asset evaluation coverage, since the cancel in Step 5 deliberately
   truncates it.
8. **Confirm-before-write, re-asserted for this batch**:
   ```bash
   sqlite3 "$DB" "SELECT count(*) FROM people;"          # expect 0
   sqlite3 "$DB" "SELECT count(*) FROM person_assets;"   # expect 0
   XMP_AFTER="$(mktemp)"
   find "$IMPORT_DIR" -name "*.xmp" -exec shasum {} \; | sort > "$XMP_AFTER"
   diff "$XMP_BEFORE" "$XMP_AFTER"                          # expect no diff
   ```
   `people`/`person_assets` (`Sources/TeststripCore/Catalog/CatalogMigrations.swift:124-129,133-138`)
   must both read 0 despite the evaluation lane running face detection inside
   `runEvaluation` (provider `core-image-faces`, per the spec's resolved
   `.recognition`-label open item) — face detection writes evaluation
   signals/face observations, never `people`/`person_assets`, which are only
   written on an explicit naming gesture
   (`people-confirm-writes-on-return.md`). The sidecar diff must be **empty**
   — same file set, same hashes as the Pre-state snapshot: no new `.xmp`
   appeared and none of the 79 pre-existing ones changed. No
   rating/flag/keyword/caption/creator/copyright gesture was performed on any
   asset in this card, so nothing should have touched a sidecar (non-destructive
   invariant, `CLAUDE.md`) — see Sharp edges for why this is a hash-diff
   rather than an existence check.

## Expected
- Step 3: **Fails if** only one kind row is ever visible at a time during the
  import — that's the pre-rewrite single-lane behavior this feature replaced.
- Step 4: **Fails if** either count is unchanged across the sampling window
  while the other moves — that means the two rows are cosmetic, not backed
  by genuinely concurrent execution.
- Step 5: **Fails if** cancelling "Evaluate photos" also stops or visibly
  slows "Generate previews" — a regression of the per-lane cancel semantics
  (`WorkerSupervisor.cancel(id:)` scoping) this rewrite exists to ship.
- Step 7: **Fails if** cached previews or `evaluation_signals` rows never
  land for the imported batch at all.
- Step 8: **Fails if** `people`/`person_assets` gain any row, or the
  before/after sidecar hash diff is non-empty (a new `.xmp` appeared or an
  existing one's content changed) — either is a confirm-before-write /
  non-destructive violation.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
rm -f "$XMP_BEFORE" "$XMP_AFTER"
```
Quit the launched instance. `$IMPORT_DIR` is a checked-in repo fixture —
never delete it or its `.xmp` sidecars; only the isolated catalog/app-support
dir and the two hash-snapshot temp files are throwaway.

## Sharp edges
- **Timing is the main risk to this card.** 79 real JPEGs give a wider
  window than `--smoke`'s pre-rendered 24, but preview render + evaluation
  speed depends on the machine; if Step 5's cancel is attempted after
  evaluation has already fully drained, there's nothing left to cancel. If
  that happens live, re-run from Step 2 with a still-larger folder (e.g. the
  full `sample-data/photos/wordpress-photo-directory` + `loc-free-to-use`
  combined, or repeat the import into a second empty `IMPORT_DIR` copy) and
  drive Step 5 earlier in the window — don't weaken the assertion to pass on
  an already-completed lane.
- **The `.ingest` lane is not one of the two under test.** It's included in
  the same concurrent-lanes machinery (`managedWorkerKindRunningLimits`
  caps it at 1 alongside every other kind, `AppCatalog.swift:35-43`), but
  its own "Import photos" bar isn't the point of this card —
  `activity-002-popover-import.md` covers the `.ingest` row directly. Don't
  conflate a lingering "Import photos" row with the two-lanes assertion in
  Step 3.
- **Providers may fall back to internal serialization without breaking this
  card.** The design spec accepts that a not-concurrency-safe evaluation
  provider (Vision / Core Image / Core ML) may run behind a per-lane
  serialization guard while still overlapping *other* lanes
  (`docs/superpowers/specs/2026-07-13-parallel-worker-lanes-design.md`,
  "Provider-serial fallback is acceptable"). This card only asserts
  preview-vs-evaluation overlap, which holds either way; it does not probe
  which specific evaluation providers are internally serialized.
- **`evaluation_signals` can gain more than one row per asset per
  evaluation pass** (`PRIMARY KEY (asset_id, kind, provider, model, version,
  settings_hash)`, `Sources/TeststripCore/Catalog/CatalogMigrations.swift:63-76`
  — one row per signal kind/provider combination), so its row count is not a
  1:1 proxy for "assets evaluated"; Step 7's `DISTINCT asset_id` query is the
  one that counts assets, the plain `count(*)` samples in Step 4 are only
  meant to show forward motion, not a specific number.
- This card assumes folder-imported assets keep `original_path` pointing at
  the source folder (non-destructive, catalog-first design — originals stay
  in place), which is what makes the `original_path LIKE '%jesse-pictures%'`
  scoping in Step 7 valid; if a future import path starts copying/relocating
  originals on ingest, that query needs revisiting.
- **Why Step 8 is a hash-diff, not an existence check**: `jesse-pictures`'s
  79 pre-existing sidecars mean importing it may exercise sidecar-*adoption*
  at import time (reading a pre-existing `.xmp`'s rating/label into the
  catalog on first touch) — a real, separately-tracked product question
  (`test/scenarios/LEDGER.md`'s `import-005-sidecar-on-import` row: "Priya:
  pre-existing sidecar values ignored at import, lazily adopted on first
  touch — product question for Jesse"). That's orthogonal to what this card
  checks: adoption, if it happens, is a catalog-side read of metadata the
  user already authored outside Teststrip, not a machine verdict written to
  *disk* without a gesture. This card's invariant is narrower and disk-side —
  no sidecar is created or mutated on disk by the concurrent preview/evaluation
  lanes themselves — which the before/after hash diff proves either way,
  without taking a position on the adoption question.

## Run status
PARTIALLY RUN in the Tart VM 2026-07-13 (`vm_scenario_run.sh`, smoke launch +
`submit_import_path.sh` typed-path import of the synced `faces` fixture, 11
photos — `jesse-pictures` could not be synced: its RAW files fill the VM
disk). Verified live, reproduced across two fresh-catalog imports:
- **Both lanes execute on a real import** — the preview lane landed cached
  previews for every imported asset (35 preview dirs = 24 smoke + 11 faces)
  AND the evaluation lane landed 145 `evaluation_signals` across all 11
  imported assets plus 11 `face_observations`. (Steps 4/7 output.)
- **Confirm-before-write holds live** — `people` and `person_assets` both
  read 0 after the import despite `runEvaluation`'s face detection executing.
  (Step 8.)
- **Not caught live: the two lanes in the same sampled instant** (Step 3/4's
  simultaneous "both bars advancing"). An 11-photo batch drains its
  preview+evaluation pipeline in ~1–2s, inside ssh-per-sample latency and
  below the confirmation-sheet scan/ingest start delay; a wider fixture was
  blocked by VM disk space. This transient overlap IS proven by this branch's
  headless `lane-overlap` verifier (`script/verify_lane_overlap.sh`,
  RED-tested by forcing `maxDispatchedCommandCount: 1`) which drives the real
  worker binary + supervisor + catalog. Re-run with a larger synced fixture
  (free VM disk first) to catch it live.
- **Not run: per-kind cancel (Step 5)** — the 11-photo drain finishes before
  the cancel can be issued; needs the wider fixture. Covered by unit tests
  (`SupervisorPerItemCancelTests`).
- Harness fix made during this run: `script/submit_import_path.sh` embedded
  the Swift AX driver as a single-quoted `swift -e '...'` argument, and
  recently-added comments contained apostrophes that closed the string
  (parse error under any shell) — rephrased apostrophe-free.

Authored 2026-07-13, source-cited against the
`feat/parallel-worker-lanes` branch: lane-concurrency construction
(`Sources/TeststripApp/AppCatalog.swift:35-43,125-132`), per-item cancel
semantics (`Sources/TeststripCore/Worker/WorkerSupervisor.swift:195-211`),
the per-kind Activity projection
(`Sources/TeststripApp/ActivityCenterPresentation.swift:72-139`,
`Sources/TeststripApp/AppModel.swift:2783-2836`), and the auto-evaluation
trigger that makes both lanes fire off a single import
(`Sources/TeststripApp/AppModel.swift:8788-8802,9025-9043`). Cross-checked
against this branch's own headless lane-overlap verifier
(`script/verify_lane_overlap.sh`, `script/lane_overlap_verifier_metrics.sh`,
`Sources/TeststripBench/LaneOverlapSmoke.swift`) for the "overlap" definition
used in Step 4, though that harness drives the worker binary directly rather
than through the live AX-driven app — this card is the live-UI counterpart
the spec's own testing section calls for ("E2E scenario card (VM)").
Pending a live VM run per `test/scenarios/README.md`.
