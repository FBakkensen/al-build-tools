#!/usr/bin/env bash
# T004 Git vs non-git warning & metadata preservation (C-GIT, C-GIT-METADATA)

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$TEST_DIR/lib/bootstrap_test_helpers.sh"
. "$TEST_DIR/lib/bootstrap_harness.sh"

main() {
  require_cmd git python3 tar sha256sum find xargs awk grep pwsh

  local repo_root url rcA rcB dest_nogit dest_git pre_git_hash post_git_hash engine out
  repo_root="$(cd "$TEST_DIR/../.." && pwd)"
  bh_init_workdir albt-t004
  bh_build_fixture_zip "$repo_root" "$FIXTURE"
  url=$(bh_layout_file_url "$SRCROOT" "$FIXTURE")
  bh_make_bin_sandbox
  bh_write_install_wrapper sh

  for engine in sh ps; do
    dest_nogit="$(mktemp -d)"; _TEST_REGISTERED_DIRS+=("$dest_nogit")
    dest_git="$WORK/dest-git-$engine"; mkdir -p "$dest_git"
    out="$WORK/out-$engine.txt"

    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest_nogit" >"$out" 2>&1
    rcA=$?
    set -e
    [[ "$rcA" -eq 0 ]] || { echo "Non-git run($engine) failed: rc=$rcA" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }
    assert_contains "does not look like a git repo" "$out"
    [[ -f "$dest_nogit/Makefile" ]] || { echo "Missing Makefile in non-git dest ($engine)" 1>&2; exit 1; }

    (cd "$dest_git" && git init -q)
    pre_git_hash=$(calc_dir_hashes "$dest_git/.git")
    set +e
    ALBT_ENGINE="$engine" bash "$WORK/bin/install" --url "$url" --ref main --dest "$dest_git" >"$out" 2>&1
    rcB=$?
    set -e
    [[ "$rcB" -eq 0 ]] || { echo "Git run($engine) failed: rc=$rcB" 1>&2; sed -n '1,200p' "$out" 1>&2; exit 1; }
    assert_not_contains "does not look like a git repo" "$out"
    post_git_hash=$(calc_dir_hashes "$dest_git/.git")
    if [[ "$pre_git_hash" != "$post_git_hash" ]]; then
      echo ".git metadata changed unexpectedly ($engine)" 1>&2
      echo "pre=$pre_git_hash" 1>&2
      echo "post=$post_git_hash" 1>&2
      exit 1
    fi
  done

  echo "PASS T004 git context behaviors (sh, ps)"
}

main "$@"
