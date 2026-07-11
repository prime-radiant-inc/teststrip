# Dogfooding Runbook

For Jesse's first (and every subsequent) real-library session. One command to launch, the rest is what to expect.

## Launch

```bash
./script/build_and_run.sh
```

Run from the repo root. This rebuilds `TeststripApp` and `TeststripWorker`, ad-hoc codesigns an unsigned dev bundle at `dist/Teststrip.app` (no sandbox entitlements), and opens it. With no flags it does **not** override the application-support directory or seed any sample/synthetic data, so it opens against your real catalog at `~/Library/Application Support/Teststrip`. Because it isn't sandboxed, the background worker is fully enabled (the sandboxed build disables worker-driven imports — don't switch builds mid-dogfood). This is the one command; every other flag (`--isolated`, `--sandboxed`, `--smoke`, `--sample-photos`, `--real-corpus`, `--build`, `--verify*`) is for development/testing, not daily use.

## Workspaces

The window is organized into three focused workspaces, switched with the
toolbar Picker or **⌘1** (Cull) / **⌘2** (Library) / **⌘3** (People) — same
shortcuts in the View menu, so the two never drift apart:

- **Cull** — the loupe-first rapid-review flow: sidebar sources (including
  Autopilot Proposals and stacks), the HUD, pick/reject/rate keys, `S` to
  cycle scope, `Z`/`I`/`?`, and the end-of-set handoff. Minimum window width
  800pt.
- **Library** — grid/loupe/timeline/map browsing with the token query field,
  result-count header, and sort/filter chrome. Minimum window width 1000pt.
- **People** — the face-grouping queue (arrow keys to move focus, Return to
  confirm/name, Esc to dismiss). Minimum window width 700pt.

**⌘I** opens the tabbed inspector (Describe/Metadata/AI) in Library and Cull;
People has no inspector.

## Where things live

- Catalog root: `~/Library/Application Support/Teststrip/`
- Catalog database: `~/Library/Application Support/Teststrip/catalog.sqlite`
- Preview cache: `~/Library/Application Support/Teststrip/Previews/`

Back up the catalog before a big session (quit Teststrip first, then):

```bash
mkdir -p ~/Backups/teststrip && cp ~/Library/Application\ Support/Teststrip/catalog.sqlite ~/Backups/teststrip/catalog-$(date +%Y%m%dT%H%M%S).sqlite
```

The database uses SQLite's default rollback-journal mode (no WAL), so copying the file while the app is closed is a clean snapshot.

## Importing a real subtree, in place

Click the blue **Import** button in the top bar above the grid, or **Import Folder** in the window toolbar (both open the same native macOS folder picker). **Import Path** does the same thing from a typed path instead of a Finder dialog — only use it if you already trust the path string; for a first pass on a real tree, the folder picker is simpler.

After you pick a folder, a confirmation sheet appears before anything happens. It scans and shows a photo-file count/size estimate, then lists the plan:

- **Catalog originals in place** — no original files are moved, rewritten, or copied from this folder.
- **Mirror portable metadata to XMP** — ratings, labels, flags, keywords, captions, creator, and copyright stay file-based.
- **Generate cached previews** — micro and grid previews are queued for fast browsing from slow or offline sources.
- **Use the managed background queue** — preview and metadata work stays visible, pausable, and cancellable.
- Follow-up setup: prepare imported-set culling, detect likely stacks, prepare keyword/face review.

Click **Import N Photos** to proceed, or Cancel.

**What actually gets written to your photo tree:** nothing to the original image bytes, ever. The only new files are `.xmp` sidecars, written next to each original, and only once you set a rating/flag/keyword/caption/creator/copyright — Teststrip doesn't write a sidecar just from importing or browsing. The default sidecar name is `<original-filename>.xmp` (e.g. `IMG_1234.CR2.xmp`). If a folder already has an Adobe-style sidecar (`IMG_1234.xmp`, no extension before `.xmp`) and no other file shares that basename, Teststrip reads and updates that one instead of creating a second file; if that basename is ambiguous (e.g. a RAW+JPEG pair), it falls back to its own collision-safe name rather than guessing which original the ambiguous sidecar belongs to. Existing unrelated XMP properties in a sidecar are preserved — only the fields above are ever touched.

## During and after import

- An orange progress banner appears at the top of the grid immediately, with a phase label ("Waiting" / "Cataloging" / "Building previews"), a cancel button, and a reassurance line — while queued it says "Queued safely; originals will not be modified."
- The **Activity** icon lives in the toolbar (a bell, replaced by a spinner while work is running, with a red count badge when something needs attention — an XMP conflict, an offline source, a provider failure). Click it to open a popover listing import and preview/metadata background work with Queued/Running/Paused/Done/Failed status, per-item progress, and pause/resume/cancel controls; clicking a problem row jumps to Library with that asset selected.
- Micro and grid previews for imported photos render inline during import for immediate browsing; anything left over drains in the background afterward. On a large subtree this backlog can take a while to fully drain — see Known Rough Edges.
- When import finishes, a completion panel reports the imported count (and how many were already-cataloged/matched), preview status, and offers next actions: Start culling, Review imported frames, Open imported set, Evaluate import (enabled once previews are cached), Cull stacks (if bursts were detected), plus face/keyword review prompts when applicable.

## Offline / NAS volumes

Each original's availability is tracked as online/offline/missing/moved/stale. A path under an unmounted `/Volumes/<name>` reads as **offline** rather than missing — grid browsing keeps working off the cached preview, but "Reveal Original," full-resolution loupe view, and re-evaluation are disabled until the volume is back online. If a source root gets remounted at a new path, use **Reconnect Sources** in the toolbar instead of re-importing.

## Capturing an issue

1. **Support > Copy Diagnostics** (menu bar) copies a text report to the clipboard: catalog/preview-cache paths, worker status, loaded/total asset counts, pending background-work count, XMP pending/conflict counts, per-source-root status, and the last few work failures. The status bar confirms "Copied diagnostics."
2. Take a normal macOS screenshot (Cmd+Shift+4 or Cmd+Shift+5) of what you were looking at.
3. Note what you were doing right before, and whether the import banner or Activity panel showed anything unusual (stuck "Waiting," a Failed row, etc.). If it's tied to a specific photo or folder, note the path.

## Quitting and relaunching

Quitting any time — including mid-import or while previews are still draining — is safe for the catalog. On relaunch:

- Any import that was still queued/running/paused gets marked failed with "Import interrupted before completion" (visible in Work history); re-run Import Folder on the same folder to finish it. Already-cataloged files are matched by path and won't be duplicated — only what's missing gets added.
- Any pending preview work resumes automatically in the background (bounded, and it skips sources that are still offline) — you don't need to do anything to restart it.

## New since this runbook was written (2026-07-06 evening)

- Imports offer **"Read imported frames"** (default on): evaluation runs automatically as previews complete, so verdicts, stack recommendations, and badges are live by the time you cull. Watch Activity if you want to see it work.
- **Card imports organize into `YYYY/YYYY-MM-DD/` folders by default** (toggle off for flat copy) and can write a **second copy** to a backup destination; backup failures show per-file in the issue sheet without failing the import.
- **Export** lives in the toolbar: selected/visible/current-scope, Full-res or Web 2048px, optional EXIF/IPTC carry (default on).
- Culling now shows a **provisional Keep/Toss read** with inline rationale, a stack list rail, ✦ recommended-frame markers, face **Close-Ups** beside the loupe, and a **Potential Picks** review queue. All reads are display-only until you act. Thresholds were calibrated against this library's real signal distributions on 2026-07-06; if reads feel wrong, say so — they're one constant away.
- **People** suggests automatic face groupings with a "needs a name" confirm band; nothing is written until you confirm.

## Known rough edges

- **Large-import feedback latency was fixed and re-measured on 2026-07-06.** After the render-path caching and publication-coalescing fixes (`dd1b598`, `1b0b2fb`, `974ede9`, `575a595`), the 600-image foreground probe shows first visible feedback at 0.75s (budget: 1.5s), the imported photo visible at 3.4s, and the preview backlog drained by the time the probe samples. Imports much larger than 600 have not been probed; if a big import feels stalled, capture Copy Diagnostics and report it.
- Ambiguous Adobe-style sidecars that carry `photoshop:SidecarForExtension` (all 79 in this library) are now bound to their original and updated in place; shared `frame.xmp` files without that attribute still conservatively get a Teststrip-style `frame.ext.xmp` beside them.
