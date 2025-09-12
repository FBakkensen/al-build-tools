# Data Model (Conceptual) – Bootstrap Installer Tests

The feature does not introduce persistent application domain entities. Instead we model transient test artifacts.

## Ephemeral Entities
| Entity | Purpose | Key Attributes | Lifecycle |
|--------|---------|----------------|-----------|
| TempDestination | Target directory for installation | path, isGitRepo(bool), preExistingFiles[] | Created per test, deleted after test |
| OverlaySnapshot | Representation of installed overlay state | fileList[], sha256Map{path->hash} | Captured after install and re-run |
| ToolAvailabilityMatrix | Simulated environment capabilities | hasUnzip, hasPython | Derived by PATH filtering |

## Relationships
- TempDestination produces an OverlaySnapshot after each installation run.
- ToolAvailabilityMatrix influences expected outcome (success vs failure path).

## Invariants
- OverlaySnapshot.fileList must include `overlay/Makefile` and at least one platform script under `overlay/scripts/make/linux/`.
- Re-run under unchanged ToolAvailabilityMatrix must produce identical sha256Map.
- Sentinel file placed pre-install must persist untouched post-install.

## State Transitions
```
UNINITIALIZED -> INSTALLED_ONCE -> REINSTALLED (idempotent) -> CLEANED (teardown)
```
Failure path transitions end test early with assertion logs.
