# Traceability: install.ps1 Test Coverage

This living stub aligns functional requirements (FR-001..FR-025) with the test files that will verify them. Update the "Planned/Pending Test Coverage" column as each test lands or file names change.

| FR ID | Planned/Pending Test Coverage | Notes |
|-------|--------------------------------|-------|
| FR-001 | T010 - `tests/integration/Install.Success.Basic.Tests.ps1`<br>T018 - `tests/integration/Install.TempWorkspaceLifecycle.Tests.ps1` | Validates happy path completion and temp workspace lifecycle. |
| FR-002 | T011 - `tests/integration/Install.IdempotentOverwrite.Tests.ps1` | Confirms deterministic overwrite behavior on rerun. |
| FR-003 | _(pending)_ | Identify prerequisite guard scenario (e.g., missing required tool) and add dedicated contract test. |
| FR-004 | T007 - `tests/contract/Install.PowerShellVersionUnsupported.Tests.ps1` | Ensures version guard blocks unsupported PowerShell. |
| FR-005 | T012 - `tests/integration/Install.NoWritesOnFailure.Tests.ps1` | Asserts no overlay writes occur when acquisition fails. |
| FR-006 | T010 - `tests/integration/Install.Success.Basic.Tests.ps1` | Confirms expected postconditions after success. |
| FR-007 | T023 - `tests/contract/Install.RestrictedWrites.Tests.ps1` | Guards against filesystem writes outside overlay scope. |
| FR-008 | T008 - `tests/contract/Install.UnknownParameter.Tests.ps1` | Verifies unsupported arguments are rejected with guidance. |
| FR-009 | T017 - `tests/contract/Install.Diagnostics.Stability.Tests.ps1` | Locks diagnostic line format for guards/success/failure. |
| FR-010 | T020 - `tests/integration/Install.PerformanceBudget.Tests.ps1` | Tracks runtime against <30s performance target. |
| FR-011 | T021 - `tests/integration/Install.EnvironmentIsolation.Tests.ps1` | Ensures sequential runs remain isolated. |
| FR-012 | T040 - `README` contributor guide snippet | Documentation requirement captured via repo docs update. |
| FR-013 | T004/T038 - `specs/005-add-tests-for/traceability.md` | This matrix provides ongoing requirement-to-test mapping. |
| FR-014 | T012 - `tests/integration/Install.NoWritesOnFailure.Tests.ps1`<br>T013 - `tests/contract/Install.DownloadFailure.NetworkUnavailable.Tests.ps1`<br>T014 - `tests/contract/Install.DownloadFailure.NotFound.Tests.ps1`<br>T015 - `tests/contract/Install.DownloadFailure.CorruptArchive.Tests.ps1`<br>T016 - `tests/contract/Install.DownloadFailure.Timeout.Tests.ps1` | Covers download failure classification and side-effect guards. |
| FR-015 | T009 - `tests/contract/Install.NonCleanAfterPartialFailure.Tests.ps1` | Validates rerun blocked when repo dirty after partial copy. |
| FR-016 | T022 - `tests/integration/Install.Parity.Structure.Tests.ps1` | Shared structure assertions across OSes. |
| FR-017 | T022 - `tests/integration/Install.Parity.Structure.Tests.ps1` | Ensures diagnostics and steps align cross-platform. |
| FR-018 | T011 - `tests/integration/Install.IdempotentOverwrite.Tests.ps1`<br>T022 - `tests/integration/Install.Parity.Structure.Tests.ps1` | Confirms overwrite parity on each OS. |
| FR-019 | T018 - `tests/integration/Install.TempWorkspaceLifecycle.Tests.ps1` | Observes temp workspace creation/removal. |
| FR-020 | T019 - `tests/integration/Install.PermissionDenied.Tests.ps1` | Simulates permission-denied copy failure. |
| FR-021 | T001 - `tests/_install/Assert-Install.psm1` helpers<br>T022 - `tests/integration/Install.Parity.Structure.Tests.ps1` | Shared helpers keep assertions platform-neutral; parity test enforces no OS-specific drift. |
| FR-022 | T022 - `tests/integration/Install.Parity.Structure.Tests.ps1` | Single suite expected to pass on Windows & Ubuntu. |
| FR-023 | T005 - `tests/contract/Install.GitRepoRequired.Tests.ps1`<br>T024 - Implementation complete | Guard for missing git repository. Implementation verified working. |
| FR-024 | T006 - `tests/contract/Install.WorkingTreeNotClean.Tests.ps1` | Guard for dirty git state. |
| FR-025 | T011 - `tests/integration/Install.IdempotentOverwrite.Tests.ps1` | One-command install/update idempotence enforcement. |

_Last updated: 2025-09-17 - T024 implementation verified complete (git repo guard logic already implemented and tested)._
