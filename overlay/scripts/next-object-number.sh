#!/usr/bin/env bash
# filepath: scripts/next-object-number.sh
# Purpose: Print the next available AL object number for a given object type
#          according to idRanges in app/app.json. Exits 2 if range exhausted.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <objecttype>" 1>&2
  exit 1
fi

objtype="$1"
appjson="app/app.json"

if [[ ! -f "$appjson" ]]; then
  echo "No available $objtype number found in the specified ranges." 1>&2
  exit 2
fi

# Extract ranges using PCRE, capturing only digits after from/to keys
# Produces a flat array: from1 to1 from2 to2 ...
mapfile -t fromto < <(grep -Po '"(?:from|to)"\s*:\s*\K\d+' "$appjson" 2>/dev/null || true)

if [[ ${#fromto[@]} -lt 2 || $(( ${#fromto[@]} % 2 )) -ne 0 ]]; then
  echo "No available $objtype number found in the specified ranges." 1>&2
  exit 2
fi

# Find used numbers for the given object type in .al files only
used=$( { grep -rhoP --include='*.al' "\\b${objtype}\\s+\\d+\\b" app/ 2>/dev/null || true; } | awk '{print $2}' | sort -n | uniq)

found=0
for ((j=0; j<${#fromto[@]}; j+=2)); do
  from=${fromto[j]}
  to=${fromto[j+1]}
  # Ensure numeric
  : "$from" "$to"
  for ((i=from; i<=to; i++)); do
    if ! printf '%s\n' "$used" | grep -qx "$i"; then
      printf '%s\n' "$i"
      found=1
      break 2
    fi
  done
done

if [[ $found -eq 0 ]]; then
  echo "No available $objtype number found in the specified ranges." 1>&2
  exit 2
fi
