#!/usr/bin/env bash
# Harness for bootstrap installer tests (identical structure for sh and ps)
# Depends on: tests/contract/lib/bootstrap_test_helpers.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/bootstrap_test_helpers.sh"

# bh_init_workdir TEST_ID -> sets WORK, OUT, DEST, FIXTURE, SRCROOT
bh_init_workdir() {
  local tid=${1:?"usage: bh_init_workdir TEST_ID"}
  local repo_root
  repo_root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  # Use system temp directory instead of repo directory to avoid pollution
  export TEST_TMPDIR=""
  export WORK=$(make_temp_dir "${tid}")
  export OUT="$WORK/out.txt"
  export DEST="$WORK/target"
  export FIXTURE="$WORK/fixture.zip"
  export SRCROOT="$WORK/src"
  mkdir -p "$DEST"
}

# bh_build_fixture_zip REPO_ROOT FIXTURE
bh_build_fixture_zip() {
  local repo_root=${1:?}; local fixture=${2:?}
  python3 - "$repo_root" "$fixture" <<'PY'
import os, sys, zipfile
root = sys.argv[1]
out = sys.argv[2]
top = 'albt-fixture'
overlay_root = os.path.join(root, 'overlay')
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk(overlay_root):
        for f in files:
            full = os.path.join(base, f)
            rel = os.path.relpath(full, overlay_root)
            arc = os.path.join(top, 'overlay', rel)
            z.write(full, arc)
PY
}

# bh_layout_file_url SRCROOT FIXTURE -> prepares GitHub-like layout and echoes file:// URL
bh_layout_file_url() {
  local srcroot=${1:?}; local fixture=${2:?}
  mkdir -p "$srcroot/archive/refs/heads"
  cp "$fixture" "$srcroot/archive/refs/heads/main.zip"
  printf "file://%s\n" "$srcroot"
}

# bh_make_bin_sandbox [hide_tool ...] -> populates $WORK/bin and prepends to PATH
bh_make_bin_sandbox() {
  local hide=("$@")
  local bin="$WORK/bin"; mkdir -p "$bin"
  local old_path="$PATH"
  IFS=':' read -r -a _pdirs <<<"$old_path"
  for p in "${_pdirs[@]}"; do
    [[ -d "$p" ]] || continue
    while IFS= read -r -d '' f; do
      local base; base=$(basename "$f")
      # Skip hidden
      local h; for h in "${hide[@]}"; do [[ "$base" == "$h" ]] && continue 2; done
      # Reserve our own wrapper name
      [[ "$base" == "install" ]] && continue
      [[ -e "$bin/$base" ]] && continue
      ln -s "$f" "$bin/$base" 2>/dev/null || true
    done < <(find "$p" -maxdepth 1 \( -type f -perm -u+x -o -type l \) -print0 2>/dev/null)
  done
  export PATH="$bin"
}

# bh_write_install_wrapper ENGINE REPO_ROOT SRCROOT -> writes $WORK/bin/install
bh_write_install_wrapper() {
  local engine=${1:?}
  local repo_root srcroot
  repo_root="$(cd "$SCRIPT_DIR/../../.." && pwd)"
  srcroot="$SRCROOT"
  local bin="$WORK/bin"; mkdir -p "$bin"
  local wrapper="$bin/install"
  rm -f "$wrapper" 2>/dev/null || true
  cat >"$wrapper" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
engine=${ALBT_ENGINE:-sh}
url=""; ref="main"; dest="."; source_dir="overlay"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine) engine="$2"; shift 2 ;;
    --url) url="$2"; shift 2 ;;
    --ref) ref="$2"; shift 2 ;;
    --dest) dest="$2"; shift 2 ;;
    --source) source_dir="$2"; shift 2 ;;
    *) echo "unknown arg: $1" 1>&2; exit 2 ;;
  esac
done
case "$engine" in
  sh)
    exec bash "__REPO__/bootstrap/install.sh" --url "${url:-https://github.com/FBakkensen/al-build-tools}" --ref "$ref" --dest "$dest" --source "$source_dir"
    ;;
  ps)
    # Write a small PS entry file that stubs IWR and calls the installer
    cat >"__BIN__/ps_entry.ps1" <<'PSE'
param()
function Invoke-WebRequest {
  param([Parameter(Mandatory=$true)][string]$Uri,
        [Parameter(Mandatory=$true)][string]$OutFile,
        [Parameter(ValueFromRemainingArguments=$true)]$Rest)
  $srcroot = $env:SRCROOT
  $src = [System.IO.Path]::Combine($srcroot, 'archive', 'refs', 'heads', 'main.zip')
  Copy-Item -LiteralPath $src -Destination $OutFile -Force
}
$ErrorActionPreference = 'Stop'
. (Join-Path "__REPO__" 'bootstrap' 'install.ps1')
Install-AlBuildTools -Url $env:URL -Ref $env:REF -Dest $env:DESTDIR -Source $env:SRC
PSE
    SRCROOT="__SRCROOT__" URL="$url" REF="$ref" DESTDIR="$dest" SRC="$source_dir" pwsh -NoLogo -NoProfile -File "__BIN__/ps_entry.ps1"
    ;;
  *) echo "unknown engine: $engine" 1>&2; exit 2 ;;
esac
SH
  sed -i "s#__REPO__#${repo_root//\/\\}#g" "$wrapper"
  sed -i "s#__SRCROOT__#${srcroot//\/\\}#g" "$wrapper"
  sed -i "s#__BIN__#${bin//\/\\}#g" "$wrapper"
  chmod +x "$wrapper"
}

bh_assert_installed() {
  local d=${1:?}
  [[ -f "$d/Makefile" ]] || { echo "Missing Makefile in dest" 1>&2; return 1; }
  [[ -f "$d/scripts/make/linux/build.sh" ]] || { echo "Missing linux/build.sh in dest" 1>&2; return 1; }
  [[ -f "$d/scripts/make/windows/build.ps1" ]] || { echo "Missing windows/build.ps1 in dest" 1>&2; return 1; }
}
