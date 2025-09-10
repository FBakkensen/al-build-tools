#!/usr/bin/env bash

set -euo pipefail

# Test for timeout path in static analysis script
# Sets TIMEOUT_SECONDS=1 and INJECT_SLEEP=2 to simulate a timeout scenario
# Expects the script to detect timeout and emit a Blocking Configuration issue

export TIMEOUT_SECONDS=1
export INJECT_SLEEP=2

# Run the script with a safety timeout to prevent hanging
# Capture output and check for timeout-related blocking issue
if output=$(timeout 10 bash scripts/ci/run-static-analysis.sh 2>&1); then
    echo "Test failed: Script completed without timing out"
    exit 1
else
    # Check if the script's internal timeout was triggered and reported as Blocking Configuration
    if echo "$output" | grep -qi "blocking.*configuration.*timeout\|timeout.*blocking.*configuration"; then
        echo "Test passed: Timeout detected and reported as Blocking Configuration issue"
        exit 0
    else
        echo "Test failed: Expected Blocking Configuration timeout message not found in output"
        echo "Captured output:"
        echo "$output"
        exit 1
    fi
fi