#!/usr/bin/env bash
# Contract tests for overlay/scripts/next-object-number.sh (Linux/bash)
# Verifies next available AL object numbers per type within app/app.json idRanges.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/al_fixtures.sh"

SCRIPT_REL="overlay/scripts/next-object-number.sh"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"
SCRIPT_PATH="$REPO_ROOT/$SCRIPT_REL"

require_cmd bash grep awk sort sed mktemp

run_sh() {
  local proj=${1:?}; local objtype=${2:?}
  ( cd "$proj" && bash "$SCRIPT_PATH" "$objtype" )
}

expect_ok() {
  local got rc
  set +e
  got=$(run_sh "$1" "$2")
  rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "FAIL: expected exit 0 for '$2', got $rc; output: $got" 1>&2
    exit 1
  fi
  if [[ "$got" != "$3" ]]; then
    echo "FAIL: expected '$3' for '$2', got '$got'" 1>&2
    exit 1
  fi
}

expect_fail_msg() {
  local got rc
  set +e
  got=$(run_sh "$1" "$2" 2>&1)
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "FAIL: expected non-zero exit for '$2', got 0; output: $got" 1>&2
    exit 1
  fi
  assert_contains "No available $2 number" "$got"
}

main() {
  # 1) Basic start: no objects -> returns 'from'
  local p1
  p1=$(al_new_project albt-nextnum-sh-1)
  al_write_appjson "$p1" "50000:50010"
  expect_ok "$p1" page 50000

  # 2) Per-type isolation: 'page 50000' exists; 'table' can still use 50000
  local p2
  p2=$(al_new_project albt-nextnum-sh-2)
  al_write_appjson "$p2" "50000:50010"
  al_add_object "$p2" page 50000 TestPage
  expect_ok "$p2" table 50000

  # 3) First gap detection
  local p3
  p3=$(al_new_project albt-nextnum-sh-3)
  al_write_appjson "$p3" "50000:50010"
  al_add_object "$p3" page 50000 A
  al_add_object "$p3" page 50002 B
  expect_ok "$p3" page 50001

  # 4) Range exhausted -> exit 2 with message
  local p4
  p4=$(al_new_project albt-nextnum-sh-4)
  al_write_appjson "$p4" "50000:50001"
  al_add_object "$p4" page 50000 A
  al_add_object "$p4" page 50001 B
  expect_fail_msg "$p4" page

  # 5) Ignore out-of-range objects
  local p5
  p5=$(al_new_project albt-nextnum-sh-5)
  al_write_appjson "$p5" "50000:50001"
  # Objects outside the configured ranges should not block assignment
  al_add_object "$p5" page 40000 OldPage
  al_add_object "$p5" table 40000 OldTable
  expect_ok "$p5" page 50000

  # 6) Multiple ranges: consume first range, select from second
  local p6
  p6=$(al_new_project albt-nextnum-sh-6)
  al_write_appjson "$p6" "50000:50000" "50002:50003"
  al_add_object "$p6" page 50000 Only
  expect_ok "$p6" page 50002

  # 7) Missing app.json -> non-zero and message
  local p7
  p7=$(al_new_project albt-nextnum-sh-7)
  # intentionally do not write app.json
  expect_fail_msg "$p7" page

  echo "PASS: next-object-number.sh contract tests"
}

main "$@"

