# Contracts: Docker-Based Install Script Test

This directory defines machine-readable contracts for the installer container test harness.

## JSON Schemas

### `installer-test-summary.schema.json`
Defines the summary JSON file emitted after each containerized installer execution. Fields capture runtime metadata, release selection, and success/failure indicators.

| Field | Purpose |
|-------|---------|
| image | Container image reference used for run |
| containerId | Underlying Docker container ID |
| startTime / endTime | Execution window (UTC ISO 8601) |
| durationSeconds | Derived duration for reporting SLAs |
| releaseTag | GitHub release tag under test |
| assetName | Release artifact file name (overlay zip) |
| exitCode | Raw installer exit code |
| success | Boolean convenience flag (exitCode == 0) |
| psVersion | PowerShell version inside container (must be >=7.2) |
| errorSummary | Present only when success=false with concise failure reason |
| logs.transcript | Relative path to transcript file |
| logs.additional | Array of any extra log file paths (future use) |

## File Naming Conventions
- Summary JSON: `out/test-install/summary.json`
- Transcript: `out/test-install/install.transcript.txt`

## Versioning
Changes to schema require bumping spec version references and validating compatibility with existing CI consumers. Add backward-compatible fields as optional; mark breaking removals clearly in release notes.
