#!/usr/bin/env bash
# T011 PowerShell parity (C-POWERSHELL-PARITY)
# Bash test that executes install.ps1 via the same bin/install wrapper.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd python3 tar sha256sum find xargs awk grep pwsh

  local repo_root url rc
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t011
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_make_bin_sandbox
  bh_write_install_wrapper ps

  set +e
  ALBT_ENGINE=ps bash "$WORK/bin/install" --url "$url" --ref main --dest "$DEST" >"$OUT" 2>&1
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    echo "FAILED: expected pwsh exit 0, got $rc" 1>&2
    sed -n '1,200p' "$OUT" 1>&2 || true
    exit 1
  fi

  # Debug visibility of tree on failures in CI
  echo "DEST tree:" >>"$OUT"; find "$DEST" -maxdepth 3 -type f -print >>"$OUT" 2>&1 || true

  bh_assert_installed "$DEST"
  assert_contains "Completed: overlay from" "$OUT"

  echo "PASS T011 PowerShell parity basic install"
}

main "$@"
