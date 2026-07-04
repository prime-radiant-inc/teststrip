# Teststrip Sample Photos

This directory contains manifests and tooling for real-photo sample data. The
photo binaries are downloaded on demand and ignored by git.

The default app sample set uses the WordPress Photo Directory:

- Source: https://wordpress.org/photos/
- License: https://creativecommons.org/publicdomain/zero/1.0/
- Manifest: `wordpress-photo-directory.tsv`

The WordPress Photo Directory publishes contributor photos under CC0. The
manifest uses fixed photo pages and downloaded image URLs so the sample set is
traceable and repeatable.

The older historical set uses the Library of Congress Free to Use and Reuse data
package:

- Source: https://data.labs.loc.gov/free-to-use/
- Collection: https://www.loc.gov/free-to-use/
- Manifest basis: https://data.labs.loc.gov/free-to-use/sample-data/manifest.json
- Manifest: `loc-free-to-use.tsv`

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

Download the Library of Congress set explicitly:

```sh
script/download_sample_photos.sh \
  --manifest sample-data/loc-free-to-use.tsv \
  --destination sample-data/photos/loc-free-to-use
```

`script/build_and_run.sh --sample-photos` uses the WordPress Photo Directory
manifest by default. Override `TESTSTRIP_SAMPLE_PHOTOS_MANIFEST` and
`TESTSTRIP_SAMPLE_PHOTOS_DIR` when checking a different sample set.
