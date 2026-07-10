# app-014-updater: the Sparkle updater wiring is present and correctly configured (STATIC-ONLY)

**What this covers**: Jesse gets app updates via Sparkle. Inventory items
45-48: Support ▸ Check for Updates… drives
`Updater.shared.checkForUpdates()` → `SPUStandardUpdaterController`
(`Sources/TeststripApp/Updater.swift`); automatic background checks start at
init (`startingUpdater: true`, eagerly touched in `TeststripApplication.init`,
`Sources/TeststripApp/main.swift:36`); the Info.plist carries `SUFeedURL`
(github latest appcast), `SUPublicEDKey`, `SUEnableAutomaticChecks`,
`SUEnableInstallerLauncherService`, version 0.1.0, bundle id
`com.teststrip.app` (`script/lib/app_bundle.sh:130-170`).

**STATIC-ONLY card — and why.** A real update cycle needs a published,
EdDSA-signed appcast with a newer version than the running build; none exists
pre-release (inventory item 48: UNTESTABLE without a release). Running
Check for Updates… against the live feed would at best show "no update" and
at worst hit the network non-deterministically. So this card asserts only
what is checkable offline/statically: the menu item exists, the bundle's
plist keys are right, the binary links Sparkle, and the feed URL is
well-formed and (when network permits) reachable-with-expected-404. The
dynamic upgrade flow gets a card only after the first real release.

## Pre-state
```bash
./script/build_and_run.sh --smoke     # builds the .app bundle and launches it
APP="$PWD/dist/Teststrip.app"   # build_and_run.sh assembles the bundle here (DIST_DIR, script/build_and_run.sh:31-33)
```

## Steps
1. **Menu item exists (AX).** `script/ax_drive.sh wait-vended Teststrip`,
   then via System Events assert the Support menu contains
   `Check for Updates…` (exact title, `AppMenuCoveragePresentation
   .checkForUpdatesActionID`). Do NOT click it.
2. **Info.plist keys.** Against the built bundle:
   ```bash
   plutil -p "$APP/Contents/Info.plist" | grep -E 'SUFeedURL|SUPublicEDKey|SUEnableAutomaticChecks|SUEnableInstallerLauncherService|CFBundleShortVersionString|CFBundleIdentifier'
   ```
   Expect: `SUFeedURL` =
   `https://github.com/prime-radiant-inc/teststrip/releases/latest/download/appcast.xml`,
   `SUPublicEDKey` = `ZY/ZPlRrnPohsWVic4GcjZ8tJg8qScm9MRHj3EWO4mg=`,
   both SUEnable keys = 1, `CFBundleIdentifier` = `com.teststrip.app`,
   `CFBundleShortVersionString` = `0.1.0` (unless overridden via
   `TESTSTRIP_SHORT_VERSION`).
3. **Sparkle actually bundled + signed.**
   ```bash
   ls "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"   # InstallerLauncher present
   codesign -dv "$APP" 2>&1 | head -3                            # bundle is signed
   otool -L "$APP/Contents/MacOS/"* | grep -i sparkle            # host links Sparkle
   ```
4. **Feed URL reachable-as-expected.** Network-permitting:
   ```bash
   curl -sIL -o /dev/null -w '%{http_code}\n' "$(plutil -extract SUFeedURL raw "$APP/Contents/Info.plist")"
   ```
   Pre-release the expected result is `404` (no published appcast asset on
   the latest release) — record the actual code. `200` is also a pass IF an
   appcast has since been published; anything else (DNS failure aside) means
   the URL is malformed.
5. **Background-check start (observable half only).** After launch, check
   the defaults domain for a Sparkle key (`defaults read com.teststrip.app |
   grep -i '"SU'`) as in app-001 step 6 — evidence `startingUpdater: true`
   ran.

## Expected
- Step 1: exact menu title present. **Fails if** missing/renamed (drifts
  from `MenuCoveragePresentationTests`' constant).
- Step 2: every key/value matches the table above. **Fails if** the feed URL
  or ED key drifted — a wrong key bricks all future updates silently.
- Step 3: InstallerLauncher XPC present, bundle signed, Sparkle linked.
  **Fails if** the XPC service is missing (sandboxed host can't install).
- Step 4: 404 (or 200 with a real appcast). **Fails if** the URL 4xx's for
  malformation reasons (400) or the host is wrong.
- Step 5: some SU* defaults key exists post-launch.

## Cleanup
```bash
./script/reset_isolated_test_data.sh --delete
```

## Sharp edges
- Do not click Check for Updates… in an automated run: it opens a modal
  Sparkle window (network-dependent) that can wedge the AX tree for
  subsequent cards.
- `TESTSTRIP_SHORT_VERSION`/`TESTSTRIP_BUNDLE_VERSION` env vars override the
  plist versions at bundle time — if the build env sets them, assert against
  the override, not 0.1.0.
- When the first release ships, replace this card's static cap with a
  dynamic upgrade scenario (serve a local appcast + signed zip, point
  SUFeedURL at it via a test build) — leave this note in place until then.
