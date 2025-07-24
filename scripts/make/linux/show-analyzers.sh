#!/bin/bash
# Linux Show-Analyzers Script - equivalent to Windows show-analyzers.ps1
# Usage: show-analyzers.sh AppDir

AppDir="$1"
if [[ -z "$AppDir" ]]; then
    AppDir="app"
fi

# Source shared libraries
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/json-parser.sh"

# Show enabled analyzers
enabled_analyzers=($(get_enabled_analyzers "$AppDir"))
echo -e "\033[0;36mEnabled analyzers:\033[0m"
for analyzer in "${enabled_analyzers[@]}"; do
    echo "  $analyzer"
done

# Show analyzer DLL paths
analyzer_paths=($(get_enabled_analyzer_paths "$AppDir"))
if [[ ${#analyzer_paths[@]} -gt 0 ]]; then
    echo -e "\033[0;36mAnalyzer DLL paths:\033[0m"
    for analyzer_path in "${analyzer_paths[@]}"; do
        echo "  $analyzer_path"
    done
else
    echo -e "\033[1;33mNo analyzer DLLs found.\033[0m"
fi

exit 0