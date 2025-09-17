# Data Model (Conceptual for Test Traceability)

## Entities

### InstallerSession
- Fields:
  - ref (string) - source git ref used for overlay
  - startTime (datetime)
  - endTime (datetime)
  - tempWorkspacePath (string)
  - exitCode (int)
  - outcome (enum: Success|Failure)
  - failureCategory (enum per FR-014) optional
  - diagnostics (string[])
- Relationships: 1-to-many with DownloadAttempt; 1-to-many with GuardRailOutcome

### DownloadAttempt
- Fields:
  - url (string)
  - timestamp (datetime)
  - result (enum: Success|Failure)
  - category (enum per FR-014)
  - hint (string)

### GuardRailOutcome
- Fields:
  - name (string) e.g., PowerShellVersion, CleanGitState, GitRepoPresent
  - passed (bool)
  - message (string)

## Derived Test Assertions Mapping
| Requirement | Entity Focus | Assertion Strategy |
|-------------|--------------|--------------------|
| FR-001 | InstallerSession | Successful outcome, temp workspace ephemeral |
| FR-002 / FR-025 | InstallerSession | Hash comparison before/after second run |
| FR-003 / FR-004 | GuardRailOutcome | Specific guard fails with message |
| FR-005 | InstallerSession | No overlay files when failure pre-copy |
| FR-006 | InstallerSession | Expected overlay artifacts exist post success |
| FR-007 | GuardRailOutcome | No writes outside overlay path |
| FR-008 | GuardRailOutcome | Unknown parameter rejected |
| FR-009 | InstallerSession | Diagnostic lines stable patterns |
| FR-010 | InstallerSession | Execution duration < 30s |
| FR-011 | InstallerSession | Independent fresh git working trees |
| FR-012 | (Documentation) | Quickstart maps scenarios -> tests |
| FR-013 | (Traceability) | This table + tasks mapping |
| FR-014 | DownloadAttempt | Single-line diagnostic pattern |
| FR-015 | GuardRailOutcome | Re-run blocked when dirty after partial failure |
| FR-016-018 | InstallerSession | Parity tests both OSes |
| FR-019 | InstallerSession | Temp workspace created & removed |
| FR-020 | GuardRailOutcome | Permission failure captured |
| FR-021 | Testing Harness | Shared assertions no OS branching |
| FR-022 | Testing Harness | Single suite pass implies parity |
| FR-023 | GuardRailOutcome | Non-git path abort |
| FR-024 | GuardRailOutcome | Dirty git state abort |
