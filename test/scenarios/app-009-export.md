# app-009-export: Export copies with presets and an optional EXIF/IPTC carry

**What this covers**: Jesse exports finished picks for delivery; the copies
must actually be resized and the metadata carry must obey the checkbox.
Inventory items 31-33: one export flow shared by File ▸ Export…, the toolbar
button, and the end-of-set surface via `exportRequestToken`
(`Sources/TeststripApp/main.swift` FileCommands, `AppModel.requestExport`);
the review sheet's scope picker (selected/visible/current scope) + confirm,
JPEG/PNG, quality, EXIF/IPTC toggle, long edge; and `ExportService` dedupe,
filename de-collision, progress, with the `TESTSTRIP_EXPORT_DESTINATION_DIR`
override. Concretely: the toolbar **Export** popover, its
Format/Quality/Long-edge settings, presets, and the **"Include EXIF/IPTC
metadata"** checkbox (`includeSourceMetadata`, Jesse's explicit ask: EXIF/IPTC
optional, checkbox at export). The load-bearing assertions are on the exported
files: a resized JPEG is actually written at the requested long edge, and the
EXIF/IPTC checkbox governs whether metadata rides along — checked carries it,
unchecked strips it.

## Pre-state
- Fresh build, isolated catalog:
  ```bash
  ./script/build_and_run.sh --smoke
  ISOLATED=$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)
  ```
- Scratch export destination: `OUT=$(mktemp -d)/export` (let the app create it).
  Launch with the typed-path destination override so the native folder panel is
  bypassed deterministically:
  ```bash
  OUT=$(mktemp -d)/export
  TESTSTRIP_EXPORT_DESTINATION_DIR="$OUT" ./script/build_and_run.sh --smoke
  ```
  For the second (metadata-OFF) export to a distinct `OUT2`, relaunch with
  `TESTSTRIP_EXPORT_DESTINATION_DIR="$OUT2"`, or drive the native panel via AX.
- At least one photo visible in the grid.

## Steps
1. **Open Export.** `script/activate_app.sh Teststrip`; AX-press the toolbar
   button labeled **"Export"**. `waitFor` an `AXStaticText` **"Export Photos"**.
2. **Set a resize + carry metadata ON.** In the popover: leave Format = JPEG,
   type `1024` into the **"Long edge"** field, and ensure the checkbox
   **"Include EXIF/IPTC metadata"** is CHECKED (read its AX value; toggle if
   needed).
3. **Run the export.** AX-press the export confirm button (the popover's
   primary action; its label is the presentation `exportTitle`, e.g.
   "Export N"). In the native destination panel, Cmd+Shift+G → `$OUT` → confirm.
   `waitFor` the export to report completion (progress clears / success text).
4. **Assert a resized JPEG landed with metadata**:
   ```bash
   F=$(ls "$OUT"/*.jpg "$OUT"/*.jpeg 2>/dev/null | head -1); echo "$F"
   sips -g pixelWidth -g pixelHeight "$F"          # long edge must be 1024
   sips -g hasAlpha "$F" >/dev/null && echo "readable jpeg"
   /usr/bin/mdls -name kMDItemExifApertureValue -name kMDItemISOSpeed "$F"   # metadata present
   ```
4b. **Assert catalog-authored metadata is embedded (persona-6 defect).**
   Before this export, give at least one in-scope photo catalog metadata via
   the inspector or Batch Metadata: keywords (e.g. `STS-7, astronaut`),
   caption, creator (`NASA Photo Office`), copyright (`Public Domain`), and a
   rating. Then, on that photo's export:
   ```bash
   /usr/bin/mdls -name kMDItemKeywords -name kMDItemAuthors \
                 -name kMDItemCopyright -name kMDItemDescription "$F"
   ```
   Every field set in the catalog must read back non-null and match what was
   typed (IPTC Keywords / Byline / CopyrightNotice / CaptionAbstract are
   embedded by `ExportService.embeddingCatalogMetadata`). **Fails if** any
   catalog-authored field is `(null)` while the checkbox was checked — that
   is the persona-6 "deliverables stripped of the work" defect. Quote the
   `mdls` output.
5. **Export again with metadata OFF.** Re-open Export, same 1024 long edge,
   UNCHECK "Include EXIF/IPTC metadata", export to `OUT2=$(mktemp -d)/export`.
6. **Assert the stripped copy dropped metadata**:
   ```bash
   G=$(ls "$OUT2"/*.jpg "$OUT2"/*.jpeg 2>/dev/null | head -1)
   /usr/bin/mdls -name kMDItemExifApertureValue "$G"   # should be (null)
   ```
7. **Collision prompt (Jesse's ruling 2026-07-11).** Re-export the same scope
   into `$OUT` again (names now collide). Assert ONE batch-level
   confirmation dialog appears — title "Replace existing files?", buttons
   **Replace All / Keep Both / Cancel** — *before* any file is written
   (snapshot `ls -l "$OUT"` mtimes first; they must be unchanged while the
   dialog is up).
   - **Keep Both**: new copies land as `-2` suffixed names; originals'
     bytes/mtimes untouched.
   - **Replace All** (run a third export): colliding files are overwritten in
     place (mtime changes, no new `-3` names for the colliding set).
   - **Cancel**: nothing written at all.
   Detection/resolution plumbing:
   `ExportService.collidingFilenames`/`ExportCollisionResolution`
   (`Sources/TeststripCore/Export/ExportService.swift`),
   `AppModel.exportCollisionFilenames`, `ExportCollisionPrompt` in
   `Sources/TeststripApp/LibraryGridView.swift`. Unit coverage:
   `ExportServiceTests` collision tests + `ExportCollisionPromptTests`.
   PENDING-VM: dialog leg not yet driven live (VM unavailable this pass).

## Expected
- Step 3: an export completion signal within 30s. **Fails if** none appears or
  an error alert shows.
- Step 4: exactly one dimension equals 1024 and the other ≤ 1024; `sips` reads
  the file (valid JPEG); at least one EXIF field is present. **Fails if** the
  file is full-size (resize ignored), unreadable, or carries no EXIF when the
  box was checked. Quote the actual `sips` dimensions.
- Step 4b: `kMDItemKeywords`/`kMDItemAuthors`/`kMDItemCopyright`/
  `kMDItemDescription` match the catalog values field-for-field. **Fails if**
  any is null with the box checked.
- Step 6: the same EXIF field reads `(null)` / absent, and the catalog-
  authored fields from step 4b are also absent (the toggle governs both
  carries). **Fails if** metadata
  survived with the box unchecked — the checkbox is not governing the carry.
  Quote both `mdls` outputs (checked vs unchecked) side by side.

## Cleanup
```bash
rm -rf "$(dirname "$OUT")" "$(dirname "$OUT2")"
./script/reset_isolated_test_data.sh --delete
```
Quit the launched instance.

## Sharp edges
- The destination is a native `NSOpenPanel` (`exportDestinationParent`),
  bypassed here by the `TESTSTRIP_EXPORT_DESTINATION_DIR` env override set in
  Pre-state: with it set, the export confirm writes straight to that directory.
  Without the override, drive the panel via Cmd+Shift+G as in the reject card.
- Synthetic `--isolated` fixtures may carry little/no EXIF, which would make the
  step-4 "metadata present" assertion vacuous. Confirm the seeded originals
  actually have EXIF (`mdls` a source original first); if they don't, run this
  card against `--sample-photos` or a real-EXIF fixture instead, and say which
  corpus you used. A vacuous "present" check is a failed check.
- `sips` reports the *stored* pixel dimensions; `includeSourceMetadata` resets
  orientation to 1 and drops pixel-dimension tags on export, so trust `sips`
  geometry over any EXIF dimension tag.
- The collision prompt is batch-level and fires once per export run; two
  same-named frames *within* one batch still suffix even under Replace All
  (one frame never clobbers another — see
  `testExportReplaceAllStillSuffixesWithinBatchDuplicates`).
