# Quickstart: Docker-Based Installer Test Harness

Validate the public bootstrap installer in a clean Windows container before releasing.

## Prerequisites
- Windows host with Docker engine configured for Windows containers
- Network access to GitHub releases
- Windows PowerShell 5.1+ (PowerShell 7 will be installed automatically inside the container by the installer script if absent)

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

#### Scenario 1: Docker Not Installed
- **Exit Code**: 6 (MissingTool)
- **Error Message**: "Docker engine not found. Please install Docker Desktop or Docker CLI."
- **Summary JSON**: `"errorSummary": "Docker engine not found"`
- **Remediation**: Install Docker Desktop (Windows) or Docker CLI; ensure Windows containers mode is enabled.

#### Scenario 2: Network Error During Release Fetch
- **Exit Code**: 1 (General Error)
- **Error Message**: Check transcript for network timeout or DNS resolution error
- **Summary JSON**: `"errorSummary": "Failed to fetch latest release from GitHub API after 2 attempts"`
- **Provision Log**: See `provision.log` for image pull diagnostics
- **Remediation**: Verify network connectivity; optionally set `$env:GITHUB_TOKEN` for higher rate limits

#### Scenario 3: Installer Script Exit Non-Zero
- **Exit Code**: 1 (General Error)
- **Error Message**: Varies; check transcript for installer output
- **Summary JSON**:
  - `"exitCode": <N>` (installer's exit code)
  - `"errorSummary": "Installer exited with code X (failed prerequisites: <tools>) (last step: <name>)"`
  - `"failedPrerequisites": ["tool1", "tool2"]` (if parsing extracted prerequisite status)
  - `"lastCompletedStep": "Download overlay"` (step name before failure)
- **Provision Log**: Container stdout/stderr tail appended to transcript
- **Remediation**:
  1. Read transcript for detailed error messages
  2. Check summary.json `failedPrerequisites` array to identify which tool failed (e.g., PowerShell 7 auto-install, git, dotnet, chocolatey)
  3. Check `lastCompletedStep` to pinpoint which phase failed
  4. For PowerShell 7 auto-install failures: Ensure Windows PowerShell 5.1 is available; verify dotnet runtime prerequisites on Windows Server Core image
  5. For git failures: Verify network access; check if git binary is in PATH
  6. For tool prerequisites: See `timedPhases` timing data to identify slow/hanging steps

#### Scenario 4: Image Pull Timeout
- **Exit Code**: 1 (General Error)
- **Summary JSON**:
  - `"imagePullSeconds": <timeout>` (reached network timeout)
  - `"errorSummary": "Image pull failed: <reason>"`
- **Provision Log**: Docker pull output with error details
- **Remediation**:
  1. Pre-pull the image locally: `docker pull mcr.microsoft.com/windows/servercore:ltsc2022`
  2. Override image with locally cached copy: `$env:ALBT_TEST_IMAGE = 'localhost/windows-servercore-cached'`
  3. Increase timeout by rerunning (may hit transient network issues)

#### Scenario 5: Container Exits Successfully but Artifacts Missing
- **Exit Code**: 1 (General Error)
- **Summary JSON**: `"errorSummary": "Transcript file missing after successful container exit"`
- **Cause**: Harness validation caught artifact absence despite installer exit 0
- **Remediation**:
  1. Check `out/test-install/` directory exists and has write permissions
  2. Re-run with `-Verbose` to see file write operations in log
  3. Verify disk space available in `out/` directory

#### Scenario 6: Large Transcript (>5MB)
- **Exit Code**: 0 (Success) but transcript truncated
- **Summary JSON**: `"success": true` (harness succeeded; transcript truncation is protective)
- **Transcript File**: Contains "[TRANSCRIPT TRUNCATED - Original size: X.XX MB]" header
- **Cause**: Installer produced excessive logging (looping installations or debug verbosity)
- **Remediation**: Check transcript tail (last 4MB) for actual errors; consider lowering verbosity or investigating repeated installs

#### Scenario 7: Guard Condition Triggered
- **Exit Code**: 2 (Guard)
- **Error Message**: "Invoked without required execution context"
- **Summary JSON**: `"guardCondition": "<Condition>"`
- **Example Conditions**:
  - `"GitRepoRequired"`: Harness running outside a git repository
  - `"PowerShellVersionUnsupported"`: Container failed to install PowerShell 7.2+
- **Remediation**:
  1. For GitRepoRequired: Run harness from within the cloned al-build-tools repository
  2. For PowerShellVersionUnsupported: Check transcript for PowerShell auto-install errors; verify dotnet runtime prerequisites

#### Scenario 8: Prerequisite Installation Partial Failure
- **Exit Code**: 1 (General Error)
- **Summary JSON**:
  - `"installedPrerequisites": ["choco", "git"]` (tools that completed)
  - `"failedPrerequisites": ["dotnet"]` (tools that started but didn't finish)
- **Transcript**: Search for `[install] prerequisite tool="dotnet"` to find where it failed
- **Remediation**:
  1. Check if missing tool is optional or required (read installer output)
  2. If required: Address blockers in transcript (network, permissions, dependency)
  3. If optional: Continue if other prerequisites succeeded

#### Interpreting `timedPhases` for Performance Analysis

The summary.json includes optional timing data:
```json
{
  "timedPhases": {
    "release-resolution": {
      "durationSeconds": 3,
      "startTime": "2025-10-17T14:32:00Z",
      "endTime": "2025-10-17T14:32:03Z"
    },
    "container-provisioning": {
      "durationSeconds": 120,
      "startTime": "2025-10-17T14:32:03Z",
      "endTime": "2025-10-17T14:34:03Z"
    }
  }
}
```

- **release-resolution > 10 seconds**: Network latency to GitHub API; check connectivity or set `GITHUB_TOKEN`
- **container-provisioning > 180 seconds**: Image pull or container creation is slow; pre-pull image or use local cache
- **Compare to previous runs**: If suddenly slow, may indicate network/CI agent performance regression

#### General Debugging Steps

1. **Check exit code first** (last line of summary.json or script output)
2. **Read transcript summary** (first and last 50 lines for context)
3. **Parse summary.json fields**:
   - `errorSummary` (brief reason)
   - `failedPrerequisites` (which tools failed)
   - `lastCompletedStep` (how far did we get)
   - `guardCondition` (validation rejection)
4. **Inspect provision.log** (only on failure; container image pull + creation diagnostics)
5. **Run locally with `-Verbose` and keep-container flags for inspection**:
   ```powershell
   $env:ALBT_TEST_KEEP_CONTAINER = '1'
   pwsh -File scripts/ci/test-bootstrap-install.ps1 -Verbose
   # Then inspect running container: docker exec -it albt-test-<id> powershell
   ```
