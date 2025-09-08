#!/usr/bin/env bash
# filepath: Scripts/next-object-number.sh

if [ $# -ne 1 ]; then
  echo "Usage: $0 <objecttype>"
  exit 1
fi

objtype="$1"
appjson="app/app.json"

# Get ranges from app.json
fromto=($(grep -Po '"from":\s*\d+|"to":\s*\d+' "$appjson" | awk '{print $2}'))

# Find used numbers for the given object type
used=$(grep -rhoP "$objtype\s+\d+" app/ | awk '{print $2}' | sort -n)

found=0
for ((j=0; j<${#fromto[@]}; j+=2)); do
  from=${fromto[j]}
  to=${fromto[j+1]}
  for ((i=from; i<=to; i++)); do
    if ! echo "$used" | grep -qx "$i"; then
      echo "$i"
      found=1
      break 2
    fi
  done
done

if [[ $found -eq 0 ]]; then
  echo "No available $objtype number found in the specified ranges."
  exit 2
fi