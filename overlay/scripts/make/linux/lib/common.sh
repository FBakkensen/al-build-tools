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
    # Search across common VS Code roots (stable, insiders, local, remote)
    local al_ext_roots=(
        "$HOME/.vscode/extensions"
        "$HOME/.vscode-server/extensions"
        "$HOME/.vscode-insiders/extensions"
        "$HOME/.vscode-server-insiders/extensions"
    )

    local best_path=""
    local best_version="0.0.0"

    for root in "${al_ext_roots[@]}"; do
        [[ -d "$root" ]] || continue

        # Collect candidate extension folders
        shopt -s nullglob
        local candidates=("$root"/ms-dynamics-smb.al-*)
        shopt -u nullglob
        [[ ${#candidates[@]} -gt 0 ]] || continue

        # Build list of version|path pairs for sorting and comparison
        local lines=""
        local ext base ver
        for ext in "${candidates[@]}"; do
            [[ -d "$ext" ]] || continue
            base=$(basename "$ext")
            # Extract numeric version after prefix, strip any suffix (e.g., -preview)
            ver=${base#ms-dynamics-smb.al-}
            ver=$(echo "$ver" | sed -E 's/^([0-9]+(\.[0-9]+)*)[A-Za-z0-9.-]*/\1/')
            [[ -n "$ver" ]] || ver="0.0.0"
            lines+="$ver|$ext\n"
        done

        # Compare against current best
        local version path
        while IFS='|' read -r version path; do
            [[ -n "$path" ]] || continue
            if [[ $(printf '%s\n' "$version" "$best_version" | sort -V | tail -n1) == "$version" && "$version" != "$best_version" ]]; then
                best_version="$version"
                best_path="$path"
            fi
        done < <(printf "%b" "$lines")
    done

    # Fallback: derive extension root from discovered compiler path if possible
    if [[ -z "$best_path" ]]; then
        local alc
        alc=$(get_al_compiler_path "")
        if [[ -n "$alc" ]]; then
            # Expect structure: <ext>/bin/<linux-*>/alc
            best_path=$(dirname "$(dirname "$(dirname "$alc")")")
        fi
    fi

    echo "$best_path"
}

# Function: get_al_compiler_path
# Discover AL compiler path robustly across VS Code variants and layouts
# Search order:
#   1) Respect explicit `ALC_PATH` env var if executable
#   2) Look in common extension roots for highest ms-dynamics-smb.al-* version
#      and prefer bin/linux-<arch>/alc, then bin/linux/alc, then any */linux*/alc
#   3) Fallback to any 'alc' under the extension folder
#   4) Final fallback: if 'alc' is on PATH
get_al_compiler_path() {
    local app_dir="$1"

    # 1) Direct override via env var
    if [[ -n "$ALC_PATH" && -f "$ALC_PATH" ]]; then
        echo "$ALC_PATH"
        return
    fi

    # Determine preferred linux folder based on architecture
    local arch
    arch=$(uname -m 2>/dev/null || echo "")
    local preferred_linux=""
    case "$arch" in
        x86_64|amd64) preferred_linux="linux-x64" ;;
        aarch64|arm64) preferred_linux="linux-arm64" ;;
        *) preferred_linux="" ;;
    esac

    # 2) Search common VS Code extension roots
    local al_ext_roots=(
        "$HOME/.vscode/extensions"
        "$HOME/.vscode-server/extensions"
        "$HOME/.vscode-insiders/extensions"
        "$HOME/.vscode-server-insiders/extensions"
    )

    for root in "${al_ext_roots[@]}"; do
        [[ -d "$root" ]] || continue

        # Collect candidate extension folders
        local candidates=()
        shopt -s nullglob
        candidates=("$root"/ms-dynamics-smb.al-*)
        shopt -u nullglob
        [[ ${#candidates[@]} -gt 0 ]] || continue

        # Build a version-sorted list (desc) of candidates
        local lines=""
        local ext base ver
        for ext in "${candidates[@]}"; do
            [[ -d "$ext" ]] || continue
            base=$(basename "$ext")
            # Extract numeric version prefix after ms-dynamics-smb.al-
            ver=${base#ms-dynamics-smb.al-}
            ver=$(echo "$ver" | sed -E 's/^([0-9]+(\.[0-9]+)*)[A-Za-z0-9.-]*/\1/')
            [[ -n "$ver" ]] || ver="0.0.0"
            lines+="$ver|$ext\n"
        done

        # Iterate in descending version order
        local pair version path
        while IFS='|' read -r version path; do
            [[ -n "$path" ]] || continue

            # Prefer bin/linux-<arch>/alc if present
            if [[ -n "$preferred_linux" && -f "$path/bin/$preferred_linux/alc" ]]; then
                echo "$path/bin/$preferred_linux/alc"
                return
            fi
            # Next try legacy bin/linux/alc
            if [[ -f "$path/bin/linux/alc" ]]; then
                echo "$path/bin/linux/alc"
                return
            fi
            # Next try any bin/*linux*/alc
            shopt -s nullglob
            local matches=("$path/bin/"*linux*/alc)
            shopt -u nullglob
            if [[ ${#matches[@]} -gt 0 && -f "${matches[0]}" ]]; then
                echo "${matches[0]}"
                return
            fi
            # Fallback: any 'alc' under the extension
            local any_alc
            any_alc=$(find "$path" -type f -name alc 2>/dev/null | head -n 1)
            if [[ -n "$any_alc" ]]; then
                echo "$any_alc"
                return
            fi
        done < <(printf "%b" "$lines" | sort -t'|' -k1,1V -r)
    done

    # 4) Final fallback: check PATH
    if command -v alc &>/dev/null; then
        command -v alc
        return
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
            while IFS= read -r analyzer; do
                enabled+=("$analyzer")
            done < <(echo "$analyzers_json" | jq -r '.[]' 2>/dev/null)
        fi
        # Back-compat flags
        if [[ ${#enabled[@]} -eq 0 ]]; then
            local flags
            flags=$(jq -r '[.enableCodeCop, .enableUICop, .enableAppSourceCop, .enablePerTenantExtensionCop] | @tsv' "$settings_path" 2>/dev/null)
            if [[ -n "$flags" ]]; then
                IFS=$'\t' read -r f1 f2 f3 f4 <<< "$flags"
                [[ "$f1" == "true" ]] && enabled+=("CodeCop")
                [[ "$f2" == "true" ]] && enabled+=("UICop")
                [[ "$f3" == "true" ]] && enabled+=("AppSourceCop")
                [[ "$f4" == "true" ]] && enabled+=("PerTenantExtensionCop")
            fi
        fi
    fi
    
    # Do not enable any default analyzers when none are configured
    
    # Helper: resolve placeholders in custom entries
    local resolve_entry
    resolve_entry() {
        local raw="$1"
        local app_dir="$2"
        local ext_path="$3"
        local workspace_root
        workspace_root=$(pwd)

        local value="$raw"
        # Resolve common VS Code-like placeholders
        local analyzers_dir="$ext_path/bin/Analyzers"

        # Token-aware joins to handle "${token}File.dll" without a slash
        if [[ "$value" =~ ^\$\{analyzerFolder\}(.*)$ ]]; then
            local tail="${BASH_REMATCH[1]}"
            if [[ -n "$tail" && "$tail" != /* ]]; then value="$analyzers_dir/$tail"; else value="$analyzers_dir$tail"; fi
        fi
        if [[ "$value" =~ ^\$\{alExtensionPath\}(.*)$ ]]; then
            local tail2="${BASH_REMATCH[1]}"
            if [[ -n "$tail2" && "$tail2" != /* ]]; then value="$ext_path/$tail2"; else value="$ext_path$tail2"; fi
        fi

        # Simple replacements for other tokens
        value=${value//\${workspaceFolder\}/$workspace_root}
        value=${value//\${workspaceRoot\}/$workspace_root}
        value=${value//\${appDir\}/$app_dir}

        # Remove any remaining ${} braces without replacing the content
        value=$(echo "$value" | sed 's/\${\([^}]*\)}/\1/g')

        # Expand ~ and environment variables
        value=$(eval echo "$value")

        # If relative, make absolute relative to workspace root
        if [[ "$value" != /* ]]; then
            value="$workspace_root/$value"
        fi

        # If directory, include all dlls inside
        if [[ -d "$value" ]]; then
            find "$value" -maxdepth 1 -type f -name '*.dll' 2>/dev/null
            return
        fi
        # If contains wildcard, expand
        if [[ "$value" == *'*'* ]]; then
            compgen -G "$value" || true
            return
        fi
        # If file exists, echo it
        if [[ -f "$value" ]]; then
            echo "$value"
        fi
    }

    # Build final DLL path list
    local al_ext_path
    al_ext_path=$(get_highest_version_al_extension)
    local out_paths=()

    for analyzer in "${enabled[@]}"; do
        # Strip quotes and whitespace
        analyzer=$(echo "$analyzer" | sed 's/^\s*\"\?//; s/\"\?\s*$//')
        # If form is ${Name}, unwrap to Name for known analyzers
        if [[ $analyzer =~ ^\$\{([A-Za-z]+)\}$ ]]; then
            analyzer="${BASH_REMATCH[1]}"
        fi
        # Known analyzers by name
        local is_supported=false
        for supported_analyzer in "${supported[@]}"; do
            if [[ "$analyzer" == "$supported_analyzer" ]]; then
                is_supported=true
                break
            fi
        done
        if [[ "$is_supported" == true && -n "$al_ext_path" ]]; then
            local dll="${dll_map[$analyzer]}"
            if [[ -n "$dll" ]]; then
                local dll_path
                dll_path=$(find "$al_ext_path" -type f -name "$dll" 2>/dev/null | head -1)
                if [[ -n "$dll_path" ]]; then
                    out_paths+=("$dll_path")
                fi
            fi
            continue
        fi

        # Otherwise treat as path expression
        while IFS= read -r resolved; do
            [[ -n "$resolved" ]] && out_paths+=("$resolved")
        done < <(resolve_entry "$analyzer" "$app_dir" "$al_ext_path")
    done

    # Deduplicate while preserving order
    declare -A seen
    local unique=()
    local p
    for p in "${out_paths[@]}"; do
        if [[ -n "$p" && -z "${seen[$p]}" ]]; then
            seen[$p]=1
            unique+=("$p")
        fi
    done

    printf '%s\n' "${unique[@]}"
}
