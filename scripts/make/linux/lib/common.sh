# Linux Common Utilities Library - equivalent to Windows common.ps1
# Bash functions for AL project operations

# Function: get_app_json_path
# Find app.json location - equivalent to Get-AppJsonPath
# Returns the path to app.json or empty if not found
get_app_json_path() {
    local app_dir="$1"
    local app_json_path1="${app_dir}/app.json"
    local app_json_path2="app.json"
    
    if [[ -f "$app_json_path1" ]]; then
        echo "$app_json_path1"
    elif [[ -f "$app_json_path2" ]]; then
        echo "$app_json_path2"
    else
        echo ""
    fi
}

# Function: get_settings_json_path  
# Find .vscode/settings.json location - equivalent to Get-SettingsJsonPath
# Returns the path to settings.json or empty if not found
get_settings_json_path() {
    local app_dir="$1"
    local settings_path="${app_dir}/.vscode/settings.json"
    
    if [[ -f "$settings_path" ]]; then
        echo "$settings_path"
    elif [[ -f ".vscode/settings.json" ]]; then
        echo ".vscode/settings.json"
    else
        echo ""
    fi
}

# Function: get_output_path
# Calculate output .app file path - equivalent to Get-OutputPath
# Returns the full path to the expected output .app file
get_output_path() {
    local app_dir="$1"
    local app_json
    app_json=$(get_app_json_path "$app_dir")
    
    if [[ -z "$app_json" ]]; then
        echo ""
        return
    fi
    
    # Check if jq is available
    if ! command -v jq &> /dev/null; then
        echo ""
        return
    fi
    
    # Parse JSON fields with defaults
    local name version publisher
    name=$(jq -r '.name // "CopilotAllTablesAndFields"' "$app_json" 2>/dev/null)
    version=$(jq -r '.version // "1.0.0.0"' "$app_json" 2>/dev/null)
    publisher=$(jq -r '.publisher // "FBakkensen"' "$app_json" 2>/dev/null)
    
    # Handle jq parsing failures
    if [[ -z "$name" || "$name" == "null" ]]; then name="CopilotAllTablesAndFields"; fi
    if [[ -z "$version" || "$version" == "null" ]]; then version="1.0.0.0"; fi
    if [[ -z "$publisher" || "$publisher" == "null" ]]; then publisher="FBakkensen"; fi
    
    local output_file="${publisher}_${name}_${version}.app"
    echo "${app_dir}/${output_file}"
}

# Function: get_package_cache_path
# Get package cache path - equivalent to Get-PackageCachePath
# Returns the path to .alpackages directory
get_package_cache_path() {
    local app_dir="$1"
    echo "${app_dir}/.alpackages"
}

# Function: write_error_and_exit
# Error handling - equivalent to Write-ErrorAndExit
# Prints error message in red and exits with code 1
write_error_and_exit() {
    local message="$1"
    echo -e "\033[0;31m${message}\033[0m" >&2
    exit 1
}

# Function: get_highest_version_al_extension
# Find the highest version AL extension - equivalent to Get-HighestVersionALExtension
# Returns the path to the highest version AL extension directory
get_highest_version_al_extension() {
    local al_ext_locations=(
        "$HOME/.vscode/extensions"
        "$HOME/.vscode-server/extensions"
    )
    
    local highest_path=""
    local highest_version="0.0.0"
    
    for location in "${al_ext_locations[@]}"; do
        if [[ -d "$location" ]]; then
            for ext_dir in "$location"/ms-dynamics-smb.al-*; do
                if [[ -d "$ext_dir" ]]; then
                    local dir_name
                    dir_name=$(basename "$ext_dir")
                    if [[ $dir_name =~ ms-dynamics-smb\.al-([0-9]+\.[0-9]+\.[0-9]+) ]]; then
                        local version="${BASH_REMATCH[1]}"
                        # Simple version comparison (works for most cases)
                        if [[ $(printf '%s\n' "$version" "$highest_version" | sort -V | tail -n1) == "$version" && "$version" != "$highest_version" ]]; then
                            highest_version="$version"
                            highest_path="$ext_dir"
                        fi
                    fi
                fi
            done
        fi
    done
    
    echo "$highest_path"
}

# Function: get_al_compiler_path
# Discover AL compiler path - equivalent to Get-ALCompilerPath
# Returns the path to alc binary or empty if not found
get_al_compiler_path() {
    local app_dir="$1"
    local al_ext_path
    al_ext_path=$(get_highest_version_al_extension)
    
    if [[ -n "$al_ext_path" ]]; then
        local alc_path="${al_ext_path}/bin/linux/alc"
        if [[ -f "$alc_path" ]]; then
            echo "$alc_path"
            return
        fi
    fi
    
    echo ""
}

# Function: get_enabled_analyzer_paths
# Get enabled analyzer DLL paths - equivalent to Get-EnabledAnalyzerPaths
# Returns array of analyzer DLL paths based on settings.json configuration
get_enabled_analyzer_paths() {
    local app_dir="$1"
    local settings_path
    settings_path=$(get_settings_json_path "$app_dir")
    
    # Analyzer name to DLL mapping
    declare -A dll_map=(
        ["CodeCop"]="Microsoft.Dynamics.Nav.CodeCop.dll"
        ["UICop"]="Microsoft.Dynamics.Nav.UICop.dll"
        ["AppSourceCop"]="Microsoft.Dynamics.Nav.AppSourceCop.dll"
        ["PerTenantExtensionCop"]="Microsoft.Dynamics.Nav.PerTenantExtensionCop.dll"
    )
    
    local supported=("CodeCop" "UICop" "AppSourceCop" "PerTenantExtensionCop")
    local enabled=()
    
    # Parse enabled analyzers from settings.json
    if [[ -n "$settings_path" && -f "$settings_path" && -n "$(command -v jq)" ]]; then
        local analyzers_json
        analyzers_json=$(jq -r '.["al.codeAnalyzers"] // empty' "$settings_path" 2>/dev/null)
        
        if [[ -n "$analyzers_json" && "$analyzers_json" != "null" ]]; then
            # Parse array and remove ${} wrapper
            while IFS= read -r analyzer; do
                analyzer=$(echo "$analyzer" | sed 's/\${//g; s/}//g')
                enabled+=("$analyzer")
            done < <(echo "$analyzers_json" | jq -r '.[]' 2>/dev/null)
        fi
    fi
    
    # Default to CodeCop and UICop if nothing configured
    if [[ ${#enabled[@]} -eq 0 ]]; then
        enabled=("CodeCop" "UICop")
    fi
    
    # Filter to supported analyzers and find DLL paths
    local al_ext_path
    al_ext_path=$(get_highest_version_al_extension)
    local dll_paths=()
    
    if [[ -n "$al_ext_path" ]]; then
        for analyzer in "${enabled[@]}"; do
            # Check if analyzer is supported
            local is_supported=false
            for supported_analyzer in "${supported[@]}"; do
                if [[ "$analyzer" == "$supported_analyzer" ]]; then
                    is_supported=true
                    break
                fi
            done
            
            if [[ "$is_supported" == true ]]; then
                local dll="${dll_map[$analyzer]}"
                if [[ -n "$dll" ]]; then
                    local dll_path
                    dll_path=$(find "$al_ext_path" -name "$dll" -type f 2>/dev/null | head -1)
                    if [[ -n "$dll_path" ]]; then
                        dll_paths+=("$dll_path")
                    fi
                fi
            fi
        done
    fi
    
    printf '%s\n' "${dll_paths[@]}"
}