#!/bin/zsh

set -euo pipefail

# Compiles the downloaded Core ML face models (sample-data/models/*.mlpackage)
# into their runtime-loadable .mlmodelc form, in place, once per machine. The
# app, the worker, and the tests load ONLY the precompiled .mlmodelc; runtime
# never compiles (MLModel.compileModel writes a fresh ~125 MB .mlmodelc into
# the process temp dir on every call and nothing cleans it up).
#
# When to use: after script/download_face_model.sh fetches or updates an
# .mlpackage (it invokes this automatically), or whenever
# sample-data/models/<name>.mlmodelc is missing or stale. Safe to run any
# time: it is a fast no-op when every compiled model is up to date.
# Worktrees that symlink sample-data/models share the same compiled artifacts.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODELS_DIR="$ROOT_DIR/sample-data/models"
FORCE=0

usage() {
  cat <<EOF
Usage: $0 [--force]

Compiles every $MODELS_DIR/<name>.mlpackage into a sibling <name>.mlmodelc
(the only form the app/worker/tests load), skipping models whose compiled
output is already newer than the package. --force recompiles everything.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  --force) FORCE=1 ;;
  "") ;;
  *) usage >&2; exit 2 ;;
esac

if [[ ! -d "$MODELS_DIR" ]]; then
  echo "no models directory at $MODELS_DIR (run script/download_face_model.sh first)" >&2
  exit 0
fi

packages=("$MODELS_DIR"/*.mlpackage(N))
if (( ${#packages} == 0 )); then
  echo "no .mlpackage models in $MODELS_DIR (run script/download_face_model.sh first)" >&2
  exit 0
fi

for package in "${packages[@]}"; do
  base="${package:t:r}"
  compiled="$MODELS_DIR/$base.mlmodelc"
  if (( FORCE == 0 )) && [[ -d "$compiled" ]] \
      && [[ -z "$(find "$package" -newer "$compiled" -print -quit)" ]]; then
    echo "up to date: $base.mlmodelc"
    continue
  fi
  # Compile into a scratch dir on the same volume, then move into place so a
  # crashed compile never leaves a half-written .mlmodelc where the loader
  # would find it.
  workdir="$(mktemp -d "$MODELS_DIR/.compile-$base.XXXXXX")"
  trap 'rm -rf "$workdir"' EXIT
  xcrun coremlcompiler compile "$package" "$workdir" >/dev/null
  if [[ ! -d "$workdir/$base.mlmodelc" ]]; then
    echo "coremlcompiler did not produce $base.mlmodelc (see $workdir)" >&2
    exit 1
  fi
  rm -rf "$compiled"
  mv "$workdir/$base.mlmodelc" "$compiled"
  rm -rf "$workdir"
  trap - EXIT
  echo "compiled: $base.mlmodelc ($(du -sh "$compiled" | cut -f1))"
done
