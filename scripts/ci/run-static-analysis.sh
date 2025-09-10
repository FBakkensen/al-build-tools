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
done < <(find overlay bootstrap -name "*.sh" -type f -print0 2>/dev/null || true)

# Initialize issues array for shell scripts
shell_issues=()

# Check if shellcheck is installed
if ! command -v shellcheck >/dev/null 2>&1; then
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
                        # Map level to category
                        case "$level" in
                            error) category="Syntax" ;;
                            warning) category="Security" ;;
                            info) category="Style" ;;
                            *) category="Style" ;;
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
                output=$(pwsh -Command "Invoke-ScriptAnalyzer -Path '$ps_file' | ConvertTo-Json" 2>/dev/null || true)
                if [[ -n "$output" ]]; then
                    # Parse JSON
                    while IFS= read -r issue_json; do
                        # Parse fields
                        file=$(echo "$issue_json" | jq -r '.ScriptPath // empty' 2>/dev/null || echo "$ps_file")
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

echo "Shell script analysis complete. Found ${#shell_issues[@]} issues."
echo "PowerShell script analysis complete. Found ${#ps_issues[@]} issues."
# Temporary: print issues for debugging
for issue in "${shell_issues[@]}"; do
    echo "Shell Issue: $issue"
done
for issue in "${ps_issues[@]}"; do
    echo "PS Issue: $issue"
done