#!/usr/bin/env bash
# T010 Read-only destination failure (C-READONLY, C-EXIT-CODES)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep pwsh

  local repo_root url rc engine dest out
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t010
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_write_install_wrapper sh

  for engine in sh ps; do
    bh_make_bin_sandbox
    dest="$WORK/readonly-dest-$engine"; out="$WORK/out-$engine.txt"
    mkdir -p "$dest"
    chmod 0555 "$dest"
    T010_DEST="$dest"
    trap 'if [[ -n "${T010_DEST:-}" ]]; then chmod -R u+w "$T010_DEST" 2>/dev/null || true; fi' EXIT

    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$out" 2>&1
    rc=$?
    set -e

    if [[ "$rc" -eq 0 ]]; then
      echo "FAILED($engine): expected non-zero exit when destination is read-only" 1>&2
      sed -n '1,200p' "$out" 1>&2 || true
      exit 1
    fi
    if ! grep -Eiq 'permission denied|cannot (open|mkdir)|operation not permitted|denied' "$out"; then
      echo "FAILED($engine): expected a permission error message in output" 1>&2
      sed -n '1,200p' "$out" 1>&2 || true
      exit 1
    fi
    if [[ -f "$dest/Makefile" ]]; then
      echo "FAILED($engine): overlay files should not be present in read-only dest" 1>&2
      exit 1
    fi
  done

  echo "PASS T010 readonly destination failure (sh, ps)"
}

main "$@"
