#!/usr/bin/env bash
set -euo pipefail

DELETE=0
ROOT="${TESTSTRIP_ISOLATED_TEST_DATA_ROOT:-${TMPDIR:-/tmp}}"

usage() {
  echo "usage: $0 [--delete]" >&2
}

case "${1:-}" in
  "")
    ;;
  --delete)
    DELETE=1
    ;;
  --help|-h|help)
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ ! -d "$ROOT" ]]; then
  echo "teststrip_reset_isolated_test_data error=root_not_directory root=$ROOT" >&2
  exit 2
fi

running_app_support_directories() {
  if [[ -n "${TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES:-}" ]]; then
    printf '%s\n' "$TESTSTRIP_RUNNING_APP_SUPPORT_DIRECTORIES"
    return 0
  fi

  /bin/ps eww -axo command= 2>/dev/null | /usr/bin/awk '
    {
      for (i = 1; i <= NF; i += 1) {
        prefix = "TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY="
        if (index($i, prefix) == 1) {
          print substr($i, length(prefix) + 1)
        }
      }
    }
  '
}

has_teststrip_marker() {
  local candidate="$1"
  [[ -f "$candidate/Teststrip/catalog.sqlite" \
    || -d "$candidate/Teststrip/Previews" \
    || -d "$candidate/Teststrip/SmokeOriginals" ]]
}

# Paths reach this script through different normalizers: macOS's $TMPDIR ends
# in a slash, so env-var/launch paths often carry doubled or trailing slashes
# ("…/T//teststrip-app-support.x"), while `find` prints collapsed single-slash
# paths. A naive string == between the two silently never matches, defeating
# the running-instance guard. Collapse slash runs and strip the trailing slash
# on both sides before comparing.
normalize_path() {
  local p="$1"
  p="$(printf '%s' "$p" | /usr/bin/sed -E 's#/+#/#g')"
  while [[ "$p" == */ && "$p" != "/" ]]; do p="${p%/}"; done
  printf '%s' "$p"
}

is_running_support_root() {
  local candidate; candidate="$(normalize_path "$1")"
  local running_root
  while IFS= read -r running_root; do
    [[ -n "$running_root" ]] || continue
    if [[ "$(normalize_path "$running_root")" == "$candidate" ]]; then
      return 0
    fi
  done < <(running_app_support_directories)
  return 1
}

found=0
while IFS= read -r candidate; do
  found=1
  base="$(basename "$candidate")"
  if [[ "$base" != teststrip-app-support.* ]]; then
    continue
  fi
  if ! has_teststrip_marker "$candidate"; then
    printf 'teststrip_reset_isolated_test_data skip_unmarked %s\n' "$candidate"
    continue
  fi
  if is_running_support_root "$candidate"; then
    printf 'teststrip_reset_isolated_test_data skip_running %s\n' "$candidate"
    continue
  fi
  if [[ "$DELETE" == "1" ]]; then
    rm -rf "$candidate"
    printf 'teststrip_reset_isolated_test_data deleted %s\n' "$candidate"
  else
    printf 'teststrip_reset_isolated_test_data would_delete %s\n' "$candidate"
  fi
done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type d -name 'teststrip-app-support.*' -print | sort)

if [[ "$found" == "0" ]]; then
  printf 'teststrip_reset_isolated_test_data none root=%s\n' "$ROOT"
fi
