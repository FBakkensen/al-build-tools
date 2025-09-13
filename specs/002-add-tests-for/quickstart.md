# Quickstart – Running Bootstrap Installer Contract Tests

## Prerequisites
- bash, pwsh (PowerShell 7+), git, curl, python3, unzip
  - Tests simulate missing tools by PATH sandboxing; do not rely on network.

## Run All Tests
```
find tests -type f -name 'test_*.sh' -exec bash {} \;
```

## Test Scripts (each exercises both installers: bash and PowerShell)
```
bash tests/contract/test_bootstrap_install_basic.sh
bash tests/contract/test_bootstrap_install_idempotent.sh
bash tests/contract/test_bootstrap_install_git_context.sh
bash tests/contract/test_bootstrap_install_custom_dest.sh
bash tests/contract/test_bootstrap_install_fallback_unzip_missing.sh
bash tests/contract/test_bootstrap_install_fail_no_extract_tools.sh
bash tests/contract/test_bootstrap_install_preserve_and_no_side_effects.sh
bash tests/contract/test_bootstrap_install_spaces_in_path.sh
bash tests/contract/test_bootstrap_install_readonly_failure.sh
bash tests/contract/test_bootstrap_install_powershell_parity.sh
```

## Structure
- All tests use a shared harness (tests/contract/lib/bootstrap_harness.sh):
  - Builds a local file:// ZIP fixture from overlay/ (no network).
  - Creates a per-test PATH sandbox and a unified `$WORK/bin/install` wrapper.
  - Runs the same scenario twice: `ALBT_ENGINE=sh` and `ALBT_ENGINE=ps`.

## Expected Outcomes
- Success-path tests exit 0 with reporting lines (Install/update, Copied, Completed).
- Failure-path tests exit non-zero and assert an error substring.
- Idempotence test reports identical directory hash and file count across runs.

## Troubleshooting
- Ensure pwsh is installed and on PATH; tests fail if prerequisites are missing.
- On failure, each test prints the captured installer output (`out-*.txt`) to stderr. For deeper inspection, temporarily disable cleanup in `tests/contract/lib/bootstrap_test_helpers.sh` to keep the per‑test temp directory (created under the system temp path).
