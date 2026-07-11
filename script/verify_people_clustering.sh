#!/usr/bin/env bash
set -euo pipefail

# End-to-end scenario for identity-based face grouping, driven through the real
# UI. Launches the faces corpus, waits for the out-of-process worker to embed
# faces (keeping the app frontmost so its accessibility tree never parks — the
# idle-wedge that makes a stale instance un-drivable), asserts that grouping
# suggestion cards appear, then confirms/names a group and verifies a person is
# written to the catalog. Confirm-before-write is checked: no people exist until
# the naming gesture completes.
#
# Usage: script/verify_people_clustering.sh
# Exit: 0 all assertions pass, 1 an assertion failed, 2 setup/driveability error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP=Teststrip
AX="$SCRIPT_DIR/ax_drive.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Keep the app frontmost + drivable; returns 0 when the window vends.
warm() { "$AX" wait-vended "$APP" >/dev/null 2>&1; }

echo "== launch faces corpus =="
pkill -x Teststrip 2>/dev/null || true
pkill -x TeststripWorker 2>/dev/null || true
sleep 1
"$SCRIPT_DIR/build_and_run.sh" --faces >/dev/null 2>&1
sleep 3
warm || { echo "app never vended (locked console?)" >&2; exit 2; }

ISO="$(/bin/ps eww -axo command= | awk '{for(i=1;i<=NF;i++){p="TESTSTRIP_APPLICATION_SUPPORT_DIRECTORY=";if(index($i,p)==1)print substr($i,length(p)+1)}}' | head -1)"
DB="$ISO/Teststrip/catalog.sqlite"
[ -f "$DB" ] || { echo "no catalog at $DB" >&2; exit 2; }

count_faces() { sqlite3 "$DB" "SELECT count(*) FROM face_observations WHERE provider='face-recognition';" 2>/dev/null || echo 0; }
count_people() { sqlite3 "$DB" "SELECT count(*) FROM people;" 2>/dev/null || echo 0; }
count_person_assets() { sqlite3 "$DB" "SELECT count(*) FROM person_assets;" 2>/dev/null || echo 0; }

echo "== trigger evaluation over the scope =="
# "Evaluate Scope" is no longer a top-level AXButton — it moved into a menu
# item (People menu). This step was already || true-masked (never actually
# gating), so it's dropped rather than guessed at; people-009-scan.md is the
# card that drives the current People-menu scan path live.

echo "== wait for the worker to embed faces (staying warm so AX never parks) =="
target=8
for i in $(seq 1 40); do
  warm                       # re-assert frontmost every poll — prevents the idle-wedge
  n="$(count_faces)"
  [ "${n:-0}" -ge "$target" ] && break
  sleep 2
done
n="$(count_faces)"
[ "${n:-0}" -ge "$target" ] || fail "only $n face embeddings after wait (expected >= $target)"
pass "worker embedded $n faces"

echo "== confirm-before-write: no people yet =="
[ "$(count_people)" -eq 0 ] || fail "people exist before any confirm gesture"
pass "0 people before confirming (confirm-before-write holds)"

echo "== open People and assert grouping suggestions appeared =="
warm
"$AX" press "$APP" --role AXButton --label "People" >/dev/null 2>&1
sleep 2
warm
if ! TESTSTRIP_AX_TIMEOUT_SECONDS=10 "$AX" find "$APP" --contains "FACES NEED A NAME" >/dev/null 2>&1; then
  fail "no 'FACES NEED A NAME' band — grouping produced no suggestions"
fi
pass "grouping suggestion band is visible"
groups="$(TESTSTRIP_AX_TIMEOUT_SECONDS=6 "$AX" find "$APP" --contains "Who is this" 2>/dev/null | wc -l | tr -d ' ')"
[ "${groups:-0}" -ge 1 ] || fail "no 'Who is this?' group cards"
pass "$groups group card(s) offered for naming"

echo "== name a group and verify a person is written =="
warm
# The card's name button is title "Name…" / help "Name this face group"
# (distinct from the "Name selection" button in the ALL PEOPLE section).
"$AX" press "$APP" --role AXButton --help "Name this face group" >/dev/null 2>&1
sleep 1
warm
# The "Name Face Group" sheet: a field with placeholder "Person name" + Create.
"$AX" type "$APP" --role AXTextField --contains "Person name" --text "Scenario Person" >/dev/null 2>&1
"$AX" press "$APP" --role AXButton --label "Create" >/dev/null 2>&1
sleep 2

if [ "$(count_people)" -ge 1 ] && [ "$(count_person_assets)" -ge 1 ]; then
  pass "confirming a group wrote a person ($(count_people) people, $(count_person_assets) links)"
else
  fail "naming a group did not write a person (people=$(count_people), person_assets=$(count_person_assets))"
fi

echo "== all assertions passed =="
