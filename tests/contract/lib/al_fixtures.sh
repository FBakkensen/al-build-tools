#!/usr/bin/env bash
# Helpers to create minimal AL project fixtures for tests
# Style: bash, set -euo pipefail; portable tools

set -euo pipefail

# al_new_project [PREFIX]
# Creates a fresh temp directory with an `app/` folder and returns its path.
al_new_project() {
  local prefix=${1:-alproj}
  local dir
  if [[ -n "${TEST_TMPDIR:-}" ]]; then
    mkdir -p "$TEST_TMPDIR"
    dir=$(mktemp -d -p "$TEST_TMPDIR" "${prefix}.XXXXXX")
  else
    dir=$(mktemp -d 2>/dev/null || mktemp -d -t "${prefix}")
  fi
  mkdir -p "$dir/app"
  printf '%s\n' "$dir"
}

# al_write_appjson DIR RANGE...
# RANGE syntax: FROM:TO (integers). Example: al_write_appjson "$proj" "50000:50010" "50100:50105"
al_write_appjson() {
  local dir=${1:?"usage: al_write_appjson DIR FROM:TO [FROM:TO ...]"}
  shift
  mkdir -p "$dir/app"
  local json='{"idRanges":['
  local first=1 r from to
  for r in "$@"; do
    from=${r%%:*}
    to=${r##*:}
    if [[ $first -eq 0 ]]; then json+=','; fi
    json+="{\"from\":${from},\"to\":${to}}"
    first=0
  done
  json+=']}'
  printf '%s\n' "$json" >"$dir/app/app.json"
}

# al_add_object DIR TYPE NUMBER NAME
# Writes a minimal AL object file containing a declaration line like: "page 50000 MyPage { }"
al_add_object() {
  local dir=${1:?}; local type=${2:?}; local num=${3:?}; local name=${4:?}
  local d="$dir/app/$(printf '%ss' "${type,,}")"
  mkdir -p "$d"
  local file="$d/${type}_${num}_${name}.al"
  {
    printf '%s %s %s {\n' "$type" "$num" "$name"
    printf '  // minimal test object\n'
    printf '}\n'
  } >"$file"
}

