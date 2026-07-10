# inspect-002-info-identity-exif: Info tab preview, identity header, read-only summary, and conditional EXIF rows

**What this covers**: the Info tab's read-surface — the cached preview image,
the filename/extension/captured-date identity header, the read-only
rating/flag/label summary (distinct from Describe's editable buttons — see
inspect-005 for that split), and EXIF/technical-metadata rows that only
render when the underlying `AssetTechnicalMetadata` has values (no EXIF ⇒ no
"Technical" section at all).

## Pre-state
```bash
./script/build_and_run.sh --smoke
ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
DB="$ISOLATED/Teststrip/catalog.sqlite"
```
Pick a target and inspect its stored technical metadata. Confirmed by dry-run
against a fresh `--smoke` catalog: **all 24 smoke assets have non-null
`technical_metadata_json`** with `cameraMake`, `cameraModel`, `lensModel`,
`isoSpeed`, `pixelWidth`/`pixelHeight`, and `capturedAt` populated, but
**none carry `aperture`, `shutterSpeed`, or `focalLength`** — so `--smoke`
alone cannot exercise the fully-absent-EXIF branch (no technical metadata at
all) or the aperture/shutter/focal-length rows; it can only exercise
"Technical section present, subset of rows shown":
```bash
sqlite3 "$DB" "SELECT id, original_path, metadata_json, technical_metadata_json FROM assets ORDER BY id LIMIT 1;"
SRC=$(sqlite3 "$DB" "SELECT original_path FROM assets ORDER BY id LIMIT 1;")
```

## Steps
1. `script/ax_drive.sh wait-vended Teststrip`; ⌘2 for Library; select `$SRC`'s
   grid cell; ⌘I to open the inspector (lands on Info by default, or press
   ⌥⌘1 to force it).
2. **Preview.** Assert an image renders in the preview area
   (`ax_drive.sh find --role AXImage` or the accessibility label "Selected
   preview" per `InspectorView.swift:680`).
3. **Identity header.** Assert the header shows `$SRC`'s basename (minus
   extension) as the display name, and — if the extension is non-empty — an
   uppercase extension badge (e.g. "JPG") per `InspectorAssetIdentity.init`
   (`InspectorView.swift:21-32`). Assert the accessibility value combines
   availability + rating text (`identity.accessibilityValue`,
   `InspectorView.swift:30`).
4. **Read-only rating/flag/label summary.** Cross-check against the catalog:
   ```bash
   sqlite3 "$DB" "SELECT metadata_json FROM assets WHERE original_path='$SRC';"
   ```
   Assert the Info tab's summary line (accessibility label "Rating, flag, and
   label", `InspectorView.swift:638-648`) reads consistently — e.g. a
   `"rating":3` asset shows `★★★` via `ratingDisplayText` (`:650-652`), a
   `"flag":"pick"` asset shows "Pick" via `flagDisplayText` (`:654-660`), and
   `"colorLabel":"blue"` shows "Blue" via `labelDisplayText` (`:662-664`).
5. **This summary is read-only in Info.** Assert there are no star/flag/label
   *buttons* in the Info tab (`ax_drive.sh find --role AXButton --help "Rate
   3"` should find nothing while on the Info tab) — those live only in
   Describe (`elementsByTab[.info]` has `.ratingDisplay`, not
   `.ratingEditButtons`; see inspect-001 step 7-8 for the tab split, and
   inspect-005 for exercising the editable buttons).
6. **EXIF rows.** `$SRC` has non-null `technical_metadata_json` (true for all
   24 smoke assets); assert a "Technical" section renders with a
   "Dimensions" row always present (`InspectorTechnicalRows.init`,
   `InspectorView.swift:93-96`), Camera/Lens/ISO/Captured rows present
   (matching the smoke seeder's populated fields), and **no** Aperture,
   Shutter Speed, or Focal Length rows (smoke fixtures never populate those
   three) — cross-check each present row's value against the
   `technical_metadata_json` column read in Pre-state. This exercises the
   conditional-row logic on the fields smoke *does* vary, but not the
   fully-absent-EXIF path (`infoTabBody`'s `if let technicalMetadata =
   asset.technicalMetadata`, `InspectorView.swift:610-612`) or the
   aperture/shutter/focal rows — flagged as a fixture gap in Sharp edges.

## Expected
- Step 2: preview image present. **Fails if** the preview area is blank for a
  selected asset with a generated preview.
- Step 3: display name and extension badge match `$SRC`'s filename exactly.
  **Fails if** the header shows the full filename including extension as the
  display name (extension should be stripped into the badge), or omits the
  badge for a non-empty extension.
- Step 4: summary text matches the catalog's `metadata_json` rating/flag/color
  fields exactly via the documented display-text mapping. **Fails if** the
  summary shows a stale or default value that doesn't match the DB.
- Step 5: zero rating/flag/label edit buttons found while on Info.
  **Fails if** Describe's edit controls leak into Info (an anti-orphan
  regression — see inspect-001 step 7-8's tab-isolation check).
- Step 6: "Technical" section renders with Dimensions/Camera/Lens/ISO/Captured
  rows and no Aperture/Shutter Speed/Focal Length rows. **Fails if** a row
  renders for a field smoke never populates, a populated field's row is
  missing, or the section fails to render at all.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- **Fixture gap**: `--smoke` cannot exercise the fully-absent-`technicalMetadata`
  branch (all 24 assets have it populated) or the Aperture/Shutter
  Speed/Focal Length rows (none of the 24 populate `aperture`,
  `shutterSpeed`, or `focalLength`). A future card or fixture update using
  `--sample-photos`/`--real-corpus` (real camera EXIF) would be needed to
  cover those; documenting the gap here per README.md's fixture-status
  convention rather than silently skipping it.
- `ratingText` in the identity header (`InspectorView.swift:29`,
  `"Rating: \(asset.metadata.rating)"`) is a *different* string than the
  star-glyph summary line (`ratingDisplayText`) — both are legitimately
  present and should not be conflated when asserting step 3 vs step 4.

## Run status
BLOCKED-CONSOLE — locked console prevents any AX step. Wiring confirmed
statically: `Sources/TeststripApp/InspectorView.swift:12-37`
(`InspectorAssetIdentity`), `:604-614` (`infoTabBody`), `:638-664`
(`metadataDisplaySummary`, `ratingDisplayText`/`flagDisplayText`/
`labelDisplayText`), `:90-126` (`InspectorTechnicalRows`, conditional row
construction), `:1179-1187` (`technicalMetadataView`, only called when
`asset.technicalMetadata` is non-nil). Needs a human-present re-run. All SQL
in this card was run headlessly against a seeded --smoke catalog on
2026-07-10 (schema per Sources/TeststripCore/Catalog/CatalogMigrations.swift);
the smoke catalog's `technical_metadata_json` values were inspected directly
(all 24 assets, confirming camera/lens/ISO present and aperture/shutter/focal
absent) before finalizing this card.
