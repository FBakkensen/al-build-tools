#!/usr/bin/env bash
# T009 Path containing spaces (C-SPACES)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep pwsh

  local repo_root url rc engine dest out
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t009
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_write_install_wrapper sh

  for engine in sh ps; do
    bh_make_bin_sandbox
    dest="$WORK/target with spaces-$engine/sub dir"
    out="$WORK/out-$engine.txt"
    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc=$?
    set -e
    [[ "$rc" -eq 0 ]] || { echo "Install($engine) failed: rc=$rc" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }
    bh_assert_installed "$dest"
    assert_contains "Completed: overlay from" "$out"
  done

  echo "PASS T009 path with spaces (sh, ps)"
}

main "$@"
