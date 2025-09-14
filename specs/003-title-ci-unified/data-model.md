## Data Model / Conceptual Entities

No persistent domain entities introduced. Conceptual artifacts for clarity:

| Entity | Description | Key Attributes |
|--------|-------------|----------------|
| Bats Test File | Linux-focused test script (`*.bats`) | Path, name, exit status, output |
| Pester Test File | Windows-focused test (`*.Tests.ps1`) | Path, name, result objects |
| Test Discovery Contract | Rules defining which files are executed | Pattern (`**/*.bats`, `**/*.Tests.ps1`), recursion |
| Zero-Test Guard | Pre-execution validation step | Count, error message, exit code 1 |
| Migration Coverage Table | PR-only artifact tracking legacy ports | Legacy name, new file(s), status |

State transitions are limited to test execution outcome (pass/fail) and not persisted. No further modeling required.
