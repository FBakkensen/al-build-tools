# Data Model: PowerShell-Only Build Script Consolidation

Although no persistent datastore is introduced, the feature defines conceptual entities and process relationships shaping contracts and tests.

## Conceptual Entities
| Entity | Description | Key Attributes | Relationships |
|--------|-------------|----------------|--------------|
| GuardedScript | A PowerShell entrypoint only valid when invoked via `make` (C1) | Name, Path, RequiresVersion, SupportsVerbose, Contracts(C1,C2,C3,C4,C7,C8,C9,C10,C12,C13,C14) | Uses GuardMechanism |
| UnguardedScript | Direct-use utility not requiring guard (C11) | Name, Path, Contracts(C11,C12) | N/A |
| GuardMechanism | Inline env var check per script (no shared shipped module) (C1,C9) | VariableName (`ALBT_VIA_MAKE`), ExitCodeOnViolation (2) | Validates GuardedScript |
| StaticAnalysisGate | CI-only quality stage (not part of overlay runtime) | Tool (PSScriptAnalyzer), ExitCodeFail (3) | Blocks TestSuites |
| ContractTestSuite | Verifies externally observable behavior | Cases, ExitCodeFail (4) | Depends on GuardedScript, GuardMechanism |
| IntegrationTestSuite | Cross-platform end-to-end validation via `make` | Scenarios, ExitCodeFail (5) | Depends on GuardedScript, MakeInfrastructure |
| MissingToolDetection (CI) | CI step ensures required modules installed | RequiredTools[], ExitCodeMissing (6) | Precedes StaticAnalysisGate |
| MakeInfrastructure | Orchestrator setting/unsetting guard var | Recipes, Shell (`pwsh`) | Invokes GuardedScript |
| VerbosityControl | Unified verbosity behavior (C2) | EnvVar (`VERBOSE`), Flag (`-Verbose`) | Affects GuardedScript logging |
| ExitCodeMap | Central mapping for CI & docs (C9) | Codes[], Meanings | Referenced by all scripts |
| RelocatedScript | Former Windows-only script moved to neutral folder | OriginalPath, NewPath, ParityBaselineRef | Is a GuardedScript |
| DeprecatedScript | Removed Bash or Windows wrapper script | OriginalPath, RemovalCommit, Replacement | ReplacedBy RelocatedScript |
| ParityBaseline | Stored normalized output snapshot pre-relocation | ScriptName, CaptureDate, NormalizationRules | ComparedBy ContractTestSuite |

Pre‑relocation script behavior inventory is maintained at [inventory-windows-scripts.md](file:///d:/repos/al-build-tools/specs/003-powershell-only-build/inventory-windows-scripts.md) and serves as a reference for RelocatedScript semantics prior to enhancement.

## Relationships Diagram (Textual)
```
MakeInfrastructure --> (sets env) GuardMechanism (inline) --> GuardedScript
GuardedScript --> VerbosityControl
GuardedScript --> ExitCodeMap
CI MissingToolDetection --> StaticAnalysisGate --> ContractTestSuite --> IntegrationTestSuite
UnguardedScript (independent) --> ExitCodeMap
RelocatedScript (specialization) --> GuardedScript
ParityBaseline --> ContractTestSuite (parity checks)
DeprecatedScript --> (ReplacedBy) RelocatedScript
```

## State & Transitions
| State | Trigger | Next State | Notes |
|-------|---------|-----------|-------|
| InvocationStarted | make recipe executes | GuardCheck | Env variable injected |
| GuardCheck | `ALBT_VIA_MAKE` missing | Terminated(Code=2) | Early exit, stub guidance |
| GuardCheck | `ALBT_VIA_MAKE` present | PreFlight | Proceed |
| PreFlight (CI only) | Missing tool | Terminated(Code=6) | Tool list emitted (CI) |
| PreFlight (CI only) | Tools present | StaticAnalysis | Only in CI before tests |
| StaticAnalysis (CI) | Violations | Terminated(Code=3) | Fail fast |
| StaticAnalysis (CI) | Clean | CommandExecution | Normal path |
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
- MissingToolDetection (CI): Fails fast if required tool absent; not part of shipped overlay logic.
- StaticAnalysisGate (CI): Tests skipped when exit code 3 emitted by analysis job.
- Environment Leakage: After completion, parent environment MUST NOT contain `ALBT_VIA_MAKE`.

## Non-Persisted Derived Values
- HelpStubLines: <=5 lines unguarded (computed at runtime when guard fails but help flag present).
- PlatformIdentifier: Derived from `$PSVersionTable.OS` to produce parity messages (used only for integration comparison; no branching beyond supported/not-supported check).

## Open Modeling Considerations
None—model intentionally lean; additions require justification referencing simplicity principle.
