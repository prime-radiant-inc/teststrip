# Auto-Rotation: Detect and Rotate

## Setup

- `--isolated` with `--sample-photos` seeded with at least one sideways photo
  (a photo whose EXIF orientation is correct but the content is visually
  rotated 90°)
- If no sideways sample is available, the scenario still verifies manual
  rotation via ⌘[/⌘]

## Steps

1. Launch the app in the Tart VM via `script/vm_scenario_run.sh`
2. Wait for import to complete and evaluations to settle
3. Open the loupe on the first photo
4. Verify the photo is displayed (no crash, no blank state)

## Manual Rotation Verification

5. Press `⌘]` (Rotate Right) — verify the image rotates 90° clockwise
6. Press `⌘]` again — verify 180°
7. Press `⌘]` again — verify 270°
8. Press `⌘]` again — verify back to original (0°, wraps)
9. Press `⌘[` (Rotate Left) — verify 270° (wraps counter-clockwise)
10. Press `⌘[` again — verify 180°

## Catalog Ground Truth

11. Query the catalog:
    ```sql
    SELECT id, json_extract(technical_metadata_json, '$.rotation') AS rotation
    FROM assets LIMIT 5;
    ```
12. Verify the selected asset has a non-null rotation after step 5

## XMP Sidecar

13. Check for sidecar file next to the source:
    ```bash
    ls "$ISOLATED/Teststrip/"*.xmp 2>/dev/null
    ```
14. Verify `ts:Rotation` attribute is present in the sidecar:
    ```bash
    grep "ts:Rotation" "$ISOLATED/Teststrip/"*.xmp
    ```

## Auto-Detection (if sideways sample exists)

15. After import + evaluation settle, query the catalog for auto-detected
    rotation:
    ```sql
    SELECT id, json_extract(technical_metadata_json, '$.rotation') AS rotation
    FROM assets WHERE json_extract(technical_metadata_json, '$.rotation') IS NOT NULL;
    ```
16. Verify at least one asset has a rotation value from auto-detection

## Pass Criteria

- ⌘[/⌘] rotation works in the loupe (visual rotation applied immediately)
- Catalog ground truth shows the rotation value
- XMP sidecar contains `ts:Rotation` when rotation is non-zero
- No crashes
