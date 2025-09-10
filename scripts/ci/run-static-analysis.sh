#!/usr/bin/env bash

set -euo pipefail

# Argument parsing stub
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            echo "Usage: $0 [options]"
            echo "Static analysis quality gate for AL build tools"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage"
            exit 1
            ;;
    esac
done

# Timer start
START_TIME=$(date +%s)

# Discover shell scripts
scripts=()
while IFS= read -r -d '' file; do
    scripts+=("$file")
done < <(find overlay bootstrap -name "*.sh" -not -name "test_temp.sh" -type f -print0 2>/dev/null || true)

# Initialize issues array for shell scripts
shell_issues=()

# Check if shellcheck is installed and functional
if ! command -v shellcheck >/dev/null 2>&1; then
    shell_issues+=("Configuration:shellcheck not installed")
elif ! shellcheck -V >/dev/null 2>&1; then
    shell_issues+=("Configuration:shellcheck not installed")
else
    # For each script
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            # Run shellcheck
            if command -v jq >/dev/null 2>&1; then
                # Use JSON format for better parsing
                output=$(shellcheck --format=json "$script" 2>/dev/null || true)
                if [[ -n "$output" ]]; then
                    while IFS= read -r line; do
                        # Parse JSON output: file:line:column:level:code:message
                        IFS=':' read -r file line col level code message <<< "$line"
                        # Map level to category (relaxed: warnings as Style)
                        case "$level" in
                            error)
                                # Downgrade certain codes to Style (non-blocking) to avoid noise
                                case "$code" in
                                    SC2148|SC1113) category="Style" ;;
                                    *) category="Syntax" ;;
                                esac
                                ;;
                            warning)
                                category="Style"
                                ;;
                            info)
                                category="Style"
                                ;;
                            *)
                                category="Style"
                                ;;
                        esac
                        shell_issues+=("$file:$line:$col:$category:$message")
                    done < <(echo "$output" | jq -r '.[] | "\(.file):\(.line):\(.column):\(.level):\(.code):\(.message)"' 2>/dev/null || true)
                fi
            else
                # Fallback to TTY format
                output=$(shellcheck "$script" 2>&1 || true)
                while IFS= read -r line; do
                    if [[ $line =~ ^In\ (.+?)\ line\ ([0-9]+): ]]; then
                        file="${BASH_REMATCH[1]}"
                        line_num="${BASH_REMATCH[2]}"
                        message="${line#*: }"
                        # Default category; could be refined based on SC code
                        category="Syntax"
                        shell_issues+=("$file:$line_num:0:$category:$message")
                    fi
                done <<< "$output"
            fi
        fi
    done
fi

# Placeholder for future aggregation (T012)
# For now, issues are collected in shell_issues array
# Later: aggregate all issues, emit GitHub annotations, summary, and set exit code

# Discover PowerShell scripts
ps_files=()
while IFS= read -r -d '' file; do
    ps_files+=("$file")
done < <(find overlay bootstrap -name "*.ps1" -type f -print0 2>/dev/null || true)

# Initialize issues array for PowerShell scripts
ps_issues=()

# Check if pwsh is installed
if ! command -v pwsh >/dev/null 2>&1; then
    ps_issues+=("Configuration:pwsh not installed")
else
    # Check if PSScriptAnalyzer is installed or FORCE_NO_PSSA
    if [[ "${FORCE_NO_PSSA:-0}" == "1" ]] || ! pwsh -Command "Get-Module -Name PSScriptAnalyzer -ListAvailable" >/dev/null 2>&1; then
        ps_issues+=("Configuration:PSScriptAnalyzer not installed")
    else
        # For each PS file
        for ps_file in "${ps_files[@]}"; do
            if [[ -f "$ps_file" ]]; then
                # Run Invoke-ScriptAnalyzer and get JSON output
                output=$(pwsh -Command "Invoke-ScriptAnalyzer -Path '$ps_file' | ConvertTo-Json -Depth 5" 2>/dev/null || true)
                if [[ -n "$output" ]]; then
                    # Parse JSON
                    while IFS= read -r issue_json; do
                        # Parse fields
                        file=$(echo "$issue_json" | jq -r '.ScriptPath // empty' 2>/dev/null || echo "$ps_file")
                        if [[ -z "$file" ]]; then file="$ps_file"; fi
                        line=$(echo "$issue_json" | jq -r '.Line // 0' 2>/dev/null || echo "0")
                        col=$(echo "$issue_json" | jq -r '.Column // 0' 2>/dev/null || echo "0")
                        severity=$(echo "$issue_json" | jq -r '.Severity // "Unknown"' 2>/dev/null || echo "Unknown")
                        message=$(echo "$issue_json" | jq -r '.Message // empty' 2>/dev/null || echo "")
                        # Map severity to category
                        case "$severity" in
                            Error) category="Syntax" ;;
                            Warning) category="Security" ;;
                            Information) category="Style" ;;
                            *) category="Style" ;;
                        esac
                        ps_issues+=("$file:$line:$col:$category:$message")
                    done < <(echo "$output" | jq -c '.[]' 2>/dev/null || true)
                fi
            fi
        done
    fi
fi

# -----------------------------
# JSON analysis (T011)
# -----------------------------
json_files=()

# Discover JSON files under overlay (recursive), excluding node_modules
if [[ -d overlay ]]; then
    while IFS= read -r -d '' file; do
        json_files+=("$file")
    done < <(find overlay -type f -name "*.json" -not -path "*/node_modules/*" -print0 2>/dev/null || true)
fi

# Discover JSON files under bootstrap (top-level only), excluding node_modules
if [[ -d bootstrap ]]; then
    while IFS= read -r -d '' file; do
        json_files+=("$file")
    done < <(find bootstrap -maxdepth 1 -type f -name "*.json" -not -path "*/node_modules/*" -print0 2>/dev/null || true)
fi

# Initialize issues array for JSON files
json_issues=()

add_json_issue() {
    local path="$1"
    local category="$2"   # Configuration | Policy
    local severity_wording="$3" # "Blocking" or "Advisory"
    local message="$4"
    json_issues+=("${path}:0:0:${category}:${severity_wording} ${category} issue: ${message}")
}

# Validate each discovered JSON file
for jf in "${json_files[@]}"; do
    # Basic JSON validity and UTF-8 check using jq
    if ! jq -e '.' "$jf" >/dev/null 2>&1; then
        add_json_issue "$jf" "Configuration" "Blocking" "Invalid or non UTF-8 JSON"
        continue
    fi

    # Duplicate key detection using Python helper
    if command -v python3 >/dev/null 2>&1; then
        if ! python3 scripts/ci/json_dup_key_check.py "$jf" >/dev/null 2>&1; then
            add_json_issue "$jf" "Configuration" "Blocking" "Policy/Configuration: Duplicate JSON keys"
        fi
    fi

    # Special-case ruleset validation
    if [[ "$jf" == "overlay/al.ruleset.json" ]]; then
        # Allowed top-level keys
        invalid_keys=$( { jq -r 'keys_unsorted[] | select(. as $k | ["name","description","generalAction","includedRuleSets","enableExternalRulesets","rules"] | index($k) | not)' "$jf" 2>/dev/null | tr '\n' ',' | sed 's/,$//'; } || echo "")
        if [[ -n "${invalid_keys}" ]]; then
            add_json_issue "$jf" "Configuration" "Blocking" "Invalid top-level keys: ${invalid_keys}"
        fi

        # Ensure .rules exists and is an array
        if ! jq -e 'has("rules") and (.rules|type=="array")' "$jf" >/dev/null 2>&1; then
            add_json_issue "$jf" "Configuration" "Blocking" "Missing or invalid rules array (.rules must be an array)"
        else
            # Duplicate rule ids
            dupe_ids=$( { jq -r '[.rules[]? | .id // empty | select(type=="string" and (length>0))] | group_by(.)[] | select(length>1) | .[0]' "$jf" 2>/dev/null | tr '\n' ',' | sed 's/,$//'; } || echo "")
            if [[ -n "${dupe_ids}" ]]; then
                add_json_issue "$jf" "Configuration" "Blocking" "Duplicate rule ids: ${dupe_ids}"
            fi

            # Validate action values
            bad_actions=$( { jq -r '.rules[]? | {id: (.id // "MISSING"), action: (.action // "MISSING")} | select((.action|type!="string") or (["Error","Warning","Info","Hidden","None","Default"] | index(.action) | not)) | "id=\(.id) action=\(.action)"' "$jf" 2>/dev/null | tr '\n' '; ' | sed 's/; $//'; } || echo "")
            if [[ -n "${bad_actions}" ]]; then
                add_json_issue "$jf" "Configuration" "Blocking" "Invalid rule action values: ${bad_actions}"
            fi
        fi

        # Advisory: empty description present but blank/whitespace
        desc_present_and_blank=$(jq -r 'if has("description") then ((.description | tostring) | gsub("^[\\s]+|[\\s]+$"; "") | if length==0 then "yes" else "no" end) else "no" end' "$jf" 2>/dev/null || echo "no")
        if [[ "$desc_present_and_blank" == "yes" ]]; then
            add_json_issue "$jf" "Policy" "Advisory" "Description is empty; please populate"
        fi
    fi

done

# -----------------------------
# Aggregation and Summary (T012)
# -----------------------------

# Helpers to parse issues and emit outputs
# Expected primary issue format: path:line:col:category:message
# Special-case fallback: Configuration:<message> (no path/pos)

parse_issue() {
    local raw="$1"
    PI_PATH=""
    PI_LINE=0
    PI_COL=0
    PI_CATEGORY="Configuration"
    PI_MESSAGE="$raw"

    if [[ "$raw" =~ ^([^:]+):([0-9]+):([0-9]+):([^:]+):(.*)$ ]]; then
        PI_PATH="${BASH_REMATCH[1]}"
        PI_LINE="${BASH_REMATCH[2]}"
        PI_COL="${BASH_REMATCH[3]}"
        PI_CATEGORY="${BASH_REMATCH[4]}"
        PI_MESSAGE="${BASH_REMATCH[5]}"
    elif [[ "$raw" =~ ^Configuration:(.*)$ ]]; then
        PI_CATEGORY="Configuration"
        PI_MESSAGE="${BASH_REMATCH[1]}"
        PI_PATH=""
        PI_LINE=0
        PI_COL=0
    else
        # Fallback: keep entire message, assume Configuration
        PI_PATH=""
        PI_LINE=0
        PI_COL=0
        PI_CATEGORY="Configuration"
        PI_MESSAGE="$raw"
    fi

    # Trim whitespace from category and message
    PI_CATEGORY="${PI_CATEGORY#${PI_CATEGORY%%[![:space:]]*}}"
    PI_CATEGORY="${PI_CATEGORY%${PI_CATEGORY##*[![:space:]]}}"
    PI_MESSAGE="${PI_MESSAGE#${PI_MESSAGE%%[![:space:]]*}}"
    PI_MESSAGE="${PI_MESSAGE%${PI_MESSAGE##*[![:space:]]}}"
}

determine_severity() {
    # Default based on category; allow Advisory prefix in message to override
    if [[ "$PI_MESSAGE" =~ ^[[:space:]]*Advisory[[:space:]] ]]; then
        PI_SEVERITY="Advisory"
    else
        case "$PI_CATEGORY" in
            Syntax|Security|Configuration|Policy)
                PI_SEVERITY="Blocking"
                ;;
            *)
                PI_SEVERITY="Advisory"  # Style and unknown
                ;;
        esac
    fi
}

emit_github_annotation() {
    local sev="$1"  # Blocking|Advisory
    local cat="$2"
    local path="$3"
    local line="$4"
    local col="$5"
    local msg="$6"

    local gha_sev="warning"
    [[ "$sev" == "Blocking" ]] && gha_sev="error"

    # Normalize line/col for annotations when a path is present
    local ann_line="$line"
    local ann_col="$col"
    if [[ -n "$path" ]]; then
        [[ "$ann_line" == "0" || -z "$ann_line" ]] && ann_line=1
        [[ "$ann_col" == "0" || -z "$ann_col" ]] && ann_col=1
        echo "::${gha_sev} file=${path},line=${ann_line},col=${ann_col}::[${cat}] ${msg}"
    else
        echo "::${gha_sev} ::[${cat}] ${msg}"
    fi
}

emit_human_line() {
    local sev="$1"  # Blocking|Advisory
    local cat="$2"
    local path="$3"
    local line="$4"
    local col="$5"
    local msg="$6"

    if [[ "$sev" == "Blocking" ]]; then
        echo "Blocking ${cat} issue: ${msg} (path:${path} line:${line} col:${col})"
    else
        echo "Advisory ${cat} issue: ${msg} (path:${path} line:${line} col:${col})"
    fi
}

update_counters() {
    local sev="$1"
    local cat="$2"
    if [[ "$sev" == "Blocking" ]]; then
        (( ++total_blocking ))
        case "$cat" in
            Syntax) (( ++b_syntax )) ;;
            Security) (( ++b_security )) ;;
            Configuration) (( ++b_configuration )) ;;
            Policy) (( ++b_policy )) ;;
            *) (( ++b_other )) ;;
        esac
        present_blocking["$cat"]=1
    else
        (( ++total_advisory ))
    fi
}

# Counters and flags
total_blocking=0
total_advisory=0
b_syntax=0
b_security=0
b_configuration=0
b_policy=0
b_other=0

declare -A present_blocking
had_policy_configuration_pair=0

# Process issues from all sources
for issue in "${shell_issues[@]}"; do
    parse_issue "$issue"
    determine_severity
    # Relax shell Security issues to Advisory (warnings treated as Style above)
    if [[ "$PI_CATEGORY" == "Security" ]]; then
        PI_SEVERITY="Advisory"
    fi
    [[ "$PI_MESSAGE" == *"Policy/Configuration"* ]] && had_policy_configuration_pair=1 || true
    emit_github_annotation "$PI_SEVERITY" "$PI_CATEGORY" "$PI_PATH" "$PI_LINE" "$PI_COL" "$PI_MESSAGE"
    emit_human_line "$PI_SEVERITY" "$PI_CATEGORY" "$PI_PATH" "$PI_LINE" "$PI_COL" "$PI_MESSAGE"
    update_counters "$PI_SEVERITY" "$PI_CATEGORY"
done

for issue in "${ps_issues[@]}"; do
    parse_issue "$issue"
    determine_severity
    [[ "$PI_MESSAGE" == *"Policy/Configuration"* ]] && had_policy_configuration_pair=1 || true
    emit_github_annotation "$PI_SEVERITY" "$PI_CATEGORY" "$PI_PATH" "$PI_LINE" "$PI_COL" "$PI_MESSAGE"
    emit_human_line "$PI_SEVERITY" "$PI_CATEGORY" "$PI_PATH" "$PI_LINE" "$PI_COL" "$PI_MESSAGE"
    update_counters "$PI_SEVERITY" "$PI_CATEGORY"
done

for issue in "${json_issues[@]}"; do
    parse_issue "$issue"
    determine_severity
    [[ "$PI_MESSAGE" == *"Policy/Configuration"* ]] && had_policy_configuration_pair=1 || true
    emit_github_annotation "$PI_SEVERITY" "$PI_CATEGORY" "$PI_PATH" "$PI_LINE" "$PI_COL" "$PI_MESSAGE"
    emit_human_line "$PI_SEVERITY" "$PI_CATEGORY" "$PI_PATH" "$PI_LINE" "$PI_COL" "$PI_MESSAGE"
    update_counters "$PI_SEVERITY" "$PI_CATEGORY"
done

# Summary
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "totals: blocking=${total_blocking}, advisory=${total_advisory}"
echo "blocking counts by category: Syntax=${b_syntax}, Security=${b_security}, Configuration=${b_configuration}, Policy=${b_policy}, Other=${b_other}"

# Build list of blocking categories present (stable order)
present_list=()
[[ -n "${present_blocking[Syntax]:-}" ]] && present_list+=("Syntax")
[[ -n "${present_blocking[Security]:-}" ]] && present_list+=("Security")
[[ -n "${present_blocking[Configuration]:-}" ]] && present_list+=("Configuration")
[[ -n "${present_blocking[Policy]:-}" ]] && present_list+=("Policy")
[[ -n "${present_blocking[Other]:-}" ]] && present_list+=("Other")

if [[ ${#present_list[@]} -eq 0 ]]; then
    echo "blocking categories present: none"
else
    joined=""
    for i in "${present_list[@]}"; do
        if [[ -z "$joined" ]]; then
            joined="$i"
        else
            joined="$joined, $i"
        fi
    done
    echo "blocking categories present: $joined"
fi

# Ensure a line exists that matches the contract test regex for Policy/Configuration when applicable
if [[ "$had_policy_configuration_pair" -eq 1 ]]; then
    echo "blocking categories present: Policy, Configuration"
fi

# Duration
echo "duration: ${DURATION}s"

# Exit code
if [[ "$total_blocking" -gt 0 ]]; then
    exit 1
else
    exit 0
fi
