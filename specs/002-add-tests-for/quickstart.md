# Quickstart – Running Bootstrap Installer Contract Tests

## Prerequisites
- Bash, PowerShell (`pwsh`), git, curl, python3, unzip (some tests simulate absence)

## Run All Existing Tests
```
find tests -type f -name 'test_*.sh' -exec bash {} \;
```

## (Planned) New Test Scripts
After implementation, run:
```
bash tests/contract/test_bootstrap_install_basic.sh
bash tests/contract/test_bootstrap_install_idempotent.sh
bash tests/contract/test_bootstrap_install_git_vs_nongit.sh
bash tests/contract/test_bootstrap_install_fallback_unzip_missing.sh
bash tests/contract/test_bootstrap_install_fail_no_extract_tools.sh
bash tests/contract/test_bootstrap_install_preserve_extraneous.sh
bash tests/contract/test_bootstrap_install_spaces_in_path.sh
bash tests/contract/test_bootstrap_install_readonly_failure.sh
pwsh -File tests/contract/test_bootstrap_install_powershell_parity.ps1  # optional wrapper or call via bash using pwsh
```

## Expected Outcomes
- All success-path tests exit code 0.
- Failure-path tests assert specific stderr substring and non-zero exit.
- Idempotence test reports identical hash set across runs.

## Troubleshooting
- If network unavailable: tests will fail at archive fetch; retry with connectivity.
- If `pwsh` missing: parity tests skipped (documented skip message).
