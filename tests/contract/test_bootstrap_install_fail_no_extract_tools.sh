#!/usr/bin/env bash
# T007 Hard failure when both unzip & python3 absent (C-HARD-FAIL, C-EXIT-CODES)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd tar sha256sum find xargs awk grep bash pwsh

  local repo_root rc engine out dest
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t007
  # Prepare fixture and layout for PS path; shell path doesn't use URL in the first run but harmless
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  bh_layout_file_url "$SRCROOT" "$FIXTURE" > /dev/null
  bh_write_install_wrapper sh

  # Shell: simulate no extract tools; PowerShell: corrupt ZIP to fail extraction
  for engine in sh ps; do
    out="$WORK/out-$engine.txt"; dest="$WORK/target-$engine"; mkdir -p "$dest"
    if [[ "$engine" == "sh" ]]; then
      bh_make_bin_sandbox unzip python3
      set +e
      ALBT_ENGINE=sh bash "$WORK/bin/install" --dest "$dest" >"$out" 2>&1
      rc=$?
      set -e
      if [[ "$rc" -eq 0 ]]; then
        echo "FAILED(sh): expected non-zero exit when unzip and python3 missing" 1>&2
        sed -n '1,200p' "$out" 1>&2 || true
        exit 1
      fi
      assert_contains "Need either 'unzip' or 'python3' available to extract the ZIP archive." "$out"
      [[ ! -f "$dest/Makefile" ]] || { echo "FAILED(sh): overlay files should not be installed on failure" 1>&2; exit 1; }
    else
      # Corrupt ZIP for PS run
      bh_make_bin_sandbox
      : > "$SRCROOT/archive/refs/heads/main.zip"
      set +e
      ALBT_ENGINE=ps bash "$WORK/bin/install" --url "file://$SRCROOT" --ref main --dest "$dest" >"$out" 2>&1
      rc=$?
      set -e
      if [[ "$rc" -eq 0 ]]; then
        echo "FAILED(ps): expected non-zero exit on corrupt ZIP" 1>&2
        sed -n '1,200p' "$out" 1>&2 || true
        exit 1
      fi
      [[ ! -f "$dest/Makefile" ]] || { echo "FAILED(ps): overlay files should not be installed on failure" 1>&2; exit 1; }
    fi
  done

  echo "PASS T007 hard fail (sh: tools missing, ps: corrupt ZIP)"
}

main "$@"
