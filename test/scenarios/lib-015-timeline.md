# lib-015-timeline: year ribbon / scrubber / sections track the loaded assets and drive scroll-to-focus

**What this covers**: the Library workspace's Timeline sub-view
(`TimelineWorkspaceView` in `Sources/TeststripApp/LibraryGridView.swift:6753`)
— the year ribbon (`timelineYearRibbon`), the month/day scrubber
(`timelineMonthDayScrubber`), the day/month sections rendered in the scroll
body, and the autoscroll-to-focus wiring
(`TimelineContentScrollPolicy.focusedTargetID`, driven by
`.onChange(of:)` at `LibraryGridView.swift:6789`). Clicking a year bar calls
`AppModel.selectTimelineYear`, clicking a month calls `selectTimelineMonth`,
clicking a day calls `selectTimelineDay` — each narrows
`captureDateStartFilter`/`captureDateEndFilter` and reloads
(`AppModel.swift:8860-8871`), which should scroll the body to the new focus
target without a manual scroll gesture.

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
**`--smoke`'s 24 assets are NOT date-varied enough for a real multi-year year
ribbon.** `Sources/TeststripBench/SmokeCatalogSeeder.swift:105` sets
`capturedAt = Date(timeIntervalSince1970: 1_704_067_200 + index * 900)` —
all 24 assets land within a single ~6-hour window on 2024-01-01. This is
enough to exercise one month/one day section and the scrubber, but the year
ribbon will show a single year bar with a single tick — it cannot prove
multi-year bucketing this way. Confirm the exact spread before driving:
```bash
sqlite3 "$DB" "SELECT date(json_extract(technical_metadata_json,'\$.capturedAt')) AS d, count(*) FROM assets GROUP BY d;"
```
If multi-year/multi-month coverage is needed to assert the ribbon's bucketing
math (not just presence), re-seed with `--sample-photos` or `--real-corpus`
instead and re-verify the date spread the same way — do not assume either
seeds enough variety without checking.

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; press ⌘2 for Library.
2. Switch to the Timeline sub-view (the Grid/Loupe/Timeline/Map picker
   documented at `LibraryGridView.swift:449`, `Text("Timeline")`).
3. Assert the year ribbon is present with at least one year bar, and the
   scrubber shows the corresponding month(s) with a focused month
   highlighted (`isFocused` per `TimelinePresentation.scrubber`).
4. Assert a day/month section is visible in the scroll body
   (`monthSection`/`daySection`) showing the seeded assets, and the
   `timelineMetric` counts ("Months", "Loaded") match
   `SELECT count(*) FROM assets` for Loaded (all 24 load with `--smoke`,
   no pagination gate).
5. Click a different month row in the scrubber (or a different year bar if
   multiple exist). Assert: (a) the clicked month/year becomes focused
   (`isFocused` reflected as the highlighted row), and (b) the scroll body
   auto-scrolls to that month's section without an explicit scroll gesture —
   confirm by checking the target `AXGroup`/section (`id`
   `timeline-month-<key>` per `TimelineContentScrollPolicy.monthTargetID`) is
   the frontmost visible element after a short wait, not requiring a manual
   scroll.
6. Click a day row/day section header. Assert `selectTimelineDay` fires
   (`captureDateStartFilter`/`captureDateEndFilter` narrow to that single day)
   — cross-check by reading `model.assets` count via the "Loaded" metric,
   which should now equal that day's `assetCount`.

## Expected
- Step 3: year ribbon renders with `≥1` bar; scrubber's focused month matches
  the most recent asset's month per `TimelinePresentation.focusedMonthID`.
  **Fails if** the ribbon is empty despite dated assets present in the
  catalog (ingest → presentation break).
- Step 5: **Fails if** clicking a scrubber row changes the model's selection
  (`selectTimelineMonth`/`selectTimelineYear` do run) but the scroll body does
  not follow — i.e. the `onChange(of: focusedTargetID)` autoscroll wiring at
  `LibraryGridView.swift:6789` is broken and the user has to scroll manually.
- Step 6: **Fails if** the "Loaded" count doesn't drop to the selected day's
  count, meaning `selectTimelineDay` didn't apply the date-range filter.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- The Timeline view is one of the surfaces gated behind
  `.liveMockupPlaceholder(.timelineLibrary)` (`LibraryGridView.swift:6785`) —
  if that placeholder is currently active for this build, the scenario as
  written can't be driven; check for a placeholder overlay before assuming a
  broken wiring.
- `TimelineWorkspaceView` also drives no-cull-chrome behavior alongside Map
  and People (`LibraryGridView.swift:4481`); this card only covers the
  Timeline-specific ribbon/scrubber/scroll behavior, not the chrome-suppression
  assertion (that belongs to a chrome-focused card).

## Run status
NOT YET RUN — headless SQL/source verification only (`--smoke` seed spread
confirmed against `SmokeCatalogSeeder.swift:105`: single-day, ~6-hour spread
across 24 assets, 900s apart). No live AX drive performed this session
(no-live-GUI constraint). Needs a human-present or VM re-run per
`test/scenarios/README.md`'s Tart-VM section.
