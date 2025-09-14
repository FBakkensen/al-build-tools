## Contract: Test Discovery & Guards

### Scope
Defines the discovery rules and guard semantics for cross-platform test execution in CI.

### Discovery Rules
| OS | Pattern | Recursive | Framework | Command |
|----|---------|-----------|-----------|---------|
| Linux | `**/*.bats` | Yes | bats-core | `bats -r tests` |
| Windows | `**/*.Tests.ps1` | Yes | Pester v5 | `Invoke-Pester -Path tests -CI` |

### Guards
Executed prior to running frameworks:
- Linux: Fail with exit 1 if zero matches → `No Bats tests (*.bats) found under tests/.`
- Windows: Fail with exit 1 if zero matches → `No Pester tests (*.Tests.ps1) found under tests/.`

### Migration Requirements
Each prior legacy `test_*.sh` must be:
1. Ported to equivalent Bats and/or Pester test, OR
2. Explicitly retired with rationale documented in PR (coverage table).

### Non-Goals
- Enforcing parity at file name level.
- Sharding or parallel test distribution.
- macOS runner inclusion (deferred).

### Change Control
Altering patterns or guard strings is a breaking CI contract requiring spec update + PR justification.
