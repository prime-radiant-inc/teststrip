#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/teststrip-sample-photos-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

source_one="$TMP_DIR/source-one.jpg"
source_two="$TMP_DIR/source-two.jpg"
printf 'first sample image bytes\n' > "$source_one"
printf 'second sample image bytes\n' > "$source_two"

md5_value() {
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  else
    md5sum "$1" | awk '{print $1}'
  fi
}

manifest="$TMP_DIR/manifest.tsv"
cat > "$manifest" <<EOF
# filename	url	md5	size	source_url
one.jpg	file://$source_one	$(md5_value "$source_one")	$(wc -c < "$source_one" | tr -d ' ')	https://example.test/one
two.jpg	file://$source_two	$(md5_value "$source_two")	$(wc -c < "$source_two" | tr -d ' ')	https://example.test/two
EOF

destination="$TMP_DIR/photos"
"$ROOT_DIR/script/download_sample_photos.sh" --manifest "$manifest" --destination "$destination" >/dev/null

[[ -f "$destination/one.jpg" ]]
[[ -f "$destination/two.jpg" ]]
cmp -s "$source_one" "$destination/one.jpg"
cmp -s "$source_two" "$destination/two.jpg"

mtime_before="$(stat -f %m "$destination/one.jpg" 2>/dev/null || stat -c %Y "$destination/one.jpg")"
"$ROOT_DIR/script/download_sample_photos.sh" --manifest "$manifest" --destination "$destination" >/dev/null
mtime_after="$(stat -f %m "$destination/one.jpg" 2>/dev/null || stat -c %Y "$destination/one.jpg")"
[[ "$mtime_before" == "$mtime_after" ]]

bad_manifest="$TMP_DIR/bad-manifest.tsv"
cat > "$bad_manifest" <<EOF
# filename	url	md5	size	source_url
bad.jpg	file://$source_one	00000000000000000000000000000000	$(wc -c < "$source_one" | tr -d ' ')	https://example.test/bad
EOF

if "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$bad_manifest" --destination "$TMP_DIR/bad" >/tmp/teststrip-bad-download.out 2>/tmp/teststrip-bad-download.err; then
  echo "expected checksum failure" >&2
  exit 1
fi

echo "download_sample_photos tests passed"
