#!/usr/bin/env bash
# T006 Fallback extraction when unzip absent (C-FALLBACK)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep curl pwsh

  local repo_root url rc engine dest out
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t006

  # Create a local ZIP fixture and expose via file:// layout (no network)
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_write_install_wrapper sh

  for engine in sh ps; do
    if [[ "$engine" == "sh" ]]; then
      bh_make_bin_sandbox unzip
    else
      bh_make_bin_sandbox
    fi
    dest="$WORK/target-$engine"; out="$WORK/out-$engine.txt"
    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc=$?
    set -e
    [[ "$rc" -eq 0 ]] || { echo "Install($engine) failed: rc=$rc" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }
    if [[ "$engine" == "sh" ]]; then
      assert_contains "Tools present: curl, tar, python3" "$out"
    fi
    bh_assert_installed "$dest"
  done

  echo "PASS T006 fallback unzip->python3 (sh) and success (ps)"
}

main "$@"
