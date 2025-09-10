#!/usr/bin/env bash
set -euo pipefail

# Contract test: Duplicate JSON keys produce failure
# Creates temp malformed JSON with duplicate keys, invokes analysis, expects blocking Policy/Configuration issue & non-zero exit

temp_json="overlay/temp_dup.json"

# Create temp JSON with duplicate keys (duplicate "name")
cat > "$temp_json" << 'EOF'
{
  "name": "DefaultRuleSet",
  "name": "DuplicateName",
  "description": "Test duplicate keys",
  "rules": [
    { "id": "AA0072", "action": "Hidden" }
  ]
}
EOF

# Capture output and exit code from analysis script
set +e
output=$(bash scripts/ci/run-static-analysis.sh 2>&1)
exit_code=$?
set -e

# Clean up temp file
rm -f "$temp_json"

# Assert non-zero exit code
if [ $exit_code -eq 0 ]; then
    echo "FAIL: Expected non-zero exit code when duplicate JSON keys present, got 0"
    exit 1
fi

# Assert expected error message in output
if ! echo "$output" | grep -q "blocking.*Policy.*Configuration"; then
    echo "FAIL: Expected message containing 'blocking Policy Configuration' not found in output"
    echo "Actual output:"
    echo "$output"
    exit 1
fi

echo "PASS: Duplicate JSON keys correctly produce blocking Policy/Configuration issue"
exit 0