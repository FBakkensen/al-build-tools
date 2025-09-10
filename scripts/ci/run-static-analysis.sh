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

echo "Shell script analysis complete. Found ${#shell_issues[@]} issues."
# Temporary: print issues for debugging
for issue in "${shell_issues[@]}"; do
    echo "Issue: $issue"
done

exit 0  # Temporary; will be based on blocking issues later