#!/bin/bash
# Linux Show-Analyzers Script - equivalent to Windows show-analyzers.ps1
# Usage: show-analyzers.sh AppDir

AppDir="$1"
if [[ -z "$AppDir" ]]; then
    AppDir="app"
fi

# Source shared libraries
# shellcheck source=./lib/common.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/lib/common.sh"
# shellcheck source=./lib/json-parser.sh
# shellcheck disable=SC1091
source "$(dirname "$0")/lib/json-parser.sh"

# Show enabled analyzers
mapfile -t enabled_analyzers < <(get_enabled_analyzers "$AppDir")
echo -e "\033[0;36mEnabled analyzers:\033[0m"
if [[ ${#enabled_analyzers[@]} -gt 0 ]]; then
    for analyzer in "${enabled_analyzers[@]}"; do
        echo "  $analyzer"
    done
else
    echo "  (none)"
fi

# Show analyzer DLL paths
mapfile -t analyzer_paths < <(get_enabled_analyzer_paths "$AppDir")
if [[ ${#analyzer_paths[@]} -gt 0 ]]; then
    echo -e "\033[0;36mAnalyzer DLL paths:\033[0m"
    for analyzer_path in "${analyzer_paths[@]}"; do
        echo "  $analyzer_path"
    done
else
    echo -e "\033[1;33mNo analyzer DLLs found.\033[0m"
fi

exit 0
