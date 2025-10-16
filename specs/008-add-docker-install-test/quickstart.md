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

Refactored flow (harness delegates all overlay acquisition to installer):

1. **Host**: Harness resolves (or accepts) release tag and copies only the `bootstrap/` directory into a fresh container.
2. **Container**: Executes the real `bootstrap/install.ps1` script.
3. **Installer (inside container)**: Handles overlay.zip download, integrity checks, extraction, and post‑install validation.
4. **Host**: Collects exit code plus artifacts (transcript, summary). Timed phases cover release-resolution and container-provisioning (no separate download timing in harness).

This isolates the authentic end‑user install path without duplicating download or checksum logic outside the installer.

## Expected Output

- Transcript: `out/test-install/install.transcript.txt`
- Summary JSON: `out/test-install/summary.json` (schema-aligned; includes timed phases and optional imageDigest)
- Provision log: `out/test-install/provision.log` (only on failure for diagnostics)
- Exit code 0 on success; mapped non‑zero on failure (network/integration/missing-tool)

Download duration and checksum fields are intentionally absent from harness diagnostics (owned by installer). The summary retains static `assetName` for schema compliance.
