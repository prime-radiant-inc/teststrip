# Teststrip Sample Photos

This directory contains manifests and tooling for real-photo sample data. The
photo binaries are downloaded on demand and ignored by git.

The current set uses the Library of Congress Free to Use and Reuse data package:

- Source: https://data.labs.loc.gov/free-to-use/
- Collection: https://www.loc.gov/free-to-use/
- Manifest basis: https://data.labs.loc.gov/free-to-use/sample-data/manifest.json

The Library of Congress describes these collections as material with no known
copyright, material believed to be in the public domain, or material cleared by
the copyright owner for public use. Keep the manifest source URLs when adding or
replacing images so every sample file remains traceable.

Download the current sample set:

```sh
script/download_sample_photos.sh
```

Use `--limit COUNT` for a smaller local set while testing import behavior:

```sh
script/download_sample_photos.sh --limit 4
```
