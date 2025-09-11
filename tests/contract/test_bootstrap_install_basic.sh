#!/usr/bin/env bash
# T002 Basic install success + reporting (C-INIT, C-REPORT)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep pwsh

  local rc repo_root url engine dest out
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t002
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_make_bin_sandbox
  bh_write_install_wrapper sh

  for engine in sh ps; do
    dest="$WORK/target-$engine"
    out="$WORK/out-$engine.txt"
    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
      echo "FAILED($engine): expected exit 0, got $rc" 1>&2
      sed -n '1,200p' "$out" 1>&2 || true
      exit 1
    fi
    assert_contains "Install/update from" "$out"
    assert_contains "Copy files into destination" "$out"
    assert_contains "Copied" "$out"
    assert_contains "Completed: overlay from" "$out"
    bh_assert_installed "$dest"
  done

  echo "PASS T002 basic install (sh, ps)"
}

main "$@"
