#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/sample-data/loc-free-to-use.tsv"
DESTINATION="$ROOT_DIR/sample-data/photos/loc-free-to-use"
LIMIT=0

usage() {
  cat <<EOF
Usage: $0 [--manifest PATH] [--destination PATH] [--limit COUNT]

Downloads the Teststrip real-photo sample set from a tab-separated manifest.
Downloaded files are checksum verified and are not committed to the repo.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      MANIFEST="$2"
      shift 2
      ;;
    --destination)
      DESTINATION="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$MANIFEST" ]]; then
  echo "manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! [[ "$LIMIT" =~ '^[0-9]+$' ]]; then
  echo "--limit must be a non-negative integer" >&2
  exit 2
fi

md5_value() {
  if command -v md5 >/dev/null 2>&1; then
    md5 -q "$1"
  elif command -v md5sum >/dev/null 2>&1; then
    md5sum "$1" | awk '{print $1}'
  else
    echo "md5 or md5sum is required" >&2
    exit 1
  fi
}

byte_count() {
  wc -c < "$1" | tr -d ' '
}

verify_file() {
  local file_path="$1"
  local expected_md5="$2"
  local expected_size="$3"

  [[ "$(md5_value "$file_path")" == "$expected_md5" ]] || return 1

  if [[ -n "$expected_size" && "$expected_size" != "0" ]]; then
    [[ "$(byte_count "$file_path")" == "$expected_size" ]] || return 1
  fi
}

mkdir -p "$DESTINATION"

processed=0
downloaded=0
kept=0

while IFS=$'\t' read -r filename url expected_md5 expected_size source_url || [[ -n "${filename:-}" ]]; do
  [[ -z "${filename:-}" || "$filename" == \#* ]] && continue

  if [[ "$filename" == */* || "$filename" == *..* ]]; then
    echo "unsafe manifest filename: $filename" >&2
    exit 1
  fi

  processed=$((processed + 1))
  output="$DESTINATION/$filename"

  if [[ -f "$output" ]] && verify_file "$output" "$expected_md5" "$expected_size"; then
    echo "kept $filename"
    kept=$((kept + 1))
  else
    temp_file="$(mktemp "$DESTINATION/.download.$filename.XXXXXX")"
    if ! curl -fsSL --retry 3 --retry-delay 1 -o "$temp_file" "$url"; then
      rm -f "$temp_file"
      echo "download failed: $url" >&2
      exit 1
    fi

    if ! verify_file "$temp_file" "$expected_md5" "$expected_size"; then
      rm -f "$temp_file"
      echo "checksum or size mismatch: $filename from $source_url" >&2
      exit 1
    fi

    mv "$temp_file" "$output"
    echo "downloaded $filename"
    downloaded=$((downloaded + 1))
  fi

  if [[ "$LIMIT" -gt 0 && "$processed" -ge "$LIMIT" ]]; then
    break
  fi
done < "$MANIFEST"

echo "sample photos ready: destination=$DESTINATION total=$processed downloaded=$downloaded kept=$kept"
