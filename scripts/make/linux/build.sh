#!/bin/bash
# Linux Build Script - equivalent to Windows build.ps1
# Usage: build.sh AppDir

AppDir="$1"
if [[ -z "$AppDir" ]]; then
    AppDir="app"
fi

# Source shared libraries
source "$(dirname "$0")/lib/common.sh"
source "$(dirname "$0")/lib/json-parser.sh"

# Diagnostic: Confirm function availability (equivalent to Windows version)
if ! type get_enabled_analyzer_paths &>/dev/null; then
    write_error_and_exit "ERROR: get_enabled_analyzer_paths is not available after import!"
fi

# Discover AL compiler
alc_path=$(get_al_compiler_path "$AppDir")
if [[ -z "$alc_path" ]]; then
    write_error_and_exit "AL Compiler not found. Please ensure AL extension is installed in VS Code."
fi

# Get enabled analyzer DLL paths
analyzer_paths=($(get_enabled_analyzer_paths "$AppDir"))

# Get output and package cache paths
output_full_path=$(get_output_path "$AppDir")
if [[ -z "$output_full_path" ]]; then
    write_error_and_exit "[ERROR] Output path could not be determined. Check app.json and get_output_path function."
fi

package_cache_path=$(get_package_cache_path "$AppDir")
if [[ -z "$package_cache_path" ]]; then
    write_error_and_exit "[ERROR] Package cache path could not be determined."
fi

# Clean up any existing output file
if [[ -f "$output_full_path" ]]; then
    if ! rm -f "$output_full_path"; then
        write_error_and_exit "[ERROR] Failed to remove ${output_full_path}"
    fi
fi

# Also check and remove any directory with the same name as the output file
if [[ -d "$output_full_path" ]]; then
    if ! rm -rf "$output_full_path"; then
        write_error_and_exit "[ERROR] Failed to remove conflicting directory ${output_full_path}"
    fi
fi

# Get app name and version for display
app_json_path=$(get_app_json_path "$AppDir")
app_name=$(jq -r '.name // "Unknown App"' "$app_json_path" 2>/dev/null)
app_version=$(jq -r '.version // "1.0.0.0"' "$app_json_path" 2>/dev/null)
output_file=$(basename "$output_full_path")

echo -e "\033[0;32mBuilding ${app_name} v${app_version}...\033[0m"

if [[ ${#analyzer_paths[@]} -gt 0 ]]; then
    echo "Using analyzers from settings.json:"
    for analyzer_path in "${analyzer_paths[@]}"; do
        echo "  - $analyzer_path"
    done
    echo ""
else
    echo "No analyzers found or enabled in settings.json"
    echo ""
fi

# Make sure AL compiler is executable
if [[ ! -x "$alc_path" ]]; then
    chmod +x "$alc_path"
fi

# Build analyzer arguments correctly
cmd_args=("/project:$AppDir" "/out:$output_full_path" "/packagecachepath:$package_cache_path")
for analyzer_path in "${analyzer_paths[@]}"; do
    cmd_args+=("/analyzer:$analyzer_path")
done

# Execute AL compiler
"$alc_path" "${cmd_args[@]}"
exit_code=$?

echo ""
if [[ $exit_code -ne 0 ]]; then
    echo -e "\033[0;31mBuild failed with errors above.\033[0m" >&2
else
    echo -e "\033[0;32mBuild completed successfully: $output_file\033[0m"
fi

exit $exit_code