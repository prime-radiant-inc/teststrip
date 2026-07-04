# RAW Decode Capability

Teststrip currently uses `ImageIODecodeProvider` as the default decode provider. ImageIO support is useful, but it is OS, camera, and file dependent, especially for RAW formats. Teststrip should catalog files honestly and avoid presenting best-effort decode as guaranteed RAW support.

## Current Provider Matrix

| Format family | Extensions | Current provider | Support level | Metadata | Cached preview | Full RAW render |
| --- | --- | --- | --- | --- | --- | --- |
| JPEG | `jpg`, `jpeg` | ImageIO | Working | Yes | Yes | Yes |
| HEIC | `heic` | ImageIO | Working | Yes | Yes | Yes |
| TIFF | `tif`, `tiff` | ImageIO | Working | Yes | Yes | Yes |
| PNG | `png` | ImageIO | Working | Yes | Yes | Yes |
| Adobe DNG | `dng` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Canon RAW | `crw`, `cr2`, `cr3` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Nikon RAW | `nef` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Sony RAW | `arw` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Fuji RAW | `raf` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Panasonic/Leica RAW | `rwl`, `rw2` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Samsung/Olympus RAW | `srw`, `orf` | ImageIO | Best effort | Yes | Best effort | Not promised |
| Sigma/Foveon RAW | `x3f` | None yet | Unsupported | No | No | No |

Sigma/Foveon X3F is recognized as a relevant long-tail RAW family because Jesse has old Foveon files, but the current ImageIO provider does not claim it. Lytro and other specialty long-tail formats are out of scope unless a future provider explicitly declares support.

## Product Behavior

- Import discovery still includes best-effort RAW extensions so photographers can catalog existing archives.
- Metadata extraction and preview rendering can fail per file without invalidating the catalog row.
- Browsing uses cached previews. The app should not decode originals on hot grid paths.
- UI copy should describe ImageIO RAW handling as best effort until real fixture-backed coverage exists.

## Provider Boundary

`DecodeProvider.capability(forFileExtension:)` exposes provider capabilities without requiring callers to decode a file. Providers declare:

- `support`: `working`, `bestEffort`, or `unsupported`
- metadata readability
- embedded-preview usefulness
- cached-preview rendering
- full-image rendering
- a short human-readable note

Future LibRaw, RawSpeed, or vendor-specific providers should implement the same `DecodeProvider` protocol and return more precise capabilities for the formats they own. `DecodeRegistry` remains responsible for choosing the first provider that accepts a URL, so provider ordering is the swap point.
