# Data Model: Docker-Based Install Script Test

## Overview
Two primary conceptual entities are required to represent the execution and reporting of the installer validation within a Windows container.

## Entities

### 1. TestContainerRun
Represents a single ephemeral container session executing the bootstrap installer.

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|-----------|
| id | string (UUID or timestamp token) | Yes | Logical identifier for run (not necessarily Docker container ID) | Non-empty |
| containerImage | string | Yes | Docker image reference used (e.g., mcr.microsoft.com/windows/servercore:ltsc2022) | Must match `<repo>/<image>:<tag>` pattern |
| containerId | string | Yes | Actual Docker container ID returned by runtime | 64 hex chars (short acceptable) |
| startTime | datetime (UTC) | Yes | Start time of run | ISO 8601 |
| endTime | datetime (UTC) | Yes | End time of run | endTime >= startTime |
| durationSeconds | integer | Yes | Derived: end - start in seconds | > 0 |
| releaseTag | string | Yes | GitHub release tag tested (or override value) | Non-empty |
| assetName | string | Yes | Downloaded release asset file name | Non-empty; ends with .zip |
| exitCode | int | Yes | Installer process exit code | >= 0 |
| success | bool | Yes | Convenience flag (exitCode -eq 0) | Matches exitCode logic |
| psVersion | string | Yes | PowerShell version used inside container | Semantic version >= 7.2 |
| logsPath | string | Yes | Relative path to transcript/log root exported | Non-empty |
| retries | int | No | Number of retry attempts performed | >= 0 |
| errorSummary | string | No | Short description of failure cause if any | Present when success=false |

#### Relationships
- One `TestContainerRun` produces exactly one `InstallerExecutionReport`.

### 2. InstallerExecutionReport
Aggregated diagnostic outputs from a container run.

| Field | Type | Required | Description | Validation |
|-------|------|----------|-------------|-----------|
| runId | string | Yes | Foreign key referencing TestContainerRun.id | Must exist |
| transcriptFile | string | Yes | Path to PowerShell Start-Transcript output | File must exist |
| summaryJsonFile | string | Yes | JSON summary file path | File must exist; valid JSON |
| additionalLogs | string[] | No | Array of other log file paths (future: pester, download logs) | Paths exist |
| artifactName | string | Yes | Actions artifact name uploaded | Non-empty |
| createdTime | datetime (UTC) | Yes | When report assembled | ISO 8601 |

#### Derived Values
- `success` derived from linked TestContainerRun.exitCode.
- `durationSeconds` stored redundantly in summary for quick inspection.

## State Transitions

### TestContainerRun Lifecycle
```
PENDING (initialized metadata)
  -> RUNNING (container started)
  -> COMPLETED (container exited, exitCode captured)
     -> (implicit) REPORTED (artifacts exported & uploaded)
```
All transitions are linear (no retries in MVP). Future retries would branch from PENDING or a RETRY_PENDING after a failure.

## Validation Rules
- A run is considered successful only if exitCode == 0 and transcriptFile exists and is non-empty.
- If success=false, errorSummary must be populated with at least one line referencing failing stage.
- PowerShell version must parse as semantic version and be >= 7.2 (string compare after normalization).

## Open Extensions (Future)
- Add LinuxContainerRun variant for parity.
- Add PesterResults entity referencing structured test results.
- Add metrics aggregation for historical timing benchmarks.
