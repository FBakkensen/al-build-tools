#!/usr/bin/env bash
# Common helpers for bootstrap installer contract tests
# Style: bash, set -euo pipefail; portable POSIX tools where possible

set -euo pipefail

# Globals used for PATH sandboxing and cleanup
_TEST_OLD_PATH=""
_TEST_HIDE_BIN_DIR=""
_TEST_REGISTERED_DIRS=()

# require_cmd cmd ...  -> ensure commands exist (fail fast with message)
require_cmd() {
  for _c in "$@"; do
    if ! command -v "$_c" >/dev/null 2>&1; then
      printf "[test] missing required command: %s\n" "$_c" 1>&2
      exit 127
    fi
  done
}

# setup_cleanup_trap  -> installs a single EXIT trap to delete registered dirs
setup_cleanup_trap() {
  # Only install once
  if [[ "${_TEST_TRAP_INSTALLED:-}" == "1" ]]; then return 0; fi
  _TEST_TRAP_INSTALLED=1
  trap '__test_cleanup' EXIT
}

__test_cleanup() {
  # Restore PATH sandbox if active
  restore_path || true
  # Remove any registered temp dirs
  if [[ ${#_TEST_REGISTERED_DIRS[@]} -gt 0 ]]; then
    for _d in "${_TEST_REGISTERED_DIRS[@]}"; do
      [[ -n "$_d" && -d "$_d" ]] && rm -rf "$_d" || true
    done
    _TEST_REGISTERED_DIRS=()
  fi
}

# hide_tool tool [tool ...]
# Creates a PATH sandbox containing symlinks to all currently discoverable
# executables EXCEPT the named tools. This ensures `command -v <tool>` fails
# without removing critical directories like /usr/bin from PATH.
hide_tool() {
  if [[ $# -lt 1 ]]; then
    printf "[test] hide_tool: expected at least one tool to hide\n" 1>&2
    exit 2
  fi

  # No-op if already sandboxed; allow stacking by reusing the current sandbox
  if [[ -z "${_TEST_HIDE_BIN_DIR:-}" ]]; then
    _TEST_HIDE_BIN_DIR=$(make_temp_dir albt-hidebin)
  fi

  # Remember original PATH once
  if [[ -z "${_TEST_OLD_PATH:-}" ]]; then
    _TEST_OLD_PATH="$PATH"
  fi

  # Build a set of names to hide
  local hidden="|"
  local t
  for t in "$@"; do
    hidden+="$t|"
  done

  # Populate the sandbox bin with symlinks for all resolvable commands,
  # excluding the hidden ones. First occurrence wins.
  IFS=':' read -r -a _pdirs <<<"$PATH"
  for p in "${_pdirs[@]}"; do
    # Skip non-directories
    [[ -d "$p" ]] || continue
    # Iterate executables in this PATH element
    # Use find to be safe with large directories
    while IFS= read -r -d '' f; do
      local base
      base=$(basename "$f")
      # Skip if hidden or already linked
      if printf "%s" "$hidden" | grep -Fq "|${base}|"; then
        continue
      fi
      if [[ ! -e "$_TEST_HIDE_BIN_DIR/$base" ]]; then
        ln -s "$f" "$_TEST_HIDE_BIN_DIR/$base" 2>/dev/null || true
      fi
    done < <(find "$p" -maxdepth 1 -type f -perm -u+x -print0 2>/dev/null)
  done

  # Ensure essential tools are available in the sandbox even if not discovered
  # from PATH scanning above (some images have atypical PATH contents).
  local need
  for need in bash curl tar python3 find xargs awk sha256sum grep sed head tail sort tr wc mktemp; do
    # Skip if this tool is intentionally hidden
    if printf "%s" "$hidden" | grep -Fq "|${need}|"; then
      continue
    fi
    if [[ ! -e "$_TEST_HIDE_BIN_DIR/$need" ]]; then
      local real
      real=$(command -v "$need" 2>/dev/null || true)
      if [[ -n "$real" ]]; then
        ln -s "$real" "$_TEST_HIDE_BIN_DIR/$need" 2>/dev/null || true
      fi
    fi
  done

  export PATH="$_TEST_HIDE_BIN_DIR"
}

# restore_path -> restores original PATH and removes sandbox directory
restore_path() {
  if [[ -n "${_TEST_OLD_PATH:-}" ]]; then
    export PATH="$_TEST_OLD_PATH"
    _TEST_OLD_PATH=""
  fi
  if [[ -n "${_TEST_HIDE_BIN_DIR:-}" && -d "$_TEST_HIDE_BIN_DIR" ]]; then
    rm -rf "$_TEST_HIDE_BIN_DIR" || true
    _TEST_HIDE_BIN_DIR=""
  fi
}

# calc_dir_hashes DIR
# Emits a stable SHA256 digest representing the directory contents (paths + file hashes).
# Ignores directories; includes regular files. Empty dir produces the hash of empty input.
calc_dir_hashes() {
  local dir=${1:?"usage: calc_dir_hashes DIR"}
  if [[ ! -d "$dir" ]]; then
    printf "[test] calc_dir_hashes: not a directory: %s\n" "$dir" 1>&2
    return 2
  fi
  (
    cd "$dir"
    # List files with relative paths, sort for determinism, hash each, then hash the list
    find . -type f -print0 | sort -z | \
      xargs -0 -I{} sh -c 'sha256sum "{}" | awk -v p="{}" "{print p \" \" $1}"' | \
      sha256sum | awk '{print $1}'
  )
}

# Allow tests to choose an exec-enabled temp root (some CI mounts /tmp noexec).
# If TEST_TMPDIR is set, prefer it when creating new temp dirs.
make_temp_dir() {
  local prefix=${1:-albt}
  local d
  if [[ -n "${TEST_TMPDIR:-}" ]]; then
    mkdir -p "$TEST_TMPDIR"
    d=$(mktemp -d -p "$TEST_TMPDIR" "${prefix}.XXXXXX")
  else
    d=$(mktemp -d 2>/dev/null || mktemp -d -t "${prefix}")
  fi
  _TEST_REGISTERED_DIRS+=("$d")
  setup_cleanup_trap
  printf "%s\n" "$d"
}

# assert_contains NEEDLE TARGET
# TARGET can be a file path or a string literal. Uses fixed-string search.
assert_contains() {
  local needle=${1:?"usage: assert_contains NEEDLE TARGET"}
  local target=${2:?"usage: assert_contains NEEDLE TARGET"}
  if [[ -f "$target" ]]; then
    if ! grep -Fq -- "$needle" "$target"; then
      printf "[assert] expected to find: %s\n[file] %s\n" "$needle" "$target" 1>&2
      return 1
    fi
  else
    if ! printf "%s" "$target" | grep -Fq -- "$needle"; then
      printf "[assert] expected to find: %s\n[text] %s\n" "$needle" "$target" 1>&2
      return 1
    fi
  fi
}

# assert_not_contains NEEDLE TARGET
assert_not_contains() {
  local needle=${1:?"usage: assert_not_contains NEEDLE TARGET"}
  local target=${2:?"usage: assert_not_contains NEEDLE TARGET"}
  if [[ -f "$target" ]]; then
    if grep -Fq -- "$needle" "$target"; then
      printf "[assert] did not expect to find: %s\n[file] %s\n" "$needle" "$target" 1>&2
      return 1
    fi
  else
    if printf "%s" "$target" | grep -Fq -- "$needle"; then
      printf "[assert] did not expect to find: %s\n[text] %s\n" "$needle" "$target" 1>&2
      return 1
    fi
  fi
}

# End of file
