# teststrip

> A macOS photo-culling app: catalog-first, non-destructive, AI-assisted. Early development; not ready for general use.

**Family:** products · **Type:** app · **Lifecycle:** experimental · **Owner:** obra

## What it does
Keyboard-first culling of photo libraries with auto-grouped stacks, provisional AI reads (sharpness, eyes, duplicates), compare/A-B views, token-based library search with timeline and map views, and local face detection with a confirm-before-write naming queue. A SQLite catalog is the operational truth; original image files are never modified and portable metadata mirrors to XMP sidecars. A supervised out-of-process worker handles preview rendering, image evaluation, and face embedding.

## How it fits
- Depends on: —
- Used by: —
- External: Sparkle (auto-update framework, appcast served from GitHub Releases); Apple notarization pipeline in the release workflow

## Runtime & data
- Runs: native macOS app (macOS 14+, Apple silicon, Swift 6); built with SwiftPM/Make
- Data in: the user's original image files (read-only)
- Data out: SQLite catalog + `.xmp` sidecars; signed/notarized release DMGs via GitHub Actions

## Links
- Releases / appcast: https://github.com/prime-radiant-inc/teststrip/releases

<!-- Maintained by the maintaining-project-map skill. Do not hand-edit; regenerated. -->
