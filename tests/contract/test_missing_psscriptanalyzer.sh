#!/usr/bin/env bash
set -euo pipefail

# Contract test: Missing PSScriptAnalyzer produces blocking Configuration issue
# Simulates absence using FORCE_NO_PSSA=1 and verifies non-zero exit with expected message

export FORCE_NO_PSSA=1

# Capture output and exit code
set +e
output=$(bash scripts/ci/run-static-analysis.sh 2>&1)
exit_code=$?
set -e

# Assert non-zero exit code
if [ $exit_code -eq 0 ]; then
    echo "FAIL: Expected non-zero exit code when PSScriptAnalyzer is missing, got 0"
    exit 1
fi

# Assert expected error message in output
if ! echo "$output" | grep -q "PSScriptAnalyzer not installed"; then
    echo "FAIL: Expected message 'PSScriptAnalyzer not installed' not found in output"
    echo "Actual output:"
    echo "$output"
    exit 1
fi

echo "PASS: Missing PSScriptAnalyzer correctly produces blocking Configuration issue"
exit 0