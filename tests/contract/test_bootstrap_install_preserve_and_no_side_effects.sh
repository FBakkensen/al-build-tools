#!/usr/bin/env bash
# T008 Preserve unrelated files & no external side effects (C-PRESERVE, C-NO-SIDE-EFFECTS)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep pwsh

  local repo_root url rc engine dest out sentinel_dir sentinel_file sentinel_hash pre_unrelated_hash post_unrelated_hash post_sentinel_hash
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t008
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_write_install_wrapper sh

  for engine in sh ps; do
    bh_make_bin_sandbox
    dest="$WORK/target-$engine"; out="$WORK/out-$engine.txt"; sentinel_dir="$WORK/outside-sentinel-$engine"; sentinel_file="$sentinel_dir/s.txt"
    mkdir -p "$dest" "$sentinel_dir"
    mkdir -p "$dest/custom"
    echo "keep-me" > "$dest/custom/unrelated.txt"
    pre_unrelated_hash=$(sha256sum "$dest/custom/unrelated.txt" | awk '{print $1}')
    echo "outside-stays" > "$sentinel_file"
    sentinel_hash=$(sha256sum "$sentinel_file" | awk '{print $1}')

    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc=$?
    set -e
    [[ "$rc" -eq 0 ]] || { echo "Install($engine) failed: rc=$rc" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }

    [[ -f "$dest/custom/unrelated.txt" ]] || { echo "Unrelated file missing after install ($engine)" 1>&2; exit 1; }
    post_unrelated_hash=$(sha256sum "$dest/custom/unrelated.txt" | awk '{print $1}')
    if [[ "$pre_unrelated_hash" != "$post_unrelated_hash" ]]; then
      echo "Unrelated file content changed ($engine)" 1>&2
      exit 1
    fi
    bh_assert_installed "$dest"
    post_sentinel_hash=$(sha256sum "$sentinel_file" | awk '{print $1}')
    if [[ "$sentinel_hash" != "$post_sentinel_hash" ]]; then
      echo "Outside sentinel modified unexpectedly ($engine)" 1>&2
      exit 1
    fi
  done

  echo "PASS T008 preserve + no side effects (sh, ps)"
}

main "$@"
