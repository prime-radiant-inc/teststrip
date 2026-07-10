#!/usr/bin/env bash
set -euo pipefail

# Runs Teststrip's interactive AX-driven scenario cards (test/scenarios/*.md)
# inside a Tart macOS VM instead of on the host console.
#
# Why: script/ax_drive.sh needs a genuinely-frontmost, unlocked GUI session.
# Jesse's host console gets stolen/locked by other work, which wedges any
# scenario card mid-run (see test/scenarios/README.md's "locked console"
# trap). A Tart VM with an auto-login GUI session never locks, so the
# interactive driving moves there. Building stays on the host — the VM never
# runs `swift build`; it only receives a pre-built .app bundle and a
# pre-seeded isolated catalog over rsync.
#
# Usage:
#   script/vm_scenario_run.sh setup              Clone+boot the VM if missing, grant TCC.
#   script/vm_scenario_run.sh sync [variant...]  Build locally, seed the given catalog
#                                                 variant(s) (default: smoke faces), rsync
#                                                 app+seeds+script/ into the VM.
#   script/vm_scenario_run.sh launch VARIANT     Kill any running app in the VM and
#                                                 launch a FRESH copy of the given seed
#                                                 variant's catalog (never reuse state
#                                                 across cards).
#   script/vm_scenario_run.sh ax ARGS...         Run script/ax_drive.sh ARGS... inside the
#                                                 VM (over ssh) against the launched app.
#   script/vm_scenario_run.sh sql VARIANT SQL    Run `sqlite3 catalog.sqlite SQL` inside the
#                                                 VM against the given variant's catalog.
#   script/vm_scenario_run.sh shell               Interactive ssh session into the VM.
#   script/vm_scenario_run.sh shell CMD...        Run CMD... remotely (non-interactively,
#                                                  quoted like `ax`) and return its output.
#   script/vm_scenario_run.sh key SPEC             Deliver a keystroke/key-code to the
#                                                  frontmost app in the VM via
#                                                  `osascript -e 'tell application "System
#                                                  Events" to SPEC'`. SPEC is passed through
#                                                  verbatim, so it can be any System Events
#                                                  keyboard command, e.g.:
#                                                    key 'keystroke "p"'
#                                                    key 'keystroke "p" using {command down}'
#                                                    key 'key code 36'          (Return)
#                                                    key 'key code 123'         (Left arrow)
#   script/vm_scenario_run.sh ip                  Print the VM's current IP.
#   script/vm_scenario_run.sh destroy            Stop and delete the VM.
#
# Seed variants (see script/build_and_run.sh for the equivalent host flags):
#   smoke   24 synthetic photos  (script/build_and_run.sh --smoke)
#   faces   sample-data/photos/faces via faces.tsv (script/build_and_run.sh --faces)
#   empty   isolated but unseeded catalog (script/build_and_run.sh --isolated)
#
# A scenario card is still driven by hand (or by an agent) issuing a sequence
# of `vm_scenario_run.sh ax ...` / `vm_scenario_run.sh sql ...` calls per its
# Steps section — this script owns VM lifecycle and state sync, not per-card
# semantics, matching how ax_drive.sh itself is a primitive, not a card runner.

VM_NAME="${TESTSTRIP_VM_NAME:-teststrip-e2e}"
VM_USER="${TESTSTRIP_VM_USER:-admin}"
VM_PASS="${TESTSTRIP_VM_PASS:-admin}"
BASE_IMAGE="${TESTSTRIP_VM_BASE_IMAGE:-ghcr.io/cirruslabs/macos-tahoe-base:latest}"
REMOTE_ROOT="/Users/$VM_USER/teststrip-vm"
APP_NAME="Teststrip"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
SEED_ROOT="${TMPDIR:-/tmp}/teststrip-vm-seeds"

usage() { sed -n '2,53p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

require_tart() { command -v tart >/dev/null || { echo "tart not found; brew install cirruslabs/cli/tart" >&2; exit 1; }; }

vm_ip() {
  require_tart
  local ip
  for _ in $(seq 1 30); do
    ip="$(tart ip "$VM_NAME" 2>/dev/null || true)"
    [[ -n "$ip" ]] && { echo "$ip"; return 0; }
    sleep 2
  done
  echo "timed out waiting for $VM_NAME IP" >&2
  return 1
}

ssh_cmd() {
  local ip; ip="$(vm_ip)"
  SSHPASS="$VM_PASS" sshpass -e ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$VM_USER@$ip" "$@"
}

scp_to_vm() {
  local dest_subdir="$1"; shift
  local ip; ip="$(vm_ip)"
  SSHPASS="$VM_PASS" sshpass -e rsync -az -e "ssh -o StrictHostKeyChecking=no" "$@" "$VM_USER@$ip:$REMOTE_ROOT/$dest_subdir"
}

cmd_setup() {
  require_tart
  command -v sshpass >/dev/null || { echo "sshpass not found; brew install cirruslabs/cli/sshpass (or hudochenkov/sshpass)" >&2; exit 1; }

  if ! tart list 2>/dev/null | awk '{print $2}' | grep -qx "$VM_NAME"; then
    echo "cloning $BASE_IMAGE -> $VM_NAME"
    tart clone "$BASE_IMAGE" "$VM_NAME"
  fi

  if ! tart list 2>/dev/null | grep -q "^local *$VM_NAME .*running"; then
    echo "booting $VM_NAME (headless, autologin GUI session — console never locks)"
    tart run "$VM_NAME" --no-graphics >"${TMPDIR:-/tmp}/tart-$VM_NAME.log" 2>&1 &
    disown
    sleep 5
  fi

  local ip; ip="$(vm_ip)"
  echo "VM IP: $ip"
  ssh_cmd "mkdir -p '$REMOTE_ROOT/dist' '$REMOTE_ROOT/script' '$REMOTE_ROOT/isolated' '$REMOTE_ROOT/test'"

  echo "granting Accessibility + AppleEvents (System Events) TCC to swift/bash/osascript"
  local sql_file="${TMPDIR:-/tmp}/teststrip-vm-grant-tcc.sql"
  cat >"$sql_file" <<'SQL'
INSERT OR REPLACE INTO access (service,client,client_type,auth_value,auth_reason,auth_version,indirect_object_identifier_type,indirect_object_identifier,flags,last_modified)
VALUES
('kTCCServiceAccessibility','/usr/bin/swift',1,2,1,1,0,'UNUSED',0,strftime('%s','now')),
('kTCCServiceAccessibility','/bin/bash',1,2,1,1,0,'UNUSED',0,strftime('%s','now')),
('kTCCServiceAccessibility','/usr/bin/osascript',1,2,1,1,0,'UNUSED',0,strftime('%s','now')),
('kTCCServiceAppleEvents','/usr/bin/osascript',1,2,1,1,0,'com.apple.systemevents',0,strftime('%s','now')),
('kTCCServiceAppleEvents','/usr/bin/swift',1,2,1,1,0,'com.apple.systemevents',0,strftime('%s','now'));
SQL
  SSHPASS="$VM_PASS" sshpass -e scp -o StrictHostKeyChecking=no "$sql_file" "$VM_USER@$ip:/tmp/grant_tcc.sql"
  ssh_cmd "sudo sqlite3 '/Library/Application Support/com.apple.TCC/TCC.db' < /tmp/grant_tcc.sql" \
    || { echo "TCC grant failed — if csrutil status (SIP) is enabled in the VM, this direct-DB approach cannot work; a one-time manual grant in the tart viewer window (System Settings > Privacy & Security > Accessibility/Automation) is required instead." >&2; exit 1; }
  echo "setup complete"
}

seed_dir_for() {
  case "$1" in
    smoke) echo "$SEED_ROOT/smoke" ;;
    faces) echo "$SEED_ROOT/faces" ;;
    empty) echo "$SEED_ROOT/empty" ;;
    *) echo "unknown seed variant: $1 (want smoke|faces|empty)" >&2; exit 2 ;;
  esac
}

seed_locally() {
  local variant="$1" dir; dir="$(seed_dir_for "$variant")"
  if [[ -f "$dir/Teststrip/catalog.sqlite" ]]; then
    echo "'$variant' seed template already exists at $dir (idempotent template — cmd_launch stamps a fresh copy per launch; pass --reseed to force regeneration)"
    [[ "${2:-}" == "--reseed" ]] || return 0
    rm -rf "${dir:?}/Teststrip"
  fi
  mkdir -p "$dir"
  case "$variant" in
    smoke)
      ( cd "$ROOT_DIR" && swift run TeststripBench seed-app-catalog "$dir" "${TESTSTRIP_SMOKE_ASSET_COUNT:-24}" )
      ;;
    faces)
      local photos="$ROOT_DIR/sample-data/photos/faces"
      [[ -d "$photos" ]] || "$ROOT_DIR/script/download_sample_photos.sh" --manifest "$ROOT_DIR/sample-data/faces.tsv" --destination "$photos"
      ( cd "$ROOT_DIR" && swift run TeststripBench seed-sample-catalog "$dir" "$photos" )
      ;;
    empty)
      mkdir -p "$dir/Teststrip"
      ;;
  esac
}

cmd_sync() {
  local variants=("${@:-}")
  [[ -z "${variants[*]}" ]] && variants=(smoke faces)

  echo "building app bundle locally (host-only; the VM never runs swift build)"
  ( cd "$ROOT_DIR" && ./script/build_and_run.sh --build )

  for v in "${variants[@]}"; do
    [[ -z "$v" ]] && continue
    echo "seeding '$v' catalog locally"
    seed_locally "$v"
  done

  echo "rsyncing app bundle to VM"
  ssh_cmd "mkdir -p '$REMOTE_ROOT/dist'"
  scp_to_vm "dist/" --delete "$APP_BUNDLE"
  echo "rsyncing script/ to VM"
  scp_to_vm "script/" --exclude .git "$ROOT_DIR/script/"
  echo "rsyncing test/scenarios/ to VM"
  ssh_cmd "mkdir -p '$REMOTE_ROOT/test/scenarios'"
  scp_to_vm "test/scenarios/" "$ROOT_DIR/test/scenarios/"

  for v in "${variants[@]}"; do
    [[ -z "$v" ]] && continue
    echo "rsyncing '$v' seed catalog to VM"
    ssh_cmd "mkdir -p '$REMOTE_ROOT/isolated/$v'"
    scp_to_vm "isolated/$v/" "$(seed_dir_for "$v")/"
  done

  ssh_cmd "codesign --force --sign - '$REMOTE_ROOT/dist/$APP_NAME.app/Contents/Helpers/TeststripWorker' 2>&1 || true; codesign --force --sign - '$REMOTE_ROOT/dist/$APP_NAME.app' && chmod +x '$REMOTE_ROOT'/script/*.sh"
  echo "sync complete"
}

cmd_launch() {
  local variant="${1:?usage: $0 launch VARIANT (smoke|faces|empty)}"
  seed_dir_for "$variant" >/dev/null # validate
  local remote_seed="$REMOTE_ROOT/isolated/$variant"
  local fresh="$REMOTE_ROOT/run/$variant-$(date +%s)"
  # seed-app-catalog/seed-sample-catalog bake original_path as an absolute
  # path rooted at the directory they were given at seed time — the *host's*
  # local seed_dir_for($variant), since seeding itself always runs on the
  # host (cmd_sync). That host path never existed on the VM at all. A plain
  # `cp -R` from remote_seed to a fresh per-launch directory does not fix
  # this — it only relocates the copy, not the baked-in string — so every
  # original_path still points at a nonexistent host path, breaking any card
  # that needs a real on-disk original (XMP sidecar writes, Move Rejects).
  # Rewrite the prefix after copying so original_path tracks the copy,
  # matching how build_and_run.sh's host flow seeds directly into the live
  # isolated dir with no relocate step.
  local local_seed; local_seed="$(seed_dir_for "$variant")"
  ssh_cmd "pkill -x $APP_NAME 2>/dev/null || true; pkill -x TeststripApp 2>/dev/null || true; pkill -x TeststripWorker 2>/dev/null || true; sleep 1; \
    mkdir -p '$(dirname "$fresh")' && cp -R '$remote_seed' '$fresh' && \
    sqlite3 '$fresh/Teststrip/catalog.sqlite' \"UPDATE assets SET original_path = replace(original_path, '$local_seed', '$fresh');\" && \
    open -n '$REMOTE_ROOT/dist/$APP_NAME.app' --env TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY='$fresh' && sleep 2 && pgrep -x $APP_NAME"
  echo "launched '$variant' fresh at $fresh (catalog: $fresh/Teststrip/catalog.sqlite)"
}

cmd_ax() { ssh_cmd "cd '$REMOTE_ROOT' && ./script/ax_drive.sh $(printf '%q ' "$@")"; }

cmd_sql() {
  local variant="${1:?usage: $0 sql VARIANT \"SELECT ...\"}"; shift
  local sql="${1:?usage: $0 sql VARIANT \"SELECT ...\"}"
  ssh_cmd "latest=\$(ls -dt '$REMOTE_ROOT'/run/$variant-* 2>/dev/null | head -1); sqlite3 \"\$latest/Teststrip/catalog.sqlite\" $(printf '%q' "$sql")"
}

cmd_shell() {
  local ip; ip="$(vm_ip)"
  if [[ $# -eq 0 ]]; then
    SSHPASS="$VM_PASS" sshpass -e ssh -o StrictHostKeyChecking=no "$VM_USER@$ip"
  else
    ssh_cmd "$(printf '%q ' "$@")"
  fi
}

cmd_key() {
  local spec="${1:?usage: $0 key OSASCRIPT-KEYSTROKE-SPEC (e.g. 'keystroke \"p\"' or 'key code 36')}"
  ssh_cmd "osascript -e $(printf '%q' "tell application \"System Events\" to $spec")"
}

cmd_destroy() { require_tart; tart stop "$VM_NAME" 2>/dev/null || true; tart delete "$VM_NAME"; }

case "${1:-}" in
  setup) cmd_setup ;;
  sync) shift; cmd_sync "$@" ;;
  launch) shift; cmd_launch "$@" ;;
  ax) shift; cmd_ax "$@" ;;
  sql) shift; cmd_sql "$@" ;;
  shell) shift; cmd_shell "$@" ;;
  key) shift; cmd_key "$@" ;;
  ip) vm_ip ;;
  destroy) cmd_destroy ;;
  --help|-h|help|"") usage ;;
  *) echo "unknown command: $1" >&2; usage; exit 2 ;;
esac
