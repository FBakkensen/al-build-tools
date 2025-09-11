#!/usr/bin/env bash
set -euo pipefail

# Contract test: Clean repo (no injected defects) succeeds
# Runs analysis on clean repo, expects exit 0 and zero Blocking lines

# Capture output and exit code from analysis script
set +e
output=$(bash scripts/ci/run-static-analysis.sh 2>&1)
exit_code=$?
set -e

# Assert zero exit code
if [ $exit_code -ne 0 ]; then
    echo "FAIL: Expected exit code 0 for clean repo, got $exit_code"
    echo "Output:"
    echo "$output"
    exit 1
fi

# Assert no Blocking lines in output
blocking_count=$(echo "$output" | grep -c "Blocking" || true)
if [ $blocking_count -ne 0 ]; then
    echo "FAIL: Expected zero Blocking lines in clean repo, found $blocking_count"
    echo "Output:"
    echo "$output"
    exit 1
fi

echo "PASS: Clean repo analysis succeeds with exit 0 and zero Blocking lines"
exit 0