#!/usr/bin/env bash
set -euo pipefail

# Contract test: Shell syntax error flagged
# Creates temp bad script under overlay/scripts/make/linux/, invokes analysis, expects Blocking Syntax issue & non-zero exit

temp_script="overlay/scripts/make/linux/temp_bad_script.sh"

# Create temp bad script with syntax error (missing fi)
cat > "$temp_script" << 'EOF'
#!/usr/bin/env bash
if true; then
echo "This has a syntax error: missing fi"
EOF

chmod +x "$temp_script"

# Capture output and exit code from analysis script
set +e
output=$(bash scripts/ci/run-static-analysis.sh 2>&1)
exit_code=$?
set -e

# Clean up temp file
rm -f "$temp_script"

# Assert non-zero exit code
if [ $exit_code -eq 0 ]; then
    echo "FAIL: Expected non-zero exit code when shell syntax error present, got 0"
    exit 1
fi

# Assert expected error message in output
if ! echo "$output" | grep -q "Blocking Syntax issue"; then
    echo "FAIL: Expected message 'Blocking Syntax issue' not found in output"
    echo "Actual output:"
    echo "$output"
    exit 1
fi

echo "PASS: Shell syntax error correctly produces blocking Syntax issue"
exit 0