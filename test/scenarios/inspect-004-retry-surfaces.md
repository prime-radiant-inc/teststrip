# inspect-004-retry-surfaces: Preview-retry and provider-failure retry actually re-queue work

**What this covers**: the two failure-recovery surfaces in the inspector —
the Info tab's preview-retry button (`previewFailureStatus`) and the AI tab's
provider-failure retry button (`providerFailureStatus`, "Retry
`<provider>`") — asserting each click **re-queues the failed work** (a
`preview_generation_queue` / `evaluation_failures` row actually changes
state), not merely that the button's own enabled/disabled state flips.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
ASSET_ID=$(sqlite3 "$DB" "SELECT id FROM assets WHERE original_path='$SRC';")
```
Both `preview_generation_queue` and `evaluation_failures` are empty on a
fresh `--smoke` catalog (confirmed by dry-run). Neither failure state is
naturally reachable through the UI within a short scenario window (a real
preview/provider failure requires an actual I/O or provider error), so this
card **synthesizes the failure row directly via SQL** — a legitimate probe
of the retry *wiring*, since the button's presence/enablement and the retry
handler both read this table, independent of how the row got there. Schemas:
```sql
CREATE TABLE preview_generation_queue (
    asset_id TEXT NOT NULL, level TEXT NOT NULL,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT, last_attempted_at REAL, updated_at REAL NOT NULL,
    PRIMARY KEY (asset_id, level)
);
CREATE TABLE evaluation_failures (
    asset_id TEXT NOT NULL, provider TEXT NOT NULL, message TEXT NOT NULL,
    failed_at REAL NOT NULL, updated_at REAL NOT NULL,
    PRIMARY KEY (asset_id, provider)
);
```

## Steps

### Preview retry (Info tab)
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 Library; select `$SRC`; ⌘I
   to Info tab.
2. **Quit the app**, then insert a synthetic failure row so it's present on
   next launch (the running instance's in-memory `assets`/queue state
   wouldn't reflect a row inserted underneath it):
   ```bash
   sqlite3 "$DB" "INSERT INTO preview_generation_queue (asset_id, level, attempt_count, last_error, last_attempted_at, updated_at) VALUES ('$ASSET_ID', 'full', 2, 'synthetic I/O error for inspect-004', strftime('%s','now'), strftime('%s','now'));"
   ```
3. Relaunch against the same isolated dir
   (`TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="$ISOLATED" open dist/Teststrip.app`
   — confirm the exact relaunch invocation `build_and_run.sh` uses for
   reattaching to an existing isolated dir, since a bare re-run of
   `--smoke` mints a *new* isolated dir per README.md). Select `$SRC`, Info
   tab.
4. Assert the "Preview retry pending" alert renders (`previewFailureStatus`,
   `InspectorView.swift:748-767`) with the synthetic error text visible, and
   a "Retry" button.
5. Click Retry (`ax_drive.sh press --role AXButton --label "Retry"` — Info
   tab has only one Retry button unless the sync-pending state is also
   showing; disambiguate by position/help if both are present).
6. Assert on disk: the `preview_generation_queue` row for
   `('$ASSET_ID','full')` is gone or its `attempt_count`/`last_attempted_at`
   changed (re-queued and, once the worker actually regenerates the preview,
   deleted) — poll:
   ```bash
   sqlite3 "$DB" "SELECT * FROM preview_generation_queue WHERE asset_id='$ASSET_ID' AND level='full';"
   ```

### Provider-failure retry (AI tab)
7. Insert a synthetic evaluation failure (same quit-and-reinsert pattern as
   step 2, since this is also read into the in-memory model at launch):
   ```bash
   sqlite3 "$DB" "INSERT INTO evaluation_failures (asset_id, provider, message, failed_at, updated_at) VALUES ('$ASSET_ID', 'apple-vision', 'synthetic provider error for inspect-004', strftime('%s','now'), strftime('%s','now'));"
   ```
8. Relaunch; select `$SRC`; ⌥⌘3 for AI tab.
9. Assert "Provider retry needed" alert renders (`providerFailureAlert`,
   `InspectorView.swift:740-746`) with "apple-vision failed: synthetic
   provider error..." text and a **"Retry apple-vision"** button
   (`InspectorProviderFailurePresentation.actionLabel`,
   `InspectorView.swift:85-87`).
10. Click "Retry apple-vision" (`model.retrySelectedProviderFailure(provider:
    "apple-vision")`, `AppModel.swift:7596-7602`, which calls
    `requestEvaluation(assetID:provider:)` to re-enqueue the provider run).
11. Assert on disk the `evaluation_failures` row for
    `('$ASSET_ID','apple-vision')` is gone (cleared on re-enqueue or on the
    subsequent successful run — poll and note which):
    ```bash
    sqlite3 "$DB" "SELECT * FROM evaluation_failures WHERE asset_id='$ASSET_ID' AND provider='apple-vision';"
    ```

## Expected
- Step 4: preview-retry alert renders with the synthetic error text and an
  enabled Retry button (`canRetrySelectedPreviewGenerationFailures` true when
  the original is available, `AppModel.swift:2424`). **Fails if** the alert
  doesn't render for a real queued-failure row, or Retry is disabled with no
  reason.
- Step 6: the `preview_generation_queue` row is mutated/cleared by the click
  — this is the load-bearing assertion; a UI-only "it looked like it
  worked" is not sufficient. **Fails if** the row is byte-identical after
  the click (the button changed its own state but never touched the queue).
- Step 9: AI-tab alert renders "Retry apple-vision" (exact provider name in
  the label, not a generic "Retry"). **Fails if** the label is generic or
  the alert doesn't render.
- Step 11: `evaluation_failures` row is cleared/re-queued by the click.
  **Fails if** it's unchanged.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Synthetic induction caveat**: since neither failure table has rows on a
  fresh smoke seed and no existing script forces a real preview/provider
  failure, this card injects rows directly via SQL rather than driving a
  real failure end-to-end. This proves the retry *wiring* reads the table
  and re-queues on click, but does not prove the original failure-detection
  path (I/O error → row insert) works — that would need a dedicated fixture
  (e.g. a corrupted/unreadable original) and is a separate gap worth a
  follow-up card if Jesse wants that half covered too.
- Quitting and relaunching between the SQL insert and the assertion is
  necessary because `AppModel` holds `selectedPreviewGenerationFailures` /
  `selectedProviderFailures` as computed properties over in-memory state
  refreshed from the catalog at specific points, not a live SQL subscription
  — confirm the actual refresh trigger (`refreshCatalogSidebarCounts` and
  friends) once live; a mid-session poll/refresh action might substitute for
  a full relaunch and would be faster to iterate with.
- Step 3's relaunch invocation needs verifying against `script/build_and_run.sh`'s
  actual flag for reattaching to an existing isolated dir vs. minting a new
  one — read the script before running this card for real.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed
statically: `Sources/TeststripApp/InspectorView.swift:748-767`
(`previewFailureStatus`, Retry → `model.retrySelectedPreviewGenerationFailures`),
`:740-746,769-788` (`providerFailureAlert`/`providerFailureStatus`, Retry
`<provider>` → `model.retrySelectedProviderFailure`),
`:70-88` (`InspectorProviderFailurePresentation`),
`Sources/TeststripApp/AppModel.swift:7250-7257`
(`retrySelectedPreviewGenerationFailures`, re-enqueues via `requestPreview`
with `.front` placement), `:7596-7601` (`retrySelectedProviderFailure`,
re-enqueues via `requestEvaluation`), `Sources/TeststripCore/Catalog/CatalogRepository.swift:1522-1567`
(`recordEvaluationFailure`, the failures table's insert/delete/query shape).
Needs a human-present re-run. All SQL and schema in this card were run
headlessly against a seeded --smoke catalog on 2026-07-10 (schema per
Sources/TeststripCore/Catalog/CatalogMigrations.swift); both failure tables
confirmed empty on a fresh smoke seed.
