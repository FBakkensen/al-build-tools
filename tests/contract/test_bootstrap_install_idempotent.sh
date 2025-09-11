#!/usr/bin/env bash
# T003 Idempotent re-run hashing (C-IDEMP)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep pwsh

  local repo_root url engine rc1 rc2 h1 h2 c1 c2 dest out
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t003
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_make_bin_sandbox
  bh_write_install_wrapper sh

  for engine in sh ps; do
    dest="$WORK/target-$engine"
    out="$WORK/out-$engine.txt"
    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc1=$?
    set -e
    [[ "$rc1" -eq 0 ]] || { echo "First run($engine) failed: rc=$rc1" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }
    h1=$(calc_dir_hashes "$dest")
    c1=$(find "$dest" -type f | wc -l | tr -d ' ')

    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc2=$?
    set -e
    [[ "$rc2" -eq 0 ]] || { echo "Second run($engine) failed: rc=$rc2" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }
    h2=$(calc_dir_hashes "$dest")
    c2=$(find "$dest" -type f | wc -l | tr -d ' ')

    if [[ "$h1" != "$h2" ]]; then
      echo "FAILED($engine): directory content hash changed between runs" 1>&2
      echo "h1=$h1" 1>&2
      echo "h2=$h2" 1>&2
      exit 1
    fi
    if [[ "$c1" != "$c2" ]]; then
      echo "FAILED($engine): file count changed between runs (c1=$c1 c2=$c2)" 1>&2
      exit 1
    fi

    assert_contains "Copied" "$out"
    assert_contains "Completed: overlay from" "$out"
  done

  echo "PASS T003 idempotent re-run (sh, ps)"
}

main "$@"
