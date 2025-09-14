# Data Model: PowerShell-Only Build Script Consolidation

Although no persistent datastore is introduced, the feature defines conceptual entities and process relationships shaping contracts and tests.

## Conceptual Entities
| Entity | Description | Key Attributes | Relationships |
|--------|-------------|----------------|--------------|
| GuardedScript | A PowerShell entrypoint only valid when invoked via `make` | Name, Path, RequiresVersion, SupportsVerbose | Uses GuardMechanism |
| UnguardedScript | Direct-use utility not requiring guard | Name, Path | N/A |
| GuardMechanism | Enforcement primitive using env var | VariableName (`ALBT_VIA_MAKE`), ExitCodeOnViolation (2) | Validates GuardedScript |
| StaticAnalysisGate | Mandatory quality stage before tests | Tool (PSScriptAnalyzer), ExitCodeFail (3) | Blocks TestSuites |
| ContractTestSuite | Verifies externally observable behavior | Cases, ExitCodeFail (4) | Depends on GuardedScript, GuardMechanism |
| IntegrationTestSuite | Cross-platform end-to-end validation via `make` | Scenarios, ExitCodeFail (5) | Depends on GuardedScript, MakeInfrastructure |
| MissingToolDetector | Pre-flight tool presence checker | RequiredTools[], ExitCodeMissing (6) | Feeds StaticAnalysisGate |
| MakeInfrastructure | Orchestrator setting/unsetting guard var | Recipes, Shell (`pwsh`) | Invokes GuardedScript |
| VerbosityControl | Unified verbosity behavior | EnvVar (`VERBOSE`), Flag (`-Verbose`) | Affects GuardedScript logging |
| ExitCodeMap | Central mapping for CI & docs | Codes[], Meanings | Referenced by all scripts |

## Relationships Diagram (Textual)
```
MakeInfrastructure --> (sets env) GuardMechanism --> GuardedScript
GuardedScript --> VerbosityControl
GuardedScript --> ExitCodeMap
MissingToolDetector --> StaticAnalysisGate --> (on success) ContractTestSuite --> IntegrationTestSuite
UnguardedScript (independent) --> ExitCodeMap
```

## State & Transitions
| State | Trigger | Next State | Notes |
|-------|---------|-----------|-------|
| InvocationStarted | make recipe executes | GuardCheck | Env variable injected |
| GuardCheck | `ALBT_VIA_MAKE` missing | Terminated(Code=2) | Early exit, stub guidance |
| GuardCheck | `ALBT_VIA_MAKE` present | PreFlight | Proceed |
| PreFlight | Missing tool | Terminated(Code=6) | Tool list emitted |
| PreFlight | Tools present | StaticAnalysis | Only for analysis target OR before tests |
| StaticAnalysis | Violations | Terminated(Code=3) | Fail fast |
| StaticAnalysis | Clean | CommandExecution | Normal path |
| CommandExecution | Success | Completed(Code=0) | Build/clean/etc done |
| CommandExecution | Internal error | Terminated(Code>6) | Unmapped error |

## Exit Codes Reference
| Code | Symbol | Meaning |
|------|--------|---------|
| 0 | SUCCESS | Normal successful completion |
| 2 | GUARD_VIOLATION | Script not invoked via make |
| 3 | STATIC_ANALYSIS_FAILED | PSScriptAnalyzer errors or disallowed suppress bypass |
| 4 | CONTRACT_TEST_FAILED | Contract test suite failure |
| 5 | INTEGRATION_TEST_FAILED | Integration test suite failure |
| 6 | MISSING_REQUIRED_TOOL | Required module absent |
| >6 | UNEXPECTED_ERROR | Unclassified internal failure |

## Data Validation Rules
- GuardMechanism: Must check before any argument parsing or help output (FR-003, FR-004).
- VerbosityControl: If `VERBOSE` env var equals `1`, treat as if `-Verbose` passed.
- MissingToolDetector: Fails on first missing tool; output lists required set.
- StaticAnalysisGate: Must not run tests if exit code 3 emitted.
- Environment Leakage: After completion, parent environment MUST NOT contain `ALBT_VIA_MAKE`.

## Non-Persisted Derived Values
- HelpStubLines: <=5 lines unguarded (computed at runtime when guard fails but help flag present).
- PlatformIdentifier: Derived from `$PSVersionTable.OS` to produce parity messages (used only for integration comparison; no branching beyond supported/not-supported check).

## Open Modeling Considerations
None—model intentionally lean; additions require justification referencing simplicity principle.
