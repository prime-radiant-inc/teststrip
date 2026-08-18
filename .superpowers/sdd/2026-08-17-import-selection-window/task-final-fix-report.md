# Task Final Fix Report

## Date: 2026-08-17

## Findings Fixed

### Fix 1: Path-escaping collision in PreIngestThumbnailCache.thumbnailURL(for:)

**File:** `Sources/TeststripCore/Preview/PreIngestThumbnailCache.swift`

**Problem:** `thumbnailURL(for:)` sanitized source paths by replacing `/` with `_`, allowing two different paths to produce the same filename (e.g., `/a/b.jpg` and `/a_b.jpg` both map to `_a_b.jpg`), causing thumbnail collisions.

**Fix:** Replaced the naive `/` → `_` replacement with a SHA-256 hash of the path (via CryptoKit). Each unique path now produces a unique 64-character hex filename, eliminating collisions.

### Fix 2: Multi-folder import applies first folder's selectedFiles to all folders

**File:** `Sources/TeststripApp/AppModel.swift` — `beginImportFolders`

**Problem:** When importing multiple folders with `selectedFiles`, all pending folders received the same `selectedFiles` set (containing only URLs from the first folder). Subsequent folders would import zero files — silent data loss.

**Fix:** Pending (additional) folders now receive `nil` for `selectedFiles` and `preIngestThumbnailCache`, since they didn't go through the selection window. Only the first folder retains the user's selection.

### Fix 3: @StateObject prevents dedup scan results from reaching the UI

**Files:** `Sources/TeststripApp/ImportSelectionView.swift`, `Sources/TeststripApp/LibraryGridView.swift`

**Problem:** `ImportSelectionView` used `@StateObject`, which initializes the model once. When the background dedup scan completed and `importSheet` was updated with new `duplicateURLs`, the new `ImportSelectionModel` was discarded by `@StateObject`. The model's `duplicateURLs` was a `let` (immutable), so the "Duplicates" filter and "Dup" badges never updated.

**Fix:**
- Changed `duplicateURLs` from `let` to `@Published var` on `ImportSelectionModel`.
- Added a `duplicateURLs: Set<URL>` parameter to `ImportSelectionView`.
- Added `.onChange(of: duplicateURLs)` to push updated dedup results from the parent into the existing model.
- Updated `importSelectionSheet` in `LibraryGridView` to pass `data.duplicateURLs` as the new parameter.

### Fix 4: Duplicate render dispatch in loadThumbnail

**File:** `Sources/TeststripApp/ImportSelectionView.swift`

**Problem:** No per-URL guard in `loadThumbnail`. Multiple `.onAppear` calls for the same URL each spawned a `Task.detached` render, wasting CPU and creating a TOCTOU race. Also, `isRendering` was set to `false` unconditionally after each render, even if other renders were still in flight.

**Fix:** Added an `inFlightRenders: Set<URL>` guard to skip duplicate renders for the same URL. `isRendering` is now only set to `false` when all in-flight renders complete.

### Fix 5: Added test for multi-folder + selectedFiles

**File:** `Tests/TeststripAppTests/AppModelTests.swift`

**Problem:** No test verified that pending folders receive `nil` for `selectedFiles` when the first folder has a selection.

**Fix:** Added `testBeginImportFoldersPassesNilSelectedFilesToPendingFolders` which calls `beginImportFolders` with two folders and non-nil `selectedFiles`, then asserts:
- `pendingImportFolders` has one entry with `selectedFiles = nil` and `preIngestThumbnailCache = nil`.
- The first folder receives the `selectedFiles` (verified via `SelectedFilesRecorder`).

## Test Results

- **2664 tests pass, 0 failures, 19 skipped** (up from 2663 — one new test added)
- Build: clean (no errors, no new warnings)

## Concerns

None. All fixes are surgical, build cleanly, and pass the full test suite.
