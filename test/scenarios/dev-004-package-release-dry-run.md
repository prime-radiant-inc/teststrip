# dev-004: package_release.sh --dry-run produces an ad-hoc, verified, non-distributable artifact

**What this covers**
As a developer I want `script/package_release.sh --dry-run` to prove the
release-build-and-assemble pipeline (release build, `.app` bundle assembly
incl. the bundled Core ML model, inside-out signing, `codesign --verify`, and
zip/dmg packaging) without needing Developer ID credentials or hitting
Apple's notarization service. This is the capability-inventory entry for
`script/package_release.sh` (dry-run path) — the CI-safe, credential-free
half of the release pipeline. Covers `script/package_release.sh`.

## Pre-state
- Repo at `fix-worker-death-recovery` (or whatever branch), clean enough that
  `swift build -c release` will succeed (no in-progress edits that break the
  build). `--dry-run` runs a real `swift build -c release` — expect several
  minutes on first run, faster on a warm build cache.
- No credentials required: `--dry-run` never reads
  `TESTSTRIP_SIGNING_IDENTITY` / `TESTSTRIP_NOTARY_PROFILE`.
- This step only writes into `dist/` under the repo root — it does not touch
  `~/Library/Application Support/Teststrip` or any isolated catalog. Safe to
  run directly (not host-console-touching; no GUI launch, no AX).

## Steps
```bash
cd /Users/jesse/git/projects/teststrip
rm -f dist/Teststrip-*.zip   # clean slate so the Expected artifact check is unambiguous
./script/package_release.sh --dry-run
echo "exit: $?"
```

Then inspect the results:
```bash
ls -la dist/
codesign --verify --deep --strict --verbose=2 dist/Teststrip.app; echo "codesign exit: $?"
codesign -dvv dist/Teststrip.app 2>&1 | grep -E 'Signature|Authority'
```

## Expected
- Process exit code `0`.
- Console output includes, in order (per `main()`'s `DRY_RUN` branch,
  `script/package_release.sh:215-223`):
  - `==> DRY RUN: ad-hoc signature, no notarization or Gatekeeper assessment`
  - `==> Release build of Teststrip + TeststripWorker`
  - `==> Assembling <dist>/Teststrip.app`
  - `==> Ad-hoc signing Sparkle.framework (dry run)`
  - `==> Ad-hoc signing worker helper (dry run)`
  - `==> Ad-hoc signing outer app bundle (dry run)`
  - `==> Verifying signature: codesign --verify --deep --strict`
  - `==> Packaging .zip -> <dist>/Teststrip-<version>.zip`
  - `==> Dry run complete. Assembled + ad-hoc-signed + verified: <dist>/Teststrip.app`
  - `==> Artifact: <dist>/Teststrip-<version>.zip (NOT distributable — ad-hoc signed, unnotarized)`
    — this exact trailing log line **is** the non-distributable marker; there
    is no separate marker *file* written into the artifact or bundle (see
    Sharp edges).
- `dist/Teststrip.app` exists and `dist/Teststrip-<version>.zip` exists
  (`<version>` = `$TESTSTRIP_SHORT_VERSION`, resolved from
  `script/lib/app_bundle.sh` — read its value if the exact filename is needed
  for assertions).
- `codesign --verify --deep --strict --verbose=2 dist/Teststrip.app` exits
  `0` — the ad-hoc signature is structurally valid (satisfies is-code-signed
  checks) even though it is not a Developer ID / distributable signature.
- `codesign -dvv` on the bundle shows `Signature=adhoc` (no `Authority=`
  lines) — confirming this is the ad-hoc path, not a real identity.
- What `--dry-run` explicitly **skips** per the script's own header comment
  (`script/package_release.sh:33-35`) and the `main()` dry-run branch: no
  `sign_developer_id` (real Developer ID cert), no `notarize_and_staple`
  (`xcrun notarytool submit --wait` / `xcrun stapler staple`), and no
  `verify_distribution` (`spctl -a -vvv -t execute` / `xcrun stapler
  validate`) — Gatekeeper assessment is not run and would not pass for an
  ad-hoc signature per the script's own comment.

## Cleanup
```bash
rm -rf /Users/jesse/git/projects/teststrip/dist
```
`dist/` is a build output directory, not tracked state — safe to remove
entirely. No isolated catalog or app-support directory was touched by this
card, so no `reset_isolated_test_data.sh` call is needed.

## Sharp edges
- The "NOT distributable" marker is **only a log line** (`log "Artifact: ...
  (NOT distributable ...)"` at `script/package_release.sh:222`), not a
  sentinel file written next to the artifact or embedded in the bundle. A
  card or CI job that only inspects `dist/` on disk (rather than capturing
  stdout) has no on-disk signal distinguishing a dry-run zip from a real
  release zip other than re-running `codesign -dvv` and checking for
  `Signature=adhoc`. Worth flagging if CI ever needs to gate on this
  programmatically rather than by grepping build logs.
- `--dry-run` still runs a full `swift build -c release` (step 1 in the
  pipeline docstring) — it is not a fast smoke check; expect real build time.
- `package_artifact()` computes `ARTIFACT_PATH` from
  `$TESTSTRIP_SHORT_VERSION` and does `rm -f "$ARTIFACT_PATH"` first, so
  re-running `--dry-run` twice in a row silently overwrites the prior zip
  rather than erroring or incrementing.
