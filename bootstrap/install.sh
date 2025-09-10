#!/usr/bin/env bash
# Bootstrap installer for al-build-tools (install = update)
# Copies overlay/* from the GitHub repo into the target git project directory.
#
# Requirements: bash, curl, tar, and either unzip or python3
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

# Pretty output helpers
supports_color() { [[ -t 1 ]] && command -v tput >/dev/null 2>&1 && [[ $(tput colors 2>/dev/null || echo 0) -ge 8 ]]; }
if supports_color; then
  BOLD="\033[1m"; DIM="\033[2m"; RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; CYAN="\033[36m"; RESET="\033[0m"
else
  BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; CYAN=""; RESET=""
fi
note() { printf "%b[al-build-tools]%b %b\n" "$CYAN" "$RESET" "$*"; }
ok()   { printf "%b[ok]%b %b\n" "$GREEN" "$RESET" "$*"; }
warn() { printf "%b[warn]%b %b\n" "$YELLOW" "$RESET" "$*" 1>&2; }
fail(){ printf "%b[error]%b %b\n" "$RED" "$RESET" "$*" 1>&2; exit 1; }
stepno=0
step(){ stepno=$((stepno+1)); printf "%b%s%b %b\n" "$BOLD" "[$stepno]" "$RESET" "$*"; }

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

step "Resolve destination"
# Resolve absolute destination path
dest_abs=$(cd "$dest" 2>/dev/null && pwd || true)
if [[ -z "$dest_abs" ]]; then
  mkdir -p "$dest"
  dest_abs=$(cd "$dest" && pwd)
fi
note "Install/update from $url@$ref into $dest_abs (source: $source_dir)"

step "Check prerequisites"
# Always require curl and tar (tar is used for robust copy of dotfiles)
for bin in curl tar; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    fail "Required tool '$bin' not found in PATH."
  fi
done
# Need either unzip or python3 for extracting the GitHub ZIP archive
if command -v unzip >/dev/null 2>&1; then
  extractor="unzip"
elif command -v python3 >/dev/null 2>&1; then
  extractor="python3"
else
  fail "Need either 'unzip' or 'python3' available to extract the ZIP archive."
fi
ok "Tools present: curl, tar, $extractor"

step "Detect git repository"
# Non-fatal check: is destination a git repo?
if ! git -C "$dest_abs" rev-parse --git-dir >/dev/null 2>&1; then
  if [[ ! -d "$dest_abs/.git" ]]; then
    warn "Destination '$dest_abs' does not look like a git repo. Proceeding anyway."
  fi
fi
ok "Working in: $dest_abs"

tmpdir=$(mktemp -d 2>/dev/null || mktemp -d -t albt)
trap 'rm -rf "$tmpdir"' EXIT

zipfile="$tmpdir/src.zip"
base="$url"
zurls=(
  "$base/archive/refs/heads/$ref.zip"
  "$base/archive/refs/tags/$ref.zip"
  "$base/archive/$ref.zip"
)

step "Download repository archive (ZIP)"
downloaded=false
for zu in "${zurls[@]}"; do
  note "Downloading (zip): $zu"
  if curl -fsSL "$zu" -o "$zipfile"; then
    downloaded=true
    break
  fi
done
if [[ "$downloaded" != true ]]; then
  fail "Failed to download ZIP archive for ref '$ref' from $url."
fi

step "Extract and locate '$source_dir'"
src_dir=""
# Extract the downloaded ZIP and locate the requested subfolder
mkdir -p "$tmpdir/z"
if [[ "$extractor" == "unzip" ]]; then
  unzip -q "$zipfile" -d "$tmpdir/z"
else
  python3 - "$zipfile" "$tmpdir/z" <<'PY'
import sys, zipfile, os
zf_path, out_dir = sys.argv[1], sys.argv[2]
os.makedirs(out_dir, exist_ok=True)
with zipfile.ZipFile(zf_path) as zf:
    zf.extractall(out_dir)
PY
fi
topdir=$(find "$tmpdir/z" -mindepth 1 -maxdepth 1 -type d | head -n1)
candidate="$topdir/$source_dir"
if [[ -d "$candidate" ]]; then src_dir="$candidate"; fi

# Last-chance: try to locate the source dir anywhere under extraction
if [[ -z "$src_dir" ]]; then
  alt=$(find "$tmpdir" -maxdepth 3 -type d -name "$source_dir" | head -n1 || true)
  if [[ -n "$alt" ]]; then src_dir="$alt"; fi
fi

if [[ -z "$src_dir" ]]; then
  fail "Could not locate '$source_dir' in downloaded archive(s) for ref '$ref'."
fi
ok "Source directory: $src_dir"

step "Copy files into destination"
mkdir -p "$dest_abs"
# Count files/dirs before copy for a friendly summary
files=$(find "$src_dir" -type f | wc -l | tr -d ' ')
dirs=$(find "$src_dir" -type d | wc -l | tr -d ' ')
# Robust copy including dotfiles (e.g., .github): tar stream from src -> dest
tar -C "$src_dir" -cf - . | tar -C "$dest_abs" -xpf -
ok "Copied $files files across $dirs directories"

note "Completed: $source_dir from $url@$ref into $dest_abs"
