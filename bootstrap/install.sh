#!/usr/bin/env bash
# Bootstrap installer for al-build-tools (install = update)
# Copies overlay/* from the GitHub repo into the target git project directory.
#
# Requirements: bash, curl, tar
# Usage (default ref=main, dest=.):
#   curl -fsSL https://raw.githubusercontent.com/FBakkensen/al-build-tools/main/bootstrap/install.sh | \
#     bash -s -- --dest .
#
# Optional flags:
#   --url <repo-url>   Override source repo URL (default baked in)
#   --ref <ref>        Branch or tag to fetch (default: main)
#   --dest <path>      Destination directory (default: .)
#   --source <subdir>  Subfolder to copy from archive (default: overlay)

set -euo pipefail
IFS=$'\n\t'

DEFAULT_URL="https://github.com/FBakkensen/al-build-tools"
DEFAULT_REF="main"
DEFAULT_DEST="."
DEFAULT_SOURCE="overlay"

url="$DEFAULT_URL"
ref="$DEFAULT_REF"
dest="$DEFAULT_DEST"
source_dir="$DEFAULT_SOURCE"

print_err() { printf "[al-build-tools] %s\n" "$*" 1>&2; }

usage() {
  cat 1>&2 <<EOF
Usage: install.sh [--url URL] [--ref REF] [--dest DIR] [--source SUBDIR]

Copies SUBDIR (default: overlay) from the al-build-tools repo archive at REF
into DIR (default: .). Running again updates by overwriting the same files.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) url="$2"; shift 2 ;;
    --ref) ref="$2"; shift 2 ;;
    --dest) dest="$2"; shift 2 ;;
    --source) source_dir="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) print_err "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

# Dependency checks
for bin in curl tar; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    print_err "Required tool '$bin' not found in PATH."; exit 1
  fi
done

# Resolve absolute destination path
dest_abs=$(cd "$dest" 2>/dev/null && pwd || true)
if [[ -z "$dest_abs" ]]; then
  mkdir -p "$dest"
  dest_abs=$(cd "$dest" && pwd)
fi

echo "[al-build-tools] Installing from $url@$ref into $dest_abs (source: $source_dir)"

# Non-fatal check: is destination a git repo?
if ! git -C "$dest_abs" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ ! -d "$dest_abs/.git" ]]; then
    print_err "Warning: destination '$dest_abs' does not look like a git repo. Proceeding anyway."
  fi
fi

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t albt)
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/src.tar.gz"

base="$url"
try_urls=(
  "$base/archive/refs/heads/$ref.tar.gz"
  "$base/archive/refs/tags/$ref.tar.gz"
  "$base/archive/$ref.tar.gz"
)

downloaded=false
for u in "${try_urls[@]}"; do
  if curl -fsSL "$u" -o "$archive"; then
    downloaded=true
    break
  fi
done

if [[ "$downloaded" != true ]]; then
  print_err "Failed to download repo archive for ref '$ref' from $url."; exit 1
fi

# Find top-level folder name inside the tarball without extracting fully
first_entry=$(tar -tzf "$archive" | sed -n '1p')
top=${first_entry%%/*}
if [[ -z "$top" ]]; then
  print_err "Archive appears empty or unreadable."; exit 1
fi

# Extract and copy overlay content
tar -xzf "$archive" -C "$tmpdir"
src_dir="$tmpdir/$top/$source_dir"
if [[ ! -d "$src_dir" ]]; then
  print_err "Expected subfolder '$source_dir' not found in archive at ref '$ref'."; exit 1
fi

mkdir -p "$dest_abs"
# Copy contents of source_dir into destination; overwrite existing files
cp -a "$src_dir/." "$dest_abs/"

echo "[al-build-tools] Copied '$source_dir' from $url@$ref into $dest_abs"
