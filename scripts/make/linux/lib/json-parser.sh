# Linux JSON Parser Library - equivalent to Windows json-parser.ps1
# JSON parsing functions using jq

# Function: get_app_json_object  
# Parse app.json and return success/failure - equivalent to Get-AppJsonObject
# Usage: if get_app_json_object "$app_dir" >/dev/null; then echo "valid"; fi
get_app_json_object() {
    local app_dir="$1"
    local app_json_path
    app_json_path=$(get_app_json_path "$app_dir")
    
    if [[ -z "$app_json_path" ]]; then
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        return 1
    fi
    
    # Test if JSON is valid by trying to parse it
    if jq empty "$app_json_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: get_settings_json_object
# Parse settings.json and return success/failure - equivalent to Get-SettingsJsonObject  
# Usage: if get_settings_json_object "$app_dir" >/dev/null; then echo "valid"; fi
get_settings_json_object() {
    local app_dir="$1"
    local settings_path
    settings_path=$(get_settings_json_path "$app_dir")
    
    if [[ -z "$settings_path" ]]; then
        return 1
    fi
    
    if ! command -v jq &> /dev/null; then
        return 1
    fi
    
    # Test if JSON is valid by trying to parse it
    if jq empty "$settings_path" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Function: get_enabled_analyzer
# Get first enabled analyzer - equivalent to Get-EnabledAnalyzer
# Returns single analyzer name (first one if multiple)
get_enabled_analyzer() {
    local app_dir="$1"
    local settings_path
    settings_path=$(get_settings_json_path "$app_dir")
    
    if [[ -n "$settings_path" && -f "$settings_path" && -n "$(command -v jq)" ]]; then
        local first_analyzer
        first_analyzer=$(jq -r '.["al.codeAnalyzers"][0] // empty' "$settings_path" 2>/dev/null)
        
        if [[ -n "$first_analyzer" && "$first_analyzer" != "null" ]]; then
            # Remove ${} wrapper
            first_analyzer=$(echo "$first_analyzer" | sed 's/\${//g; s/}//g')
            echo "$first_analyzer"
            return
        fi
    fi
    
    # Default to CodeCop
    echo "CodeCop"
}

# Function: get_enabled_analyzers
# Get all enabled analyzers - equivalent to Get-EnabledAnalyzers
# Returns array of analyzer names
get_enabled_analyzers() {
    local app_dir="$1"
    local settings_path
    settings_path=$(get_settings_json_path "$app_dir")
    
    local analyzers=()
    
    if [[ -n "$settings_path" && -f "$settings_path" && -n "$(command -v jq)" ]]; then
        local analyzers_json
        analyzers_json=$(jq -r '.["al.codeAnalyzers"] // empty' "$settings_path" 2>/dev/null)
        
        if [[ -n "$analyzers_json" && "$analyzers_json" != "null" ]]; then
            # Parse array and remove ${} wrapper
            while IFS= read -r analyzer; do
                analyzer=$(echo "$analyzer" | sed 's/\${//g; s/}//g')
                analyzers+=("$analyzer")
            done < <(echo "$analyzers_json" | jq -r '.[]' 2>/dev/null)
        fi
    fi
    
    # Default to CodeCop and UICop if nothing configured
    if [[ ${#analyzers[@]} -eq 0 ]]; then
        analyzers=("CodeCop" "UICop")
    fi
    
    printf '%s\n' "${analyzers[@]}"
}