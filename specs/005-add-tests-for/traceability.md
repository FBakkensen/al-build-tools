# Traceability: install.ps1 Test Coverage

This matrix captures the definitive mapping between functional requirements FR-001..FR-025 and the automated coverage (tests or documentation) that enforces each behavior.

| FR ID | Implemented Coverage | Notes |
|-------|-----------------------|-------|
| FR-001 | `tests/integration/Install.Success.Basic.Tests.ps1`<br>`tests/integration/Install.TempWorkspaceLifecycle.Tests.ps1` | Validates happy-path completion including temp workspace observability. |
| FR-002 | `tests/integration/Install.IdempotentOverwrite.Tests.ps1` | Confirms deterministic overwrite behavior on repeat installs. |
| FR-003 | `tests/contract/Install.GitRepoRequired.Tests.ps1`<br>`tests/contract/Install.PowerShellVersionUnsupported.Tests.ps1` | Guards fail fast when mandatory prerequisites (git metadata, supported pwsh) are absent. |
| FR-004 | `tests/contract/Install.PowerShellVersionUnsupported.Tests.ps1` | Forces failure with `[install] guard PowerShellVersionUnsupported` on unsupported versions. |
| FR-005 | `tests/integration/Install.NoWritesOnFailure.Tests.ps1` | Asserts destination is untouched when acquisition fails. |
| FR-006 | `tests/integration/Install.Success.Basic.Tests.ps1` | Checks required overlay artifacts and success diagnostics after completion. |
| FR-007 | `tests/contract/Install.RestrictedWrites.Tests.ps1` | Ensures copy never escapes overlay scope. |
| FR-008 | `tests/contract/Install.UnknownParameter.Tests.ps1` | Rejects unsupported parameters with usage guidance. |
| FR-009 | `tests/contract/Install.Diagnostics.Stability.Tests.ps1` | Locks guard, success, and failure diagnostic formats. |
| FR-010 | `tests/integration/Install.PerformanceBudget.Tests.ps1` | Enforces sub-30s performance budget via parsed duration. |
| FR-011 | `tests/integration/Install.EnvironmentIsolation.Tests.ps1` | Runs sequential installs in isolated repos to prevent cross-run contamination. |
| FR-012 | `README.md` (Installer Test Contract)<br>`tests/contract/Install.*.Tests.ps1`<br>`tests/integration/Install.*.Tests.ps1` | Contributor guidance summarizes enforced behaviors and points to suites; update when coverage shifts. |
| FR-013 | `specs/005-add-tests-for/traceability.md` | This document provides the maintained FR ↔ coverage mapping. |
| FR-014 | `tests/integration/Install.NoWritesOnFailure.Tests.ps1`<br>`tests/contract/Install.DownloadFailure.NetworkUnavailable.Tests.ps1`<br>`tests/contract/Install.DownloadFailure.NotFound.Tests.ps1`<br>`tests/contract/Install.DownloadFailure.CorruptArchive.Tests.ps1`<br>`tests/contract/Install.DownloadFailure.Timeout.Tests.ps1` | Verifies single-line diagnostics, categorized failures, and no side-effects on acquisition errors. |
| FR-015 | `tests/contract/Install.NonCleanAfterPartialFailure.Tests.ps1` | Treats residue from partial copy as dirty working tree. |
| FR-016 | `tests/integration/Install.Parity.Structure.Tests.ps1` | Asserts consistent step sequencing/labels across platforms. |
| FR-017 | `tests/integration/Install.Parity.Structure.Tests.ps1` | Checks diagnostics remain structurally comparable regardless of OS paths. |
| FR-018 | `tests/integration/Install.IdempotentOverwrite.Tests.ps1`<br>`tests/integration/Install.EnvironmentIsolation.Tests.ps1` | Ensures deterministic overwrites on each OS and no stale state. |
| FR-019 | `tests/integration/Install.TempWorkspaceLifecycle.Tests.ps1`<br>`tests/integration/Install.EnvironmentIsolation.Tests.ps1` | Validates temp workspace creation/cleanup and uniqueness per run. |
| FR-020 | `tests/integration/Install.PermissionDenied.Tests.ps1` | Surfaces `[install] guard PermissionDenied` when filesystem blocks writes. |
| FR-021 | `tests/_install/Assert-Install.psm1`<br>`tests/integration/Install.Parity.Structure.Tests.ps1` | Helpers enforce path-agnostic assertions; parity suite ensures no OS-specific drift. |
| FR-022 | `tests/integration/Install.Parity.Structure.Tests.ps1`<br>`tests/integration/Install.EnvironmentIsolation.Tests.ps1` | Requires parity-focused suites to pass on Windows and Ubuntu. |
| FR-023 | `tests/contract/Install.GitRepoRequired.Tests.ps1` | Fails with `[install] guard GitRepoRequired` outside a git repo. |
| FR-024 | `tests/contract/Install.WorkingTreeNotClean.Tests.ps1` | Blocks execution when working tree is dirty. |
| FR-025 | `tests/integration/Install.IdempotentOverwrite.Tests.ps1` | Confirms single-command install/update flow realigns overlay exactly. |

_Last updated: 2025-09-17 — T040 complete; README Installer Test Contract documents FR-012._
