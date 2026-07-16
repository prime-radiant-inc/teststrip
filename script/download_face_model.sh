#!/bin/zsh

set -euo pipefail

# Downloads the bundled AuraFace face-recognition Core ML model from the
# checksum-verified manifest and unzips the .mlpackage in place, ready for
# script/build_and_run.sh to copy into the app bundle.
#
# When to use: once per machine (or after the manifest changes), before running
# the app with face recognition or the model-gated tests. The model is NOT
# committed to git; it lives under sample-data/models/ (gitignored).

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$ROOT_DIR/sample-data/face-recognition-model.tsv"
DESTINATION="$ROOT_DIR/sample-data/models"

usage() {
  cat <<EOF
Usage: $0

Downloads and unpacks the AuraFace face-recognition model into
$DESTINATION/auraface-v1.mlpackage. The download is md5+size verified by
script/download_sample_photos.sh; this wrapper unzips the .mlpackage.zip.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

"$ROOT_DIR/script/download_sample_photos.sh" --manifest "$MANIFEST" --destination "$DESTINATION"

ZIP="$DESTINATION/auraface-v1.mlpackage.zip"
MODEL="$DESTINATION/auraface-v1.mlpackage"

if [[ ! -f "$ZIP" ]]; then
  echo "expected $ZIP after download" >&2
  exit 1
fi

rm -rf "$MODEL"
ditto -x -k "$ZIP" "$DESTINATION"

if [[ ! -d "$MODEL" ]]; then
  echo "unzip did not produce $MODEL" >&2
  exit 1
fi

# The runtime loads only the precompiled .mlmodelc; a model update is exactly
# when compilation should happen.
"$ROOT_DIR/script/compile_face_models.sh"

echo "face model ready: $MODEL"
