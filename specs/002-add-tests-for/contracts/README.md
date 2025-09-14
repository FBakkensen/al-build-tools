# Contracts – Bootstrap Installer Tests

The contracts define observable behaviors validated by the test suite.

## Contract List
| ID | Title | Description | Source Requirements |
|----|-------|-------------|---------------------|
| C-INIT | Initial Installation Success | Installing into empty directory populates overlay files and exits 0 | FR-001 |
| C-IDEMP | Idempotent Re-run | Second run updates in place without new/duplicate artifacts | FR-002 |
| C-GIT | Git Detection Behavior | Git repo destination produces no missing-git warning; non-git does warn (non-fatal) | FR-003 |
| C-CUSTOM-DEST | Custom Destination Creation | Non-existent --dest path created and populated | FR-004 |
| C-FALLBACK | Python Fallback Extraction | Missing unzip triggers python extraction success | FR-005 |
| C-HARD-FAIL | Extraction Hard Failure | Missing both unzip and python yields non-zero exit with message | FR-006, FR-010 |
| C-PRESERVE | Preserve Unrelated Files | Pre-existing unrelated files untouched | FR-007 |
| C-GIT-METADATA | Preserve .git Metadata | No mutation of .git after installation | FR-008 |
| C-REPORT | Success Reporting | Installer reports success indicator (file count or similar) | FR-009 |
| C-EXIT-CODES | Error Exit Codes | All failure paths return non-zero | FR-010 |
| C-NO-SIDE-EFFECTS | No External Side Effects | No artifacts outside destination | FR-012 |
| C-SPACES | Path With Spaces | Destination containing spaces installs successfully | Edge Case |
| C-READONLY | Read-only Destination Fails | Read-only directory causes permission error, non-zero exit | Edge Case |

## Assertion Strategy
Each contract will map to one test file. Assertions use:
- Exit code check
- Presence/absence of warning lines
- File hash comparisons (sha256sum) for idempotence
- Grep for expected stderr substrings on failure

## Non-Goals
No validation of overlay internal script logic; only presence and non-corruption.
