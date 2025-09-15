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
| Implementation Strategy | Greenfield new PS scripts / Relocate existing | Relocate existing | Lower risk, preserves proven logic, faster delivery | Hidden technical debt in old scripts | Add parity tests & incremental refactor |
| Required Tool Detection | Lazy runtime errors / Pre-flight check | Pre-flight check | Fast fail | Redundant checks | Single guard function |
| Parallel Invocation Isolation | Random token / Env var only | Env var only | Simplicity | Hypothetical collision | Process isolation sufficient |
| Test Types | Integration only / Contract + Integration | Both | Faster failure localization | More scripts | Lean assertions |
| CI Order | Tests then PSSA / PSSA then tests | PSSA first | Fail faster cheaper | Over-reliance on static | Tests still run locally |

## Guard Mechanism Evaluation
## Reuse vs Rewrite Justification
Existing Windows PowerShell scripts already encapsulate the core build, clean, configuration, and analyzer listing behaviors. Rewriting would:
- Introduce regression risk (logic drift during translation)
- Delay consolidation (duplicate testing effort)
- Inflate diff size reducing review clarity

Relocation with minimal targeted enhancement keeps:
- Smaller, auditable changes (path + guard + exit code additions)
- Proven functional semantics (validated via parity baselines)
- Focused refactors only where cross-platform path joins or verbosity inconsistencies exist

The current Windows script behaviors used for parity are captured in [inventory-windows-scripts.md](file:///d:/repos/al-build-tools/specs/003-powershell-only-build/inventory-windows-scripts.md).

Risk of inheriting suboptimal patterns is mitigated through:
- ScriptAnalyzer strict rules post-relocation
- Parity tests ensuring modifications are intentional
- Follow-up targeted refactors rather than wholesale rewrite
Environment variable chosen for simplicity and zero dependency. Alternative (filesystem lock) unnecessary; no shared mutability beyond process boundaries. Exit code 2 reserved for clear semantic mapping.

## Static Analysis Rules
Baseline: PSScriptAnalyzer Recommended. Add style rules: PSUseConsistentIndentation, PSUseConsistentWhitespace, PSAlignAssignmentStatement. Defer additional rules until noise assessed. Suppress with `[Diagnostics.CodeAnalysis.SuppressMessage()]` only when rationale documented inline.

## Testing Strategy Justification
Contract tests: immediate feedback on guard, help, exit codes, verbosity, executed within a temporary fixture AL project with the overlay copied in. Integration tests: parity across OS via `make` from the same fixture; build parity is conditional on AL compiler discovery and otherwise skipped with rationale. No unit tests initially—scripts are thin orchestrations; complexity does not justify. Future unit test insertion possible if logic is extracted into helper functions.

## Help Experience
Unguarded: <=5 lines, includes phrase "Run via make" and an example `make build`. Guarded: full usage with parameters, exit codes summary. Ensures enforcement signal consistent (FR-003/FR-024) and discoverable (FR-025).

## Tool Presence Detection
One pre-flight function `Assert-RequiredTools` enumerates required modules (PSScriptAnalyzer, Pester for test harness if invoked in test mode). On missing tool: exit code 6, message: `Missing required tool: <name>. Install and retry.` Documented in quickstart + contracts.

## Exit Code Mapping Validation
Mapping chosen avoids 1 (commonly ambiguous) and keeps distinct contiguous small integers for CI branching. >6 delegated to unexpected errors to avoid infinite categorization expansion.

## Compiler Discovery Rationale (C8)
Strategy: Enumerate AL extension install roots (VS Code extension directory), choose highest semantic version folder containing the compiler executable. Reject alternative strategies (hard-coded path, PATH search) due to brittleness and user-specific layouts. Highest-version selection guarantees deterministic upgrades without manual configuration. Absence is treated as a hard build error (clear remediation: install AL extension) because compilation cannot proceed meaningfully.

Edge Cases Considered:
- Multiple preview and stable versions → Choose numerically highest (preview suffix ignored for ordering; fallback lexical tie-break documented in test harness if needed).
- Permission issues → Surface native PowerShell error; do not mask with generic message.

## Analyzer Settings Parsing (C5, C6)
Source of truth: `.vscode/settings.json` keys:
- `al.enableCodeAnalysis` (boolean) – if false/absent treat as no analyzers.
- `al.codeAnalyzers` (array of string paths) – each path validated for existence before inclusion.

Design Choices:
- Missing or invalid JSON → return empty set (not failure) to keep build path resilient (ruleset and warnings-as-errors already cover quality gates).
- Non-existent DLL path → warn (optional) or silently skip; DO NOT stop build.

Rejected Option: Failing the build on any invalid analyzer path (too fragile for cross-developer environment differences).

## Variable Precedence (C2) Justification
Environment variables supplied by `make` define the authoritative runtime configuration because they are visible to both scripts and any nested tooling. In-script overrides risk divergence and complicate reproducibility. Therefore scripts only read (never mutate) `WARN_AS_ERROR`, `RULESET_PATH`, and future build toggles.

## Ruleset Handling (C3)
Optional quality augmentation—not a correctness dependency. Skipping silently with a warning prevents false negatives when developers lack the referenced file locally. Tests assert presence OR documented skip message; both outcomes considered compliant.

## Next Object Number Exit Code Reuse (C11)
Reuse of exit code 2 (already meaning guard violation elsewhere) for id range exhaustion intentionally keeps the mapping compact. Disambiguation achieved via message content pattern (`No available <Type> number`). Tests assert both exit code and message substring. Alternate mapping (dedicated code 7) rejected to avoid expanding the reserved numeric set.


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

## Baseline capture and normalization
- Fixture location: system temporary directory; overlay is copied into a fresh fixture per run.
- Snapshots are written under `tests/baselines/` inside the fixture. Nothing is added to this repository.
- Normalization rule: replace any absolute fixture root path with the token `<ROOT>` to stabilize diffs across machines and runs.
- Capture policy: always capture clean, show-config, and show-analyzers; capture build when a real AL compiler is discovered (present on this system). If absent, record `build.skipped.txt` with a one-line rationale instead of failing.
