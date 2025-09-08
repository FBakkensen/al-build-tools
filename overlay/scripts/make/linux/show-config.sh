#!/bin/bash
# Linux Show-Config Script - equivalent to Windows show-config.ps1
# Usage: show-config.sh AppDir

AppDir="$1"
if [[ -z "$AppDir" ]]; then
    AppDir="app"
fi

# Source shared libraries
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/json-parser.sh"

# Check app.json configuration
if get_app_json_object "$AppDir" >/dev/null; then
    app_json_path=$(get_app_json_path "$AppDir")
    echo -e "\033[0;36mApp.json configuration:\033[0m"
    
    name=$(jq -r '.name // "Unknown"' "$app_json_path" 2>/dev/null)
    publisher=$(jq -r '.publisher // "Unknown"' "$app_json_path" 2>/dev/null)
    version=$(jq -r '.version // "Unknown"' "$app_json_path" 2>/dev/null)
    
    echo "  Name: $name"
    echo "  Publisher: $publisher"
    echo "  Version: $version"
else
    echo -e "\033[0;31mERROR: app.json not found or invalid.\033[0m"
fi

# Check settings.json configuration
if get_settings_json_object "$AppDir" >/dev/null; then
    settings_path=$(get_settings_json_path "$AppDir")
    echo -e "\033[0;36mSettings.json configuration:\033[0m"
    
    analyzers=$(jq -r '.["al.codeAnalyzers"] // empty' "$settings_path" 2>/dev/null)
    if [[ -n "$analyzers" && "$analyzers" != "null" ]]; then
        echo "  Analyzers: $analyzers"
    else
        echo "  Analyzers: (default: CodeCop, UICop)"
    fi
else
    echo -e "\033[1;33mNo .vscode/settings.json found or invalid.\033[0m"
fi

exit 0