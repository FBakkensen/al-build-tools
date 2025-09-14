# Research: PowerShell-Only Build Script Consolidation

## Decision Matrix Summary
| Topic | Options Considered | Decision | Rationale | Risks | Mitigation |
|-------|--------------------|----------|-----------|-------|-----------|
| Single Language | Keep Bash + PS / PS Only | PS Only | Reduce drift, one test surface | Missed Bash-only env edge case | Contract + integration tests on Ubuntu + Windows |
| Invocation Guard | No guard / Flag param / Env var | Env var `ALBT_VIA_MAKE` | Simple, process-scoped | Var leakage | Explicit unset in make recipe + test |
| Help Strategy | Always full help / Full only guarded / Block help | Stub when unguarded | Reinforce policy while discoverable | Confuse users | Stub includes make hint |
| Version Enforcement | `#requires` only / runtime check / hybrid | `#requires -Version 7.2` | Native, zero maintenance | Less custom messaging | Document behavior |
| Verbosity Control | Custom flag / Standard -Verbose / Both | Standard + VERBOSE env | Familiar, low code | Env variable ambiguity | Normalize env→-Verbose mapping |
| Static Analysis Scope | Off / Basic / Strict | Strict recommended + style | Early defect surfacing | False positives | Scoped suppressions |
| Exit Codes | Single non-zero / Minimal / Rich mapping | Rich mapping table | Clear CI diagnostics | Slight complexity | Centralize constants |
| Required Tool Detection | Lazy runtime errors / Pre-flight check | Pre-flight check | Fast fail | Redundant checks | Single guard function |
| Parallel Invocation Isolation | Random token / Env var only | Env var only | Simplicity | Hypothetical collision | Process isolation sufficient |
| Test Types | Integration only / Contract + Integration | Both | Faster failure localization | More scripts | Lean assertions |
| CI Order | Tests then PSSA / PSSA then tests | PSSA first | Fail faster cheaper | Over-reliance on static | Tests still run locally |

## Guard Mechanism Evaluation
Environment variable chosen for simplicity and zero dependency. Alternative (filesystem lock) unnecessary; no shared mutability beyond process boundaries. Exit code 2 reserved for clear semantic mapping.

## Static Analysis Rules
Baseline: PSScriptAnalyzer Recommended. Add style rules: PSUseConsistentIndentation, PSUseConsistentWhitespace, PSAlignAssignmentStatement. Defer additional rules until noise assessed. Suppress with `[Diagnostics.CodeAnalysis.SuppressMessage()]` only when rationale documented inline.

## Testing Strategy Justification
Contract tests: immediate feedback on guard, help, exit codes, verbosity. Integration tests: parity across OS via `make`. No unit tests initially—scripts are thin orchestrations; complexity does not justify. Future unit test insertion possible if logic extracted into helper functions.

## Help Experience
Unguarded: <=5 lines, includes phrase "Run via make" and an example `make build`. Guarded: full usage with parameters, exit codes summary. Ensures enforcement signal consistent (FR-003/FR-024) and discoverable (FR-025).

## Tool Presence Detection
One pre-flight function `Assert-RequiredTools` enumerates required modules (PSScriptAnalyzer, Pester for test harness if invoked in test mode). On missing tool: exit code 6, message: `Missing required tool: <name>. Install and retry.` Documented in quickstart + contracts.

## Exit Code Mapping Validation
Mapping chosen avoids 1 (commonly ambiguous) and keeps distinct contiguous small integers for CI branching. >6 delegated to unexpected errors to avoid infinite categorization expansion.

## Performance Considerations
PowerShell startup overhead minimal vs Bash on both OS given small script count. Avoid costly reflection or module imports; keep helper modules (Guard, Common) lightweight. Target median build orchestration < 1s excluding underlying AL compiler (out of this feature scope).

## Parallel Invocation
No global state; each `make` spawn sets var, runs child, unsets. Tests will spawn two concurrent builds (mock mode) to ensure no leakage / collision conditions.

## Risks & Mitigations
| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|-----------|
| Developer bypasses guard for debugging | Divergent behaviors | Medium | Document test harness invocation helpers |
| PSScriptAnalyzer false positives stall adoption | Slower dev | Medium | Start with recommended set, expand gradually |
| Windows make installation friction | Onboarding delay | Medium | Document install steps & pre-flight check |
| Overly strict help stub confuses new users | Support load | Low | Stub includes clear next step |

## Open Questions (Deferred)
- Should we add an optional `make help` target summarizing all guarded scripts? (Planned but not required for parity.)
- Should required tool versions be enforced (e.g., PSScriptAnalyzer min version) beyond presence? (Defer until mismatch issues observed.)

## Conclusion
All foundational design decisions selected with emphasis on simplicity, deterministic testing, and minimal surface area. Proceed to Phase 1 artifact generation.
