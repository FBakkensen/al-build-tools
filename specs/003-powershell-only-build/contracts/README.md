# Contracts: PowerShell-Only Build Toolkit

This document codifies externally observable behaviors (contracts) for guarded and unguarded scripts, enabling deterministic Pester contract and integration tests.

## Scope
Applies to scripts under `overlay/scripts/make/*.ps1` (guarded) and the direct utility `overlay/scripts/next-object-number.ps1` (unguarded). Does NOT define internal function design—only surface behavior, exit codes, and messaging expectations.

## Guard Contract
| Condition | Behavior | Exit Code | Test ID |
|-----------|----------|-----------|---------|
| Direct invocation without `ALBT_VIA_MAKE` | Print single-line or short multi-line guidance containing phrase `Run via make` | 2 | GUARD-DIRECT |
| Help flag (`-h`, `--help`, `-?`) without guard | Same guard response (no full help) | 2 | GUARD-HELP |
| Invocation via make (env var present) | Proceed to pre-flight | n/a | GUARD-PASS |

## Help Contract (Guard Satisfied)
| Aspect | Requirement | Test ID |
|--------|-------------|---------|
| Flags | Support `-h`, `--help`, `-?` synonyms | HELP-FLAGS |
| Content | Displays name, brief description, usage synopsis, exit code table reference | HELP-CONTENT |
| Exit | Exits 0 after printing help (guard satisfied) | HELP-EXIT |

## Verbosity Contract
| Trigger | Expected Behavior | Test ID |
|---------|-------------------|---------|
| `VERBOSE=1 make build` | Additional diagnostic lines prefixed with `VERBOSE:` or using standard Verbose stream | VERBOSE-ENV |
| `make build -- -Verbose` (if passthrough) | Same as env var | VERBOSE-FLAG |
| Neither provided | No verbose diagnostics | VERBOSE-DEFAULT |

## Static Analysis Contract
| Condition | Behavior | Exit Code | Test ID |
|-----------|----------|-----------|---------|
| Run PSSA finds violations | Emit diagnostics; abort before tests | 3 | PSSA-FAIL |
| No violations | Continue workflow | 0 (phase success) | PSSA-PASS |
| Attempt to suppress by bypass flag (if added) | Refuse and exit | 3 | PSSA-BYPASS |

## Required Tool Contract
| Missing Tool | Behavior | Exit Code | Test ID |
|--------------|----------|-----------|---------|
| PSScriptAnalyzer absent | Fail fast (`Missing required tool: PSScriptAnalyzer`) | 6 | TOOL-PSSA |
| Pester absent (when running tests) | Fail contract/integration invocation fast | 6 | TOOL-PESTER |

## Exit Code Mapping
| Code | Meaning | Stable | Test ID |
|------|---------|--------|---------|
| 0 | Success | Yes | EXIT-0 |
| 2 | Guard violation | Yes | EXIT-2 |
| 3 | Static analysis failure | Yes | EXIT-3 |
| 4 | Contract tests failed | Yes | EXIT-4 |
| 5 | Integration tests failed | Yes | EXIT-5 |
| 6 | Missing required tool | Yes | EXIT-6 |
| >6 | Unexpected | Yes (semantic) | EXIT-UNEXPECTED |

## Integration Contract
| Scenario | Assertions | Test ID |
|----------|-----------|---------|
| Build parity | Build target produces expected artifacts (placeholder for future AL outputs) | INT-BUILD |
| Clean idempotence | Clean target removes artifacts; second run no error | INT-CLEAN |
| Show config | Output contains stable key list (e.g., `Platform:` `PowerShellVersion:`) | INT-CONFIG |
| Show analyzers | Reports installed analyzers or explicit 'None found' | INT-ANALYZERS |
| Environment isolation | Post-run parent process lacks `ALBT_VIA_MAKE` | INT-ENV-ISO |
| Cross-platform parity | Key output lines match across Windows & Ubuntu (normalized) | INT-PARITY |

## Direct Utility Contract (next-object-number.ps1)
| Aspect | Requirement | Test ID |
|--------|-------------|---------|
| Guard | No guard required | UTIL-NOGUARD |
| Help | `-h/--help/-?` prints usage and exits 0 | UTIL-HELP |
| Error Handling | Invalid args produce non-zero with message | UTIL-ARGS |

## Non-Goals
- Performance benchmarks (tracked separately in success metrics)
- Internal logging format (only presence/absence for verbosity)

## Change Control
Any modification to exit codes, guard semantics, or required tool list MUST update:
1. This contracts document
2. `quickstart.md`
3. Associated Pester tests

## Traceability Matrix (Sample)
| FR ID | Contract Test IDs |
|-------|-------------------|
| FR-001 | INT-BUILD, INT-CLEAN, INT-CONFIG, INT-ANALYZERS |
| FR-002 | GUARD-PASS, GUARD-DIRECT |
| FR-003 | GUARD-DIRECT |
| FR-004 | GUARD-HELP, HELP-FLAGS |
| FR-005 | UTIL-NOGUARD, UTIL-HELP |
| FR-006 | VERBOSE-ENV, VERBOSE-FLAG, VERBOSE-DEFAULT |
| FR-007 | INT-PARITY (indirect), absence in test logs |
| FR-008 | PSSA-FAIL, PSSA-PASS |
| FR-009 | INT-PARITY, INT-BUILD |
| FR-010 | GUARD-* , HELP-* , EXIT-2 |
| FR-011 | INT-* suite |
| FR-012 | INT-ENV-ISO |
| FR-013 | INT-ENV-ISO, GUARD-PASS |
| FR-014 | Static presence check (#requires) (implicit) |
| FR-015 | HELP-CONTENT, UTIL-HELP |
| FR-016 | INT-* parity tests |
| FR-017 | PSSA-FAIL |
| FR-018 | (Future CI artifact assertion) |
| FR-019 | PSSA-PASS (no network) |
| FR-020 | PSSA-BYPASS |
| FR-021 | Presence of #requires only (implicit) |
| FR-022 | INT-PARITY (unsupported platform test optional) |
| FR-023 | TOOL-PSSA, TOOL-PESTER |
| FR-024 | EXIT-* tests |
| FR-025 | GUARD-HELP |

## Future Extensions (Document Before Implementing)
- Additional make targets (e.g., `make test`) must conform to guard + exit code map.
- Optional `make help` aggregator target referencing guarded scripts.
