# Contracts: PowerShell-Only Build Toolkit

This document defines normative externally observable contracts (C1–C14). Each contract is independently testable. Implementation MAY refactor internals provided these behaviors and exit semantics remain stable. As of the relocation update, legacy Bash scripts have been removed and Windows PowerShell scripts were relocated to a neutral path; FR-025 introduces a parity requirement: relocated outputs must match pre‑relocation Windows baselines (normalized) unless an enhancement is explicitly documented. For a detailed inventory of the pre‑relocation Windows scripts and behaviors, see [inventory-windows-scripts.md](file:///d:/repos/al-build-tools/specs/003-powershell-only-build/inventory-windows-scripts.md).

## Scope
Applies to guarded make targets (`build`, `clean`, `show-config`, `show-analyzers`) and the unguarded utility `next-object-number.ps1`. Internal helper functions, CI scripts, and analyzer configuration are explicitly out-of-scope.

## Contract Index
| ID | Name | Summary |
|----|------|---------|
| C1 | Make Targets | Only documented targets + direct utility are public surface. |
| C2 | Variable Precedence | Environment variables set by `make` override internal defaults; scripts never silently mutate them. |
| C3 | Ruleset Resolution | Optional `RULESET_PATH` included only if file exists and length > 0; otherwise warning + skip. |
| C4 | Warnings-as-Errors | Enabled when `WARN_AS_ERROR` ∈ {1,true,yes,on} (case-insensitive). |
| C5 | Analyzer Settings | Analyzer DLLs resolved from `.vscode/settings.json`; invalid/missing file → empty set (no failure). |
| C6 | Analyzer Listing | `show-analyzers` exits 0, listing each analyzer DLL used by build or stating 'No analyzers found'. |
| C7 | Config Display | `show-config` emits stable key=value lines (≥ Platform, PowerShellVersion, RulesetStatus, WarningsAsErrors). |
| C8 | Compiler Discovery | Highest-version AL compiler selected; absence aborts build with clear error. |
| C9 | Exit Code Mapping | Standard codes (0,2,3,4,5,6,>6) + documented reuse of 2 for guard and range exhaustion (next-object-number). |
| C10 | Output Paths | Deterministic output & package cache paths; stale output removed prior to build. |
| C11 | Next Object Number | First free ID within declared `idRanges`; exhaustion → exit 2; malformed app.json → exit 1; success prints number (no extra text). |
| C12 | JSON Robustness | Malformed JSON yields non-zero exit with concise error; no partial operations. |
| C13 | Cross-Platform Parity | Normalized outputs of core targets functionally equivalent across supported OSes. |
| C14 | Side-Effect Boundaries | No network calls; filesystem writes restricted to build artifact & package cache.

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

## Static Analysis Contract (CI Only)
| Condition | Behavior | Exit Code | Test ID |
|-----------|----------|-----------|---------|
| Run PSSA finds violations (CI job) | Emit diagnostics; abort before test stages | 3 | PSSA-FAIL |
| No violations | Continue workflow | 0 (phase success) | PSSA-PASS |
| Attempt to bypass (if future flag) | Refuse and exit | 3 | PSSA-BYPASS |

## Required Tool Contract (CI / Dev Environment)
| Missing Tool | Behavior | Exit Code | Test ID |
|--------------|----------|-----------|---------|
| PSScriptAnalyzer absent | Fail fast in analysis stage (`Missing required tool: PSScriptAnalyzer`) | 6 | TOOL-PSSA |
| Pester absent (when running tests) | Fail contract/integration stage fast | 6 | TOOL-PESTER |

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

## Direct Utility Contract (next-object-number.ps1) (C11 specifics)
| Aspect | Requirement | Test ID |
|--------|-------------|---------|
| Guard | No guard required | UTIL-NOGUARD |
| Success | Outputs ONLY the numeric ID; exit 0 | UTIL-SUCCESS |
| Exhausted | Message: `No available <Type> number...`; exit 2 | UTIL-EXHAUST |
| Malformed app.json | Clear error message; exit 1 | UTIL-MALFORMED |
| Help | (`-h|--help|-?`) prints usage (≤5 lines) exit 0 | UTIL-HELP |
| Arg Validation | Missing object type argument exit 1 with usage | UTIL-ARGS |

## Non-Goals
- Internal logging format (only presence/absence for verbosity)

## Change Control
Any modification to exit codes, guard semantics, or required tool list MUST update:
1. This contracts document
2. `quickstart.md`
3. Associated Pester tests
4. Parity baselines (if change intentionally alters observable output) with an accompanying note referencing FR-025.

## Traceability Matrix (FR → Contracts → Tests)
| FR ID | Contract IDs | Representative Test IDs |
|-------|--------------|-------------------------|
| FR-001 | C1,C10 | INT-BUILD, INT-CLEAN |
| FR-002 | C1,C9 | GUARD-DIRECT |
| FR-003 | C1,C9 | GUARD-DIRECT |
| FR-004 | C1,C9 | GUARD-HELP, HELP-FLAGS |
| FR-005 | C11 | UTIL-NOGUARD, UTIL-HELP |
| FR-006 | C2 | VERBOSE-ENV, VERBOSE-FLAG |
| FR-007 | C14 | INT-PARITY (log scan) |
| FR-008 | C9 | PSSA-FAIL |
| FR-009 | C13 | INT-PARITY |
| FR-010 | C9 | EXIT-2, GUARD-* |
| FR-011 | C7,C6 | INT-CONFIG, INT-ANALYZERS |
| FR-012 | C14 | INT-ENV-ISO |
| FR-013 | C2 | INT-ENV-ISO |
| FR-014 | (implicit) | REQUIRES-VERSION |
| FR-015 | C1 | HELP-CONTENT, QUICKSTART spot checks |
| FR-016 | C13 | INT-PARITY |
| FR-017 | C9 | PSSA-FAIL |
| FR-018 | C9 | EXIT-4, EXIT-5 artifact presence |
| FR-019 | C14 | PSSA-PASS (no network) |
| FR-020 | C9 | PSSA-BYPASS |
| FR-021 | (implicit) | REQUIRES-VERSION |
| FR-022 | C13 | INT-PARITY (platform gating) |
| FR-023 | C9 | TOOL-PSSA, TOOL-PESTER |
| FR-024 | C9 | EXIT-* suite |
| FR-025 | C1 (parity overlay), C13 | Parity baseline tests |

## Future Extensions (Document Before Implementing)
- Additional make targets (e.g., `make test`) must conform to guard + exit code map.
- Optional `make help` aggregator target referencing guarded scripts.
- If a future enhancement changes observable output of a relocated script, update or regenerate the associated parity baseline and document the intentional divergence (FR-025 compliance log).
