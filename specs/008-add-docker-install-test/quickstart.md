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

The harness runs the **actual `bootstrap/install.ps1`** inside a clean Windows container to validate the real installer path. This ensures first-time user scenarios work correctly.

Example (latest release):
```powershell
pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose
```

Specify a release tag:
```powershell
$env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

Debug without container auto-removal (preserves container for inspection):
```powershell
$env:ALBT_TEST_KEEP_CONTAINER = '1'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

Override container image:
```powershell
$env:ALBT_TEST_IMAGE = 'mcr.microsoft.com/windows/servercore:ltsc2025'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

## How It Works

1. **Host**: The harness resolves the release tag and copies the `bootstrap/` directory into the container
2. **Container**: Runs `bootstrap/install.ps1` inside a clean Windows Server Core environment
3. **Installer**: Downloads the overlay for the specified release, extracts it, and validates installation
4. **Host**: Captures exit code and artifacts (transcript, summary JSON)

This validates the complete first-time user path in isolation.

## Expected Output

- Transcript: `out/test-install/install.transcript.txt`
- Summary JSON: `out/test-install/summary.json` (matches `contracts/installer-test-summary.schema.json`)
- Exit code 0 on success, non-zero on failure
