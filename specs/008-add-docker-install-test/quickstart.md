# Quickstart: Docker-Based Installer Test Harness

Validate the public bootstrap installer in a clean Windows container before releasing.

## Prerequisites
- Windows host with Docker engine configured for Windows containers
- Network access to GitHub releases
- Windows PowerShell 5.1+ (PowerShell 7 will be installed automatically inside the container by the installer script if absent)
- (Optional) `GITHUB_TOKEN` env for higher GitHub API rate limits

## Planned Artifacts
- Script: `scripts/ci/test-bootstrap-install.ps1` (implemented)
- Workflow: `.github/workflows/test-bootstrap-install.yml`

## Local Run

The harness runs the **actual `bootstrap/install.ps1`** inside a clean Windows container to validate the real installer path. This ensures first-time user scenarios work correctly.

### Get Help

View the harness usage and available options:
```powershell
pwsh -File scripts/ci/test-bootstrap-install.ps1 -Help
```

Or use the short form:
```powershell
pwsh -File scripts/ci/test-bootstrap-install.ps1 -?
```

### Basic Examples

**Example 1: Test latest release with verbose output**
```powershell
pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose
```

**Example 2: Test a specific release tag**
```powershell
$env:ALBT_TEST_RELEASE_TAG = 'v1.2.3'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

**Example 3: Override container image**
```powershell
$env:ALBT_TEST_IMAGE = 'mcr.microsoft.com/windows/servercore:ltsc2025'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

**Example 4: Debug mode (preserve container for inspection)**
```powershell
$env:ALBT_TEST_KEEP_CONTAINER = '1'
pwsh -File scripts/ci/test-bootstrap-install.ps1
```

### Integrity Verification

**T043a: Integrity Verification** – Optional SHA256 validation:

If you have a known SHA256 digest of the overlay.zip asset, you can validate it:
```powershell
$env:ALBT_TEST_EXPECTED_SHA256 = 'abc123def456...'
pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose
```

The harness and installer record the actual SHA256 in the summary JSON for comparison. The installer (`bootstrap/install.ps1`) owns the primary integrity check; the test harness documents the expected value but defers validation to the installer to avoid duplication.

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

## Failure Diagnostics

When the test fails (non-zero exit code), examine:

1. **Transcript** (out/test-install/install.transcript.txt): Full execution log including container startup, installer invocation, and any error messages.
2. **Provision log** (out/test-install/provision.log): Docker image pull, container creation, and stdout/stderr tail on failure.
3. **Summary JSON** (out/test-install/summary.json): Machine-readable metadata including:
   - exitCode: Installer exit code
   - errorSummary: Brief failure classification (network, integration, missing-tool)
   - imagePullSeconds / containerCreateSeconds: Timing data for performance analysis
   - timedPhases: Structured start/end times for release-resolution and container-provisioning phases

### Common Failure Scenarios

- **Docker not installed**: Exit code 6 (MissingTool) with message "Docker engine not found."
- **Network error during release fetch**: Exit code 1 (General Error) with errorSummary: "network".
- **Installer script exit non-zero**: Exit code 1 with errorSummary: "Installer exited with code X".
- **Container stdout tail**: Appended to transcript for quick triage.
