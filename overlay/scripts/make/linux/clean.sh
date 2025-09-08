#!/bin/bash
# Linux Clean Script - equivalent to Windows clean.ps1
# Usage: clean.sh AppDir

AppDir="$1"
if [[ -z "$AppDir" ]]; then
    AppDir="app"
fi

# Source shared libraries
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/json-parser.sh"

output_path=$(get_output_path "$AppDir")

if [[ -n "$output_path" && -f "$output_path" ]]; then
    if rm -f "$output_path"; then
        echo -e "\033[0;32mRemoved build artifact: $output_path\033[0m"
        exit 0
    else
        echo -e "\033[0;31mFailed to remove build artifact: $output_path\033[0m" >&2
        exit 1
    fi
else
    echo -e "\033[1;33mNo build artifact found to clean ($output_path)\033[0m"
    exit 0
fi