# cull-007-exif-overlay-cycle: I cycles the loupe's EXIF overlay through off/exposure/full

**What this covers**: as a photographer checking exposure and focal length
without leaving the loupe, I want `I` to cycle a compact overlay through
off → exposure summary → full technical detail → back to off, so I can
glance at camera/lens/ISO/aperture/shutter and, when I need more, pixel
dimensions/GPS/capture date, without opening the inspector. Covers item 24.

Source:
- `Sources/TeststripApp/AppModel.swift:406-417` — `ExifOverlayLevel` (`.off`,
  `.exposureLine`, `.full`), cycled by `.next()`.
- `Sources/TeststripApp/AppModel.swift:5445-5446` — the `I` shortcut
  (`CullingShortcut.cycleExifOverlay`, keyed at `:256`) calls
  `exifOverlayLevel = exifOverlayLevel.next()`.
- `Sources/TeststripApp/LibraryGridView.swift:4283-4291` — the loupe metadata
  strip renders `LoupeExifOverlayPresentation(technicalMetadata:level:).lines`
  as a stack of `Text` rows (each its own AX static text).
- `Sources/TeststripApp/LibraryGridView.swift:8520-8562` —
  `LoupeExifOverlayPresentation`: `.off` → `[]`; `.exposureLine` → one line
  from `LoupeExifSummaryPresentation` (camera make+model, lens, `"ISO N"`,
  aperture, shutter speed, focal length — joined with `" · "`,
  `:8479-8510`); `.full` → the exposure line **plus** `"<w> × <h>"` pixel
  dimensions, a `"<lat>, <lon>"` line if GPS is present, and a formatted
  capture-date line if present.

## Pre-state
```bash
./script/build_and_run.sh --smoke
script/ax_drive.sh wait-vended Teststrip
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
`--smoke` frames have `technical_metadata_json` populated **directly by the
seeder** (`Sources/TeststripBench/SmokeCatalogSeeder.swift:119-134`), not
synthesized at import — every smoke asset carries `cameraMake: "Teststrip"`,
`cameraModel: "SmokeCam <1..3>"`, `lensModel: "<35|50|65|80>mm"`,
`isoSpeed`, `pixelWidth: 1200`/`pixelHeight: 800`, and `capturedAt`. It does
**not** set `aperture`, `shutterSpeed`, `focalLength` (lensModel is used as a
free-text lens label, not the numeric focal-length field), or
`latitude`/`longitude` — so the exposure-summary line will read
`"Teststrip SmokeCam N · <k>mm · ISO <v>"` (camera+lens+ISO only, no
aperture/shutter terms) and the full overlay adds pixel dims and a date but
**no GPS line**. Pick an asset id up front:
```bash
ASSET=$(sqlite3 "$DB" "SELECT id FROM assets ORDER BY id LIMIT 1;")
sqlite3 "$DB" "SELECT json_extract(technical_metadata_json,'\$.cameraModel'), json_extract(technical_metadata_json,'\$.lensModel'), json_extract(technical_metadata_json,'\$.isoSpeed') FROM assets WHERE id = '$ASSET';"
```
to know the exact strings ("SmokeCam N", "<k>mm", ISO N) the overlay must
render for that asset, before driving the UI.

## Steps
1. Open the loupe on `$ASSET` (⌘1 Cull, select, Return).
2. Confirm the overlay starts at `.off` — no EXIF text row should exist:
   `script/ax_drive.sh find --role AXStaticText --contains "ISO"` should not
   match. (`exifOverlayLevel` is app-model state that resets each launch,
   default `.off`.)
3. Press `I` once (exposure line). Assert the exposure line is present:
   `script/ax_drive.sh wait --role AXStaticText --contains "ISO"` (matches
   the `"ISO <n>"` component) **and** `--contains "SmokeCam"` (camera
   component). Assert the full-only fields are **not** present:
   `script/ax_drive.sh find --role AXStaticText --contains "1200"` should
   not match (pixel-dimension line only appears at `.full`).
4. Press `I` again (full). Assert the pixel-dimension line now appears:
   `script/ax_drive.sh wait --role AXStaticText --contains "1200 × 800"`.
   The exposure-line fields from step 3 (`"ISO"`, `"SmokeCam"`) should still
   be present — `.full` is additive, not a replacement.
5. Press `I` a third time (back to off). Assert both the exposure text and
   the pixel-dimension text are gone: `script/ax_drive.sh find --role
   AXStaticText --contains "ISO"` and `--contains "1200 × 800"` should both
   fail to match.

## Expected
- Step 2: no EXIF text visible before the first `I` press.
- Step 3: exposure-only fields visible (`"ISO"`, `"SmokeCam"`); full-only
  field (`"1200 × 800"`) absent. **Fails if** the pixel-dimension line
  already appears at `.exposureLine` (level boundaries wrong) or if no EXIF
  text appears at all (cycle didn't advance, or `technical_metadata_json`
  wasn't read).
- Step 4: pixel-dimension line appears **in addition to** the exposure
  fields. **Fails if** the exposure fields disappeared (full replaces rather
  than extends) or the pixel-dimension line never appears.
- Step 5: overlay fully empty again. **Fails if** any EXIF text row
  persists — the three-state cycle didn't wrap back to `.off`.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **No GPS line to assert against `--smoke`.** The smoke seeder never sets
  `latitude`/`longitude`, so this card cannot exercise the GPS-line branch of
  `.full` (`LibraryGridView.swift:8536-8538`). If a GPS-line assertion is
  wanted, re-run against `--faces` or `--sample-photos` instead and confirm
  which seeded frames actually carry EXIF GPS tags (not guaranteed for the
  Wikimedia Commons portraits in `sample-data/photos/faces` — check
  `technical_metadata_json` per-asset before relying on it).
- `--contains "ISO"` is a loose substring match; if any other loupe chrome
  ever renders the literal text "ISO" outside the EXIF overlay this
  assertion could false-positive. Verified against current source that no
  other `Text` view in the loupe metadata strip does.
- The exact capture-date formatting (`DateStyle: .medium, TimeStyle: .short`,
  `LibraryGridView.swift:8556-8560`) is locale-dependent; this card doesn't
  assert on the date line's exact text for that reason, only on the
  presence of the pixel-dimension line as the `.full`-only signal.

## Run status
UNRUN — needs human-present execution per test/scenarios/README.md.
