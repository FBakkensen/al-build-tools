#!/usr/bin/env bash
# T005 Custom destination creation (C-CUSTOM-DEST)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep

  local repo_root url rc dest
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t005
  dest="$WORK/deep/nested/custom/dest"
  # Ensure destination does not exist
  [[ ! -e "$dest" ]] || { echo "Test setup failed: dest already exists" 1>&2; exit 2; }

  # Create a local ZIP fixture of overlay and expose via file:// layout
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_make_bin_sandbox
  bh_write_install_wrapper sh

  set +e
  ALBT_ENGINE=sh bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest" >"$OUT" 2>&1
  rc=$?
  set -e
  [[ "$rc" -eq 0 ]] || { echo "Install failed: rc=$rc" 1>&2; sed -n '1,200p' "$OUT" 1>&2; exit 1; }

  # Assertions: directory created and populated; reporting present
  [[ -d "$dest" ]] || { echo "Destination directory not created" 1>&2; exit 1; }
  bh_assert_installed "$dest"
  assert_contains "Install/update from" "$OUT"
  assert_contains "Completed: overlay from" "$OUT"

  echo "PASS T005 custom destination creation"
}

main "$@"
