# Quickstart: Docker-Based Installer Test Harness

Validate the public bootstrap installer in a clean Windows container before releasing.

## Prerequisites
- Windows host with Docker engine configured for Windows containers
- Network access to GitHub releases
- Windows PowerShell 5.1+ (PowerShell 7 will be installed automatically inside the container by the installer script if absent)
- (Optional) `GITHUB_TOKEN` env for higher GitHub API rate limits

## Planned Artifacts
- Script: `scripts/ci/test-bootstrap-install.ps1` (to be implemented)
- Workflow: `.github/workflows/test-bootstrap-install.yml`

## Local Run
The harness intentionally starts from a container WITHOUT PowerShell 7 to validate the installer's self-provisioning path. The future GitHub Actions workflow MUST only invoke the harness script and upload artifacts; it must not pre-install tools or perform logic absent from a local run.

Example (latest release):
```powershell
powershell -File scripts/ci/test-bootstrap-install.ps1 -Verbose
```
Specify a release tag:
```powershell
$env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```
Debug without container auto-removal:
```powershell
$env:ALBT_TEST_KEEP_CONTAINER = '1'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```
Override image:
```powershell
$env:ALBT_TEST_IMAGE = 'mcr.microsoft.com/windows/servercore:ltsc2025'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

## Expected Output
- Transcript: `out/test-install/install.transcript.txt`
- Summary JSON: `out/test-install/summary.json` (matches `contracts/installer-test-summary.schema.json`)
- Exit code 0 on success, non-zero on failure.

## CI Integration (Conceptual)
Workflow job steps outline:
1. Checkout repository
2. Run PowerShell script
3. Always upload `out/test-install` as artifact `installer-test-logs`
4. Fail job if script exit code != 0

## Failure Diagnostics
On failure, review:
1. Summary JSON (`exitCode`, `errorSummary`)
2. Transcript for stack traces or network errors
3. Container provisioning log section near PowerShell install

## Maintenance
- Update image tag only after verifying compatibility locally.
- Keep schema changes backward-compatible (additive) where possible.
- Consider adding Pester tests for deeper validation in future iterations.
- Ensure the container definition does not pre-install PowerShell 7; this is part of the test surface.
