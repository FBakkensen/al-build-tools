# Tasks: PowerShell-Only Build Script Consolidation

## Legend
| Status | Meaning |
|--------|---------|
| TODO | Not started |
| WIP | In progress |
| DONE | Complete |

## Task List
| ID | Title | Description / Acceptance | FR Refs | Status |
|----|-------|--------------------------|---------|--------|
| T01 | Scaffold make PS layout | Create `overlay/scripts/make/` PowerShell layout + `lib/` folder (no logic yet). | FR-001 | TODO |
| T02 | Add Guard module | Implement `lib/Guard.ps1` with `Assert-InvokedViaMake` (exit 2, guidance). | FR-002 FR-003 FR-004 | TODO |
| T03 | Add Common module | Logging helpers, verbosity normalization (env `VERBOSE=1` => `$VerbosePreference='Continue'`). | FR-006 | TODO |
| T04 | Implement build.ps1 | Header (`#requires -Version 7.2`), guard call first, minimal placeholder logic. | FR-001 FR-002 FR-014 | TODO |
| T05 | Implement clean.ps1 | Same pattern as build, placeholder artifact removal logic. | FR-001 | TODO |
| T06 | Implement show-config.ps1 | Emits stable keys (PowerShellVersion, Platform). Guard enforced. | FR-001 | TODO |
| T07 | Implement show-analyzers.ps1 | Lists installed analyzers or 'None found'. Guard enforced. | FR-001 | TODO |
| T08 | Ensure next-object-number.ps1 unchanged | Confirm presence of `#requires -Version 7.2` (add if missing) but no guard. | FR-005 FR-014 | TODO |
| T09 | Add exit code constants (doc) | (Optional) Central constant script or inline comments referencing exit codes—avoid duplication. | FR-024 | TODO |
| T10 | Makefile updates | Replace Bash targets with PowerShell invocation + guarded env var ephemeral pattern. | FR-002 FR-013 | TODO |
| T11 | PSSA settings file | Create `.config/ScriptAnalyzerSettings.psd1` with Recommended + style rules. | FR-008 | TODO |
| T12 | Add pre-flight tool check | Function `Assert-RequiredTools` (PSScriptAnalyzer always; Pester conditional). | FR-023 | TODO |
| T13 | Contract tests guard | Tests: direct call exit 2 message, help exit 2, via make success. | FR-003 FR-004 | TODO |
| T14 | Contract tests help full | With guard satisfied, help prints expected sections & exits 0. | FR-004 FR-015 | TODO |
| T15 | Contract tests verbosity | Env and flag produce additional verbose lines; absence silent. | FR-006 | TODO |
| T16 | Contract tests required tools | Simulate missing module (path isolation) exit 6. | FR-023 | TODO |
| T17 | Contract tests exit codes map | Validate mapping for known scenarios (guard, missing tool). | FR-024 | TODO |
| T18 | Integration build | `make build` executes without guard failure, artifacts placeholder. | FR-001 FR-011 | TODO |
| T19 | Integration clean idempotent | Two sequential `make clean` runs succeed. | FR-001 | TODO |
| T20 | Integration show-config parity | Output stable keys; cross-OS diff normalized equal. | FR-009 FR-011 | TODO |
| T21 | Integration show-analyzers parity | Reports analyzers or 'None found'; parity across OS. | FR-009 FR-011 | TODO |
| T22 | Integration env isolation | After `make build`, parent env lacks `ALBT_VIA_MAKE`. | FR-013 | TODO |
| T23 | Integration verbose parity | Verbose output consistent across OS (line presence/order). | FR-006 FR-009 | TODO |
| T24 | Static analysis gate script | Add CI step invoking PSSA with `-EnableExit`; ensures failure code 3. | FR-008 FR-017 | TODO |
| T25 | CI workflow authoring | Add GitHub Actions workflow matrix, order PSSA→contract→integration. | FR-009 FR-018 | TODO |
| T26 | Missing tool early fail CI | Simulate absence to ensure code path works (optional matrix job). | FR-023 | TODO |
| T27 | Documentation updates README | Update root README to state PowerShell-only + guard policy. | FR-015 FR-016 | TODO |
| T28 | Deprecation notice for Bash | Add note in spec or README marking removal timeline. | FR-016 | TODO |
| T29 | Remove Bash scripts (later) | Follow-up PR after validation; not part of initial merge tasks. | FR-016 | TODO |
| T30 | Help stub content | Ensure unguarded help stub <=5 lines referencing make. | FR-025 | TODO |
| T31 | Add test artifact publishing | Store Pester results as CI artifacts (NUnit XML). | FR-018 | TODO |
| T32 | Cross-platform normalization util | Helper to normalize line endings & whitespace for parity tests. | FR-009 | TODO |
| T33 | Performance baseline capture | Measure and log median build orchestration time for documentation. | Success Metrics | TODO |
| T34 | Tooling detection documentation | Add guidance in quickstart for missing tools exit codes. | FR-023 | TODO |

## Ordering Recommendation
1. Scaffold & guard (T01–T07, T02 first).
2. Common + exit codes + tool checks (T03, T09, T12).
3. Makefile + PSSA settings (T10–T11).
4. Contract tests (T13–T17, T30).
5. Integration tests + helpers (T18–T23, T32).
6. CI workflow & gates (T24–T26, T31).
7. Documentation & deprecation messaging (T27–T28, T34).
8. Performance baseline (T33).
9. Bash removal (T29) post-validation.

## Acceptance Completion Criteria
- All mandatory tasks T01–T28, T30–T32, T34 DONE before feature merge.
- T29 deferred to a subsequent branch after adoption period.
- PSSA clean, Pester suites green on both OS.

## Risk-Based Task Prioritization
High-risk early: Guard, tool detection, CI gate. Medium: Verbosity parity, cross-platform normalization. Low: Documentation polish, performance baseline.
