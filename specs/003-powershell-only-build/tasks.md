# Tasks: PowerShell-Only Build Script Consolidation (Relocation & Reuse)

**Feature Directory**: `D:/repos/al-build-tools/specs/003-powershell-only-build/`
**Source Docs**: `plan.md`, `spec.md`, `data-model.md`, `contracts/README.md`, `research.md`, `quickstart.md`
**Generation Date**: 2025-09-14

## Execution Flow (main)
```
1. Load plan.md (tech stack: PowerShell 7.2+, single overlay layout) ✅
2. Load optional docs (entities, contracts, research decisions, quickstart scenarios) ✅
3. Derive tasks (Setup → Tests → Core → Integration → Polish) ✅
4. Apply rules: Tests before implementation; different files => [P]; same file or dependency => no [P] ✅
5. Number tasks T001+ ✅
6. Define dependencies + parallel guidance ✅
7. Validate coverage: All FR-001..FR-025 mapped; all entities & contracts represented ✅
8. Ready for execution ✅
```

## Legend
- Format: `T### [P?] Description (File Path) — Acceptance / Notes`
- `[P]` = May run in parallel (no file overlap & no unmet dependency)
- Omit `[P]` when sequential dependency or same file
- All paths absolute or project-relative (root = repo root)
- Reference FR IDs, Contract Test IDs where applicable

## Sequencing Note (Updated)
- Next task: T015 Makefile minimal update (Windows-only; point to overlay/scripts/make/*.ps1).
- Then add tests for current scripts: T017–T024 (contract) and T013 (parity), T014 (integration scaffolds as needed).
- Then add new features in a test-driven way: T007–T011.

## Phase 1: Relocation & Baseline Capture
- [x] T001 Inventory current Windows PowerShell scripts & helpers — FR-001
	- DoD: List parameters, current behaviors, exit codes (implicit) for build/clean/show-*; identify helper functions in `lib/`.
	- Validation: Document stored in planning notes (not shipped) summarizing each script.
	- Deliverable: See inventory note at [inventory-windows-scripts.md](file:///d:/repos/al-build-tools/specs/003-powershell-only-build/inventory-windows-scripts.md)
- [x] T002 Capture baseline outputs (Windows) for build, clean, show-config, show-analyzers — FR-025
	- DoD: From inside a temporary fixture AL project with the overlay copied in, run each script via existing path (or via the current Makefile) and store normalized output snapshots under `tests/baselines/` (internal only). Capture clean, show-config, and show-analyzers always; capture build only when a real AL compiler is discovered, otherwise mark baseline as skipped with rationale.
	- Validation: Files exist; normalization documented; build baseline captured (compiler present).
- [x] T003 Relocate scripts: move `windows/*.ps1` to `overlay/scripts/make/` root — FR-001, FR-016
	- DoD: Files appear at new location; old `windows/` folder temporarily retained until parity tests added OR deleted if Makefile updated same commit.
	- Validation: `Test-Path` new paths true; old references removed from docs.

- [x] T005 Remove `windows/lib` and (after parity tests pass) delete `windows/` directory — FR-016
	- DoD: Completed — `overlay/scripts/make/windows/` removed from repo; no references in docs or Makefile.
	- Validation: Paths absent; docs updated.
- [x] T006 Delete all Bash scripts under `linux/` directory — FR-016
	- DoD: Completed — `overlay/scripts/make/linux/` removed completely.
	- Validation: No lingering references in docs; Makefile no longer branches on OS.

## Phase 2: Makefile Minimal Update (Windows-only)
- [x] T015 Update `Makefile` to call relocated scripts (Windows-only, minimal) — FR-016
	- Priority: Execute this task next to align with current script locations.
	- DoD: All targets use `pwsh -File overlay/scripts/make/<script>.ps1`; remove Bash logic branches; Windows-only (no OS conditional).
	- Validation: Local invocation succeeds on Windows.


## Phase 3: Test Suite (Contract & Integration)
- [x] T012 Create baseline contract tests for current behavior (no guard/verbosity/exit-code-mapping/requires-version yet) — FR-010, FR-025
	- DoD: Test files under `tests/contract/` asserting existing observable behavior only.
	- Validation: Initial run passes on current scripts; serves as safety net before enhancements.
- [ ] T014 Create integration tests (build, clean idempotent, config, analyzers, env isolation, parity across OS) — FR-011, FR-013
	- DoD: Tests under `tests/integration/` calling make targets only; use fixture projects with the overlay copied in; no network calls.
	- Validation: Windows + Ubuntu matrix passes after implementation; environment-dependent assertions are conditional (compiler/analyzers may be absent).
	- Subtasks:
		- T014.1 [x] Integration helpers module: `tests/integration/_helpers.ps1`
			- Provides `New-Fixture`, `Install-Overlay`, `Write-AppJson`, optional `Write-SettingsJson`, `Invoke-Make`, and `_Normalize-Output` (CRLF/LF and trailing space normalization).
		- T014.2 [x] Fixture generators
			- Minimal `app.json` compatible with [`Get-OutputPath`](file:///d:/repos/al-build-tools/overlay/scripts/make/lib/common.ps1#L23-L41) and optional `.vscode/settings.json` variants.
		- T014.3 [x] Build integration (compiler detection covered)
			- `tests/integration/Build.Tests.ps1`: If [`Get-ALCompilerPath`](file:///d:/repos/al-build-tools/overlay/scripts/make/lib/common.ps1#L91-L99) returns $null, assert `make build` exits non‑zero with "AL Compiler not found" from [`build.ps1`](file:///d:/repos/al-build-tools/overlay/scripts/make/build.ps1#L17-L20); else assert exit 0 and "Build completed successfully: ...".
		- T014.4 [x] Clean idempotence
			- `tests/integration/CleanIdempotence.Tests.ps1`: Pre‑seed fake `.app` at [`Get-OutputPath`](file:///d:/repos/al-build-tools/overlay/scripts/make/lib/common.ps1#L23-L41); run `make clean` twice; both exit 0; second run prints "No build artifact found" per [`clean.ps1`](file:///d:/repos/al-build-tools/overlay/scripts/make/clean.ps1#L7-L15).
		- T014.5 [x] Show-config
			- `tests/integration/ShowConfig.Tests.ps1`: With valid `app.json`, assert headers/keys printed by [`show-config.ps1`](file:///d:/repos/al-build-tools/overlay/scripts/make/show-config.ps1#L7-L13,L17-L27); with missing `app.json`, assert exit 0 and error on stderr.
		- T014.6 [P] Show-analyzers (analyzer detection covered)
			- `tests/integration/ShowAnalyzers.Tests.ps1`: No settings → header plus "(none)"; with workspace‑local fake DLL via `${workspaceFolder}`/`${appDir}` token and wildcard, assert it appears under "Analyzer DLL paths:" without requiring AL extension.
		- T014.7 [P] Environment isolation (skeleton)
			- `tests/integration/EnvIsolation.Tests.ps1`: Assert no persistent env leakage before/after `make` invocations; placeholder for future `ALBT_VIA_MAKE` guard once added.
		- T014.8 [P] Output normalization utility
			- Implement `_Normalize-Output` in helpers; reused by parity assertions.
		- T014.9 [P] Parity snapshot (scaffold)
			- `tests/integration/Parity.Tests.ps1`: Collect normalized outputs from `show-config`, `show-analyzers`, and conditionally `build/clean`; compare content‑level parity, not raw formatting, to support cross‑OS.
		- T014.10 [P] Make-level invocation contract
			- Ensure all tests call `make <target>` (exercise [`overlay/Makefile`](file:///d:/repos/al-build-tools/overlay/Makefile#L51-L65)) rather than scripts directly.

## Phase 4: Enhancements & Standardization
- [ ] T007 Add guard (`ALBT_VIA_MAKE`) to each relocated script — FR-002..FR-004 (C1,C9)
	- Precede with tests: Create `tests/contract/Guard.Tests.ps1` that expects exit 2 and guidance on direct invocation; initially FAILS until implementation.
	- DoD: Direct invocation exits 2 with guidance; via make proceeds.
	- Validation: Guard tests pass post-implementation.
- [ ] T008 Add standardized exit code comment & mapping usage — FR-024
	- Precede with tests: Extend contract tests to assert documented exit codes (e.g., analysis=3, contract=4, integration=5, missing tool=6); initially FAIL until mapping implemented.
	- DoD: Comment block present; code paths updated to use mapping.
	- Validation: Exit code tests pass.
- [ ] T009 Add verbosity env handling (VERBOSE=1) + ensure `-Verbose` still works — FR-006
	- Precede with tests: Create `tests/contract/Verbosity.Tests.ps1` to assert additional verbose output under env flag and flag pass-through; initially FAIL until implemented.
	- DoD: `$VerbosePreference='Continue'` set when env var truthy.
	- Validation: Verbosity tests pass.
- [ ] T010 Normalize config output ordering & keys — FR-011, FR-025
	- Precede with tests: Add `tests/contract/ShowConfig.Tests.ps1` asserting stable key=value ordering; initially FAIL until implemented.
	- DoD: `show-config.ps1` emits deterministic ordered key=value lines (incl. Platform, PowerShellVersion).
	- Validation: Two consecutive runs identical; tests pass.
- [ ] T011 Ensure `next-object-number.ps1` has version directive & help stub — FR-005, FR-014
	- Precede with tests: Add `tests/contract/RequiresVersion.Tests.ps1` to assert `#requires -Version 7.2`; initially FAIL where missing.
	- DoD: `#requires -Version 7.2` at top if missing; concise help.
	- Validation: Presence of directive + help displays; tests pass.

## Phase 5: CI Updates
- [ ] T016 Add/Update GitHub Actions workflow for PSSA then Pester matrix — FR-008, FR-009
	- DoD: YAML present with analysis job (exit 3 mapping) & contract/integration jobs.
	- Validation: Workflow syntax valid.
- [ ] T017 Add required tools check (exit 6 on missing PSScriptAnalyzer/Pester) — FR-023
	- DoD: Pre-step in workflow or shared script ensures presence.
	- Validation: Simulated removal triggers exit 6.

## Phase 6: Documentation & Cleanup
- [ ] T018 Update spec, plan, quickstart (done in feature branch) — FR-015 (Meta)
	- DoD: Docs contain relocation narrative; no references to linux/windows subfolders.
	- Validation: Grep returns zero hits for `/make/linux` or `/make/windows` paths.
- [ ] T019 Update `contracts/README.md` with parity note & removal statement — FR-016, FR-025
	- DoD: Contracts mention that parity tests enforce FR-025.
	- Validation: Document updated.
- [ ] T020 Update `data-model.md` entities to include RelocatedScript & DeprecatedScript — FR-025
	- DoD: New entity rows added.
	- Validation: Data model regenerated.
- [ ] T021 Update `research.md` with reuse rationale vs rewrite — FR-025
	- DoD: Added matrix row & justification.
	- Validation: Section present.
- [ ] T022 Create migration note / CHANGELOG entry — FR-015, FR-016
	- DoD: Explains removal of Bash scripts and unchanged make targets.
	- Validation: Entry present in repo.
- [ ] T023 Final static analysis run & clean-up unused helper remnants — FR-017
	- DoD: No PSSA warnings of configured severities.
	- Validation: Analyzer run returns 0 issues.

## Phase 7: Optional Inlining (post-tests)
- [ ] T004 Inline required helper logic from `overlay/scripts/make/lib/*.ps1` into each relocated script — FR-001
	- Blocker: Execute only after contract (T012) and parity (T013) tests exist and are passing for current behavior.
	- DoD: No remaining dependency on `overlay/scripts/make/lib`; only necessary functions copied; duplication < threshold (leave as-is if small).
	- Validation: Scripts run without dot-sourcing external helper files; parity remains green.

## Removed / Replaced Tasks
Original scaffold tasks (T009–T012 etc.) superseded by relocation steps (T003–T011). Any references in older planning artifacts are historical only and not to be executed.

## Traceability (Updated High-Level)
| FR | Representative Tasks |
|----|----------------------|
| FR-001 | T001,T003,T004,T005 |
| FR-002..FR-004 | T007,T012 |
| FR-005 | T011 |
| FR-006 | T009 |
| FR-007 | (inherent, verified in tests) |
| FR-008 | T016 |
| FR-009 | T016,T014 |
| FR-010 | T012 |
| FR-011 | T010,T014 |
| FR-012 | T014 |
| FR-013 | T014 |
| FR-014 | T011,T012 |
| FR-015 | T018,T022 |
| FR-016 | T005,T006,T015,T018,T022 |
| FR-017 | T016,T023 |
| FR-018 | T016 (artifact stage) |
| FR-019 | (no new tasks; enforced by review) |
| FR-020 | T016 (no bypass path) |
| FR-021 | T011,T012 (directive presence) |
| FR-022 | T014 (parity OS), T015 |
| FR-023 | T017 |
| FR-024 | T008,T012 |
| FR-025 | T002,T013,T019,T020 |

## Parallel Execution Guidance (Adjusted)
Early parallelizable tasks: T001,T002 (inventory + baselines) must precede relocation (T003). After relocation but before deletion, parity tests (T013) should be added to catch regressions prior to removing `windows/` folder.

## Coverage Checklist (Updated)
- [ ] FR-025 parity snapshots created before relocation (T002)
- [ ] Guard contract validated post‑relocation (T007,T012)
- [ ] Bash scripts deleted (T006) only after passing parity tests (T013)
- [ ] Documentation references cleaned (T018,T022)
- [ ] Data model & contracts updated (T019,T020)

---
All prior greenfield creation tasks are deprecated in favor of this relocation-first approach.

## Phase 2: Tests First (Contract & Integration Skeletons) — MUST precede Core
Contract tests (each file independent → [P]) map contracts C1–C14.
- [ ] T017 [P] Create contract test `tests/contract/Guard.Tests.ps1` (GUARD-DIRECT, GUARD-HELP, GUARD-PASS) — FR-002..FR-004, FR-025 (C1,C9)
	- DoD: Test file with three contexts covering direct invocation, help invocation, and via-make success.
	- Validation: `Invoke-Pester tests/contract/Guard.Tests.ps1` enumerates contexts; passes post core implementation.
- [ ] T018 [P] Create contract test `tests/contract/Help.Tests.ps1` (HELP-FLAGS, HELP-CONTENT, HELP-EXIT) — FR-004, FR-015, FR-025 (C1,C9)
	- DoD: Verifies help flags produce guard block (if unguarded) or content when allowed; checks exit code.
	- Validation: Pester shows all described It blocks; green after implementation.
- [ ] T019 [P] Create contract test `tests/contract/Verbosity.Tests.ps1` (VERBOSE-ENV, VERBOSE-FLAG, VERBOSE-DEFAULT) — FR-006 (C2)
	- DoD: Three test cases assert additional verbose output present/absent appropriately.
	- Validation: Verbose scenarios capture expected Write-Verbose lines count ≥1; default count 0.
- [ ] T020 [P] Create contract test `tests/contract/StaticAnalysis.Tests.ps1` (PSSA-FAIL, PSSA-PASS, PSSA-BYPASS) — FR-008, FR-017, FR-020
	- DoD: Contains scenarios for induced violation, clean file, and refusal to bypass gate.
	- Validation: Induced violation triggers expected non-zero code (3) in controlled harness; clean run 0.
- [ ] T021 [P] Create contract test `tests/contract/RequiredTools.Tests.ps1` (TOOL-PSSA, TOOL-PESTER) — FR-023 (C9)
	- DoD: Mocks or isolates module path to simulate missing tools; asserts exit 6.
	- Validation: Temporary module path override reproduces exit 6 with tool names listed.
- [ ] T022 [P] Create contract test `tests/contract/ExitCodes.Tests.ps1` (EXIT-0..EXIT-6, EXIT-UNEXPECTED) — FR-024 (C9,C11 reuse semantics)
	- DoD: Verifies each mapped scenario returns documented code; includes synthetic unexpected error test.
	- Validation: All asserted exit codes match mapping table; Pester green.
- [ ] T023 [P] Create contract test `tests/contract/Utility.Tests.ps1` (UTIL-NOGUARD, UTIL-HELP, UTIL-ARGS) — FR-005 (C11)
	- DoD: Covers unguarded tool direct invocation and help output; arg handling minimal.
	- Validation: Running test yields all passes with no guard enforcement failure.
- [ ] T024 [P] Create contract test `tests/contract/RequiresVersion.Tests.ps1` (presence of `#requires -Version 7.2` in all scripts) — FR-014, FR-021 (C9 implicit safety)
	- DoD: Enumerates target scripts and asserts first non-comment line matches directive.
	- Validation: Fails if any script missing directive; passes when all have it.

Integration tests (run inside a temporary fixture AL project with the overlay copied in; invoke via make; skeletons assert expected behaviors; each file independent → [P]).
- [ ] T025 [P] Create integration test `tests/integration/BuildParity.Tests.ps1` (INT-BUILD, cross-platform placeholder) — FR-001, FR-011 (C1,C10,C13)
	- DoD: Invokes `make build` capturing output; asserts 0 exit and presence of expected build markers.
	- Validation: Both OS CI logs show identical (normalized) essential lines.
- [ ] T026 [P] Create integration test `tests/integration/CleanIdempotence.Tests.ps1` (INT-CLEAN) — FR-001 (C1,C10)
	- DoD: Runs clean twice and asserts both exit codes 0; optional artifact existence check between runs.
	- Validation: Pester test green; no residual error output.
- [ ] T027 [P] Create integration test `tests/integration/ShowConfig.Tests.ps1` (INT-CONFIG, INT-PARITY partial) — FR-011, FR-022 (C7,C13)
	- DoD: Captures config output; asserts required keys present and format stable.
	- Validation: Cross-run diff identical; newline normalization only difference across OS.
- [ ] T028 [P] Create integration test `tests/integration/ShowAnalyzers.Tests.ps1` (INT-ANALYZERS) — FR-011 (C5,C6)
	- DoD: Asserts analyzer listing script exits 0 and outputs either list or 'None found'.
	- Validation: Test passes when no analyzers installed and when one installed (mock case).
- [ ] T029 [P] Create integration test `tests/integration/EnvIsolation.Tests.ps1` (INT-ENV-ISO) — FR-013 (C2,C14)
	- DoD: Verifies ALBT_VIA_MAKE not present before/after; present only during invocation (captured via wrapper logging).
	- Validation: Test passes demonstrating absence outside execution scope.
- [ ] T030 [P] Create integration test `tests/integration/Parity.Tests.ps1` (INT-PARITY final normalization) — FR-009, FR-016, FR-022 (C13)
	- DoD: Aggregates outputs from prior targets, normalizes line endings/whitespace, asserts equivalence across OS snapshots.
	- Validation: CI artifacts comparison yields no diff.

## Phase 3: Core Implementation (After tests exist & initially fail)
- [ ] T031 Implement guarded `build.ps1` behavior (inline guard, inline verbosity, exit code comments) — FR-001..FR-004, FR-006 (C1,C2,C3,C4,C5,C6,C8,C9,C10,C12,C13,C14)
	- DoD: Build script performs real build steps; returns 0 on success; structured logging present.
	- Validation: Contract + integration build tests green; analyzer clean.
- [ ] T032 Implement guarded `clean.ps1` behavior (artifact removal placeholder) — FR-001..FR-004
	- DoD: Removes artifacts deterministically; safe when artifacts absent.
	- Validation: Idempotence test passes; no errors on missing paths.
- [ ] T033 Implement guarded `show-config.ps1` (inline guard; emit normalized key/value lines) — FR-011, FR-016 (C7,C13)
	- DoD: Outputs stable ordered list including required keys and any extended keys per FR-049.
	- Validation: Parity tests confirm consistent ordering/content.
- [ ] T034 Implement guarded `show-analyzers.ps1` (list installed analyzers or 'None found') — FR-011 (C5,C6)
	- DoD: Handles no analyzers gracefully; optionally supports `--json` extension (if added later) behind tests.
	- Validation: Integration analyzer test green.
- [ ] T035 Update `next-object-number.ps1` help/verbosity alignment (ensure no guard) — FR-005, FR-006 (C11,C12)
	- DoD: Script prints usage with -h, supports -Verbose, retains existing behavior.
	- Validation: Utility contract tests pass; direct run unaffected by guard.

Make & CI integration:
- [ ] T041 Finalize `Makefile` recipes (scoped env, pass VERBOSE env through) — FR-006, FR-013 (C1,C2,C9)
	- DoD: All targets invoke PowerShell scripts uniformly; VERBOSE env forwarded; no persistent env leakage.
	- Validation: Running targets sequentially shows no ALBT_VIA_MAKE persistence; verbose toggle works.
- [ ] T042 Implement GitHub Actions workflow stages: analysis → contract → integration → artifact publish — FR-009, FR-018
	- DoD: Workflow executes ordered jobs with dependencies; artifacts uploaded.
	- Validation: Successful CI run shows all jobs green; artifacts present in run summary.
- [ ] T043 Add test result artifact publishing (Pester NUnit XML) — FR-018
	- DoD: Contract + integration test outputs stored as artifacts; naming includes job + timestamp or commit.
	- Validation: Artifact download contains XML with test suite entries.

## Phase 4: Integration & Hardening
- [ ] T044 Implement cross-platform output normalization (line endings, whitespace) within tests or helper for parity checks — FR-016, FR-022 (C13)
	- DoD: Normalization function/module used by parity tests; handles CRLF/LF and trailing spaces.
	- Validation: Parity tests pass even when raw outputs differ only by line endings.
- [ ] T045 Add parallel invocation test harness (spawn two `make build` concurrently) augmenting EnvIsolation test — FR-013 (C2,C14)
	- DoD: Harness launches concurrent builds; no cross-talk or race failures.
	- Validation: Test passes multiple consecutive runs without flakiness.
- [ ] T046 Add missing-tool simulation harness (temporarily shadow modules path) to strengthen TOOL-* tests — FR-023
	- DoD: Reusable function to remove modules from resolution path within test scope.
	- Validation: RequiredTools tests use harness and reliably produce exit 6.
- [ ] T047 Add failure-path test for static analysis injected violation (ensures exit 3) — FR-017
	- DoD: Test creates temp script with deliberate analyzer violation; asserts analyzer job fails with code 3.
	- Validation: Analyzer pass/fail toggled by editing violation presence.
- [ ] T048 Add unsupported platform / missing GNU make detection logic (error message path) — FR-022 (C13)
	- DoD: Detection script or inline logic identifies absence and exits non-zero with clear message.
	- Validation: Simulated environment (rename make binary) triggers expected failure.
- [ ] T049 Expand `show-config.ps1` to include `PowerShellVersion`, `Platform`, `ScriptRoot`, `AnalyzerRuleset` — FR-011, FR-016
	- DoD: Additional keys emitted in stable order; documented in README/quickstart.
	- Validation: Show-config integration test updated and passes with new keys.

## Phase 5: Polish & Documentation
- [ ] T050 Update `quickstart.md` with final help syntax & verbose examples — FR-015
	- DoD: Quickstart includes copy/paste examples for each script via make, verbose example, exit codes table reference.
	- Validation: Manual review; links and examples execute successfully in local test.
- [ ] T051 Update repository `README.md` (PowerShell-only, guard policy, exit codes) — FR-015, FR-024
	- DoD: README sections present for Guard Policy, Exit Codes, PowerShell 7.2 requirement.
	- Validation: Grep README for 'Exit Codes' and 'ALBT_VIA_MAKE' returns hits.
- [ ] T052 Add `docs/guard-policy.md` summarizing rationale & usage (optional) — FR-002..FR-004
	- DoD: New doc created with rationale, usage examples, troubleshooting; linked from README.
	- Validation: Link resolves; doc lint passes (optional markdown lint).
- [ ] T054 Generate PSScriptAnalyzer report artifact in CI (upload) — FR-018
	- DoD: CI uploads analyzer results (JSON or SARIF) as artifact.
	- Validation: Artifact contains rule result entries; zero critical severities on pass.
- [ ] T055 Create follow-up issue template for Bash script removal (post-parity release) — FR-016
	- DoD: `.github/ISSUE_TEMPLATE/remove-bash.yml` created outlining validation checklist.
	- Validation: GitHub UI shows new template option.
- [ ] T056 Draft migration note (CHANGELOG / MIGRATION.md) for consumers — FR-016, FR-015
	- DoD: MIGRATION or CHANGELOG entry with steps, deprecated paths, cutover guidance.
	- Validation: Mentions guard, PS version, new commands; peer review sign-off.
- [ ] T057 Remove any unused placeholder code & ensure zero PSSA warnings — FR-017
	- DoD: All placeholder comments replaced or deleted; `Invoke-ScriptAnalyzer` returns 0 findings of configured severities.
	- Validation: Analyzer run clean across overlay + internal scripts.
- [ ] T058 Final audit: verify no network calls in scripts/tests — FR-007, FR-019
	- DoD: Grep shows no Invoke-RestMethod/WebRequest; any required tooling checks purely local.
	- Validation: Automated grep pipeline returns empty; manual confirmation.
- [ ] T059 Final traceability matrix update in `contracts/README.md` if new tests added — Change Control
	- DoD: Matrix reflects actual final test files & FR mappings.
	- Validation: Cross-check each FR present at least once.
- [ ] T060 Close planning by marking tasks executed & archive plan (link in README) — Housekeeping
	- DoD: Tasks marked done, reference link added to README or docs index.
	- Validation: README contains archive link; no open tasks remain except deferred ones.

## Dependencies Summary
- Setup (T001–T016) precedes all tests & implementation.
- Contract & integration test skeletons (T017–T030) must exist before modules / entrypoints are fully implemented (T031+), allowing red → green TDD.
- Modules (T031–T035) precede entrypoints (T036–T040).
- Makefile & CI (T041–T043) require entrypoints & tests present.
- Hardening tasks (T044–T049) rely on working core + baseline tests.
- Polish (T050–T060) after all functional compliance.

## Parallel Execution Guidance
Example 1 (Early Contract Tests):
```
Run in parallel: T017 T018 T019 T020 T021 T022 T023 T024
Command pattern:
pwsh -NoLogo -Command "Invoke-Pester -Path tests/contract/Guard.Tests.ps1 -CI"  # repeat per file or use -PassThru for grouping
```

Example 2 (Integration Skeletons):
```
Run in parallel: T025 T026 T027 T028 T029 T030
pwsh -NoLogo -Command "Invoke-Pester -Path tests/integration/BuildParity.Tests.ps1 -CI"
```

Example 3 (Inline Implementation):
```
Run in parallel: T036 T037 T038 T039 (distinct scripts; all use inline patterns)
```

## Coverage Validation Checklist
- [ ] All FR-001..FR-025 mapped to at least one task
- [ ] Each conceptual entity has an implementation or test task
- [ ] Each contract category has a contract test file task
- [ ] Guard & help behavior tested before implementation
- [ ] Exit codes verified before relying on them in CI
- [ ] Parallel tasks only touch distinct files
- [ ] Environment variable scope tested (INT-ENV-ISO / T029, T045)
- [ ] Required tools absence simulated (T046)
- [ ] Static analysis failure path enforced (T047)

## Traceability (High-Level)
| FR Range | Representative Tasks |
|----------|----------------------|
| FR-001 | T001, T009–T012, T031–T034 |
| FR-002–FR-004 | T004, T031–T034, T017–T018 |
| FR-005 | T013, T023, T035 |
| FR-006 | T005, T031, T041 |
| FR-007 | T058 |
| FR-008 | T002, T007, T020, T042 |
| FR-009 | T014, T042, T030 |
| FR-010 | T017–T024 contract suite |
| FR-011 | T011–T012, T025–T030, T033–T034 |
| FR-012 | T025–T030 (hermetic design), T044 |
| FR-013 | T008, T029, T045 |
| FR-014 | T009–T013, T024 |
| FR-015 | T016, T050–T051, T056 |
| FR-016 | T025–T030, T055 |
| FR-017 | T002, T007, T020, T047, T057 |
| FR-018 | T042–T043, T054 |
| FR-019 | T058 |
| FR-020 | T020, T047 |
| FR-021 | T024 (presence check) |
| FR-022 | T008, T027, T030, T048 |
| FR-023 | T006, T021, T046 |
| FR-024 | T003, T022 |
| FR-025 | T017–T018 |

---
All tasks are atomic and executable by an agent with repository context. Adjust numbering ONLY by appending new IDs (do not renumber) once execution begins.

