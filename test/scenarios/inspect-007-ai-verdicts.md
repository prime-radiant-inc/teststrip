# inspect-007-ai-verdicts: AI tab's plain-English verdict groups and technical disclosure

**What this covers**: the AI tab's "What Teststrip sees" panel — signals
grouped into 5 plain-English sections (Technical Quality, Faces, Text,
Objects & Content, Color & Look), each row showing a human verdict word
(e.g. "Sharp", "Well exposed") rather than a raw score, plus a collapsed
"Technical details" disclosure that reveals the raw signal values and their
provenance (model/provider names) on demand.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`evaluation_signals` is empty on a fresh `--smoke` catalog (no eval has run
yet) — confirm:
```bash
sqlite3 "$DB" "SELECT count(*) FROM evaluation_signals;"
```
The AI tab needs at least one asset with evaluation signals to show anything
beyond an empty state, so evaluation must run first (via the app's normal
evaluate action, not synthetic SQL — the signals are provider-shaped JSON
this card shouldn't hand-fabricate).

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 Library.
2. Trigger evaluation over the visible scope (menu action or keyboard
   shortcut per the app's existing evaluate flow — see
   `import-cull-pick-happy-path.md` for the established "auto-evaluate"
   pattern). Wait for the Activity indicator to go idle
   (`script/verify_people_clustering.sh`'s "keep it warm during long waits"
   pattern — re-assert frontmost on every poll).
3. Confirm on disk that at least one asset now has rows:
   ```bash
   sqlite3 "$DB" "SELECT asset_id, kind, value_json, provenance_json FROM evaluation_signals LIMIT 20;"
   ```
   Pick `SRC` = the `original_path` for an `asset_id` with several signal
   kinds represented (ideally spanning focus/exposure and at least one
   non-technical kind like an object label, for a richer group count).
4. Select `$SRC`'s grid cell; ⌥⌘3 for the AI tab.
5. **Verdict groups.** Assert the panel header "What Teststrip sees" renders
   (`evaluationSignals`, `InspectorView.swift:1208-1217`), and that rows are
   grouped under a subset of the 5 possible section titles — "Technical
   Quality", "Faces", "Text", "Objects & Content", "Color & Look"
   (`InspectorEvaluationSignalGroup.groupOrder`,
   `InspectorView.swift:202-208`) — matching exactly which
   `EvaluationKind`s `$SRC` has signals for (`groupTitle(for:)`,
   `:210-223`). A group with zero rows must not render at all
   (`InspectorEvaluationSignalGroup.groups(for:)` compactMaps empty groups
   out, `:196-200`).
6. **Plain-English verdicts, not raw scores.** For a focus/exposure/motion-
   blur/aesthetics/framing/faceQuality/eyesOpen/smile/novelty row, assert
   the *row text itself* (not the disclosure) shows a verdict word — e.g.
   "Sharp"/"Slightly soft"/"Soft" for focus,"Well exposed"/"Dark"/"Bright"
   for exposure — per `SignalVerdict.text(for:score:)`
   (`InspectorView.swift:144-181`), not the raw `%.2f` float. Cross-check the
   verdict word against the stored `value_json` score using the exact
   thresholds in `SignalVerdict.band`/`.exposure` (0.66/0.4 for most kinds,
   0.38/0.66 for exposure).
7. For a kind with no verdict mapping (object, ocrText, faceCount,
   colorPalette, visualSimilarity — `SignalVerdict.text` returns nil for
   these, `:172-174`), assert the row instead shows the raw `value` text
   (label/text/count, `row.verdict ?? row.value`, `InspectorView.swift:1229`)
   since there's no plain-English rewrite for those kinds.
8. **Technical disclosure.** Assert the "Technical details" DisclosureGroup
   is present but collapsed by default (`isShowingSignalDetails` starts
   `false`, `InspectorView.swift:547`). Click to expand
   (`ax_drive.sh press --role AXDisclosureTriangle --label "Technical
   details"` or equivalent).
9. Assert the expanded content shows, per signal row, the raw value **and**
   provenance: `"\(row.title): \(row.value) · \(row.detail)"`
   (`InspectorView.swift:1240-1244`), where `detail` is
   `"\(confidenceText) - \(provider)/\(model)"` (`confidenceText` already
   includes its own `%`, e.g. `"82%"`)
   (`InspectorEvaluationSignalGroup.row(for:index:)`, `:225-239`). Cross-check
   the provider/model strings against `provenance_json` for that signal in
   the DB dump from step 3 — they must match exactly (this is the
   provenance-disclosure half of the assertion, not just "some text
   appeared").
10. Collapse the disclosure again; assert the raw/provenance text
    disappears while the verdict-word summary rows remain visible.

## Expected
- Step 5: only non-empty groups render, titled from the fixed
  `groupOrder` list, matching `$SRC`'s actual signal kinds. **Fails if** an
  empty group renders, or a group's title doesn't match `groupTitle(for:)`'s
  mapping for the signals present.
- Step 6: verdict words match the documented score thresholds exactly for
  `$SRC`'s stored scores. **Fails if** a raw float leaks into the summary
  row, or the verdict word doesn't match the threshold band the stored score
  falls into.
- Step 7: label/text/count-valued rows show the raw value with no verdict
  word (since none exists) — this is expected, not a bug. **Fails if** the
  card mistakenly flags this as a defect.
- Step 8-9: disclosure starts collapsed; expanding it reveals raw values and
  exact provider/model provenance matching the DB. **Fails if** provenance
  is missing, generic ("Unknown"), or doesn't match `provenance_json`.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- This card depends on a real evaluation run completing against `--smoke`
  assets, which takes real wall-clock time and worker warmth — budget for
  that in a live run and keep the app frontmost throughout per
  `test/scenarios/README.md`'s idle-wedge warning.
- Which of the 5 groups actually populate depends on which providers ran
  during evaluation (`--smoke`'s default evaluate scope) — confirm via the
  step 3 dump which groups are reachable before asserting all 5 in one pass;
  it's plausible only Technical Quality and Faces are populated for smoke's
  synthetic (non-photographic) fixtures, in which case Text/Objects &
  Content/Color & Look would need a richer corpus
  (`--sample-photos`/`--real-corpus`) to exercise — note this explicitly if
  confirmed on the live run rather than assuming all 5 fire.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step; additionally this
card was not dry-run against live evaluation signals (no eval has been
triggered against the running smoke instance in this session, so the exact
signal kinds/scores/provenance available on `--smoke` are unconfirmed —
`evaluation_signals` was confirmed *empty* pre-evaluation but not populated
and re-queried). Wiring confirmed statically:
`Sources/TeststripApp/InspectorView.swift:128-281`
(`InspectorEvaluationSignalRow`, `SignalVerdict`,
`InspectorEvaluationSignalGroup`, group/verdict/provenance construction),
`:624-633` (`aiTabBody`), `:1208-1261` (`evaluationSignals` view, the
DisclosureGroup). Needs a human-present re-run, including a real evaluation
pass to populate `evaluation_signals` before the AX steps can be driven. All
SQL in this card was run headlessly against a seeded --smoke catalog on
2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift);
`evaluation_signals` confirmed empty pre-evaluation.
