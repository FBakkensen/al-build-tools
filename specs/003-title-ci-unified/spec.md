# Feature Specification: CI: Dual-framework test discovery (single Ubuntu runner)

**Feature Branch**: `003-title-ci-unified`
**Created**: 2025-09-13
**Status**: Draft
**Input**: User description (updated scope): "Reliability, simplicity, signal, future-proof; Add bats-core & Pester test discovery; remove legacy test_*.sh from CI pipeline; add guards for no tests; run both frameworks sequentially on a single ubuntu-latest runner (install pwsh + Pester); fail if zero tests; de-scope old shell test invocation; matrix removed to reduce CI time."

## Execution Flow (main)
```
1. Parse user description from Input
2. Extract key concepts: dual-framework discovery (Bats + Pester) on single runner, auto-discovery by convention, reliability guard (fail if zero tests per framework), removal of legacy shell test harness, future growth under tests/ tree, explicit trade-off (no native Windows filesystem semantics in CI).
3. Identify ambiguities → (none critical; see assumptions below)
4. Define user scenarios & acceptance tests
5. Generate functional requirements (testable, unambiguous)
6. No persistent data entities required (test files only)
7. Review checklist gating readiness
8. Output specification for planning phase
```

---

## ⚡ Quick Guidelines
- Focus on what the toolchain must enable for contributors and CI maintainers.
- Avoid low-level scripting implementation details (exact YAML lines, dependency installation mechanics). Those belong in design/plan, not the spec.
- Target audience: repository maintainers and contributors deciding on test strategy.

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a contributor adding or modifying scripts, I can place test files (`.bats` for bash-based tests, `.Tests.ps1` for PowerShell tests) anywhere under the `tests/` hierarchy and have them automatically executed in CI (single ubuntu-latest job running both frameworks) without editing workflow files—ensuring immediate feedback and preventing silent coverage gaps.

### Acceptance Scenarios
1. **Given** a new Bats test file `tests/contract/foo/new_feature.bats`, **When** CI runs on `ubuntu-latest`, **Then** the test is discovered and its result contributes to the job outcome.
2. **Given** a new Pester test file `tests/contract/windows/Bar.Tests.ps1`, **When** CI runs on `ubuntu-latest` (with pwsh + Pester installed), **Then** the test is discovered and its result contributes to the job outcome.
3. **Given** at least one test of each framework type exists, **When** the CI job runs, **Then** the job passes only if all Bats and all Pester tests pass.
4. **Given** there are zero `.bats` test files, **When** CI runs, **Then** it fails with the message "No Bats tests (*.bats) found under tests/.".
5. **Given** there are zero `.Tests.ps1` test files, **When** CI runs, **Then** it fails with the message "No Pester tests (*.Tests.ps1) found under tests/.".
6. **Given** legacy `test_*.sh` shell scripts still exist temporarily during migration, **When** CI runs, **Then** those scripts are NOT executed once the new workflow is active.
7. **Given** a contributor adds both a Bats and a Pester test for analogous behavior, **When** CI runs, **Then** both are executed; naming/location parity not required.
8. **Given** a failing test in one framework (Bats or Pester), **When** the other framework’s tests complete, **Then** the single CI job exits non-zero summarizing both results.
9. **Given** a test relies on Windows-only filesystem semantics, **When** it runs on Ubuntu, **Then** any discrepancy is documented as a limitation (not enforced) pending possible future Windows runner reintroduction.

### Edge Cases
- All tests skipped or containing only comments → counts as zero discovered and triggers guard failure.
- Misnamed files (`*.bats.txt` or `SomethingTest.ps1` without `.Tests.ps1`) → not discovered; documentation will clarify naming rules.
- Extremely large number of test files → executed sequentially; sharding future enhancement.
- Mixed CRLF/LF line endings inside test files → should not affect discovery; test frameworks handle.
- Windows-specific path / case-insensitivity differences are NOT validated (explicit trade-off of single-runner approach).

## Requirements *(mandatory)*

### Functional Requirements
// Updated for single-job dual-framework execution.
- **FR-001**: System MUST automatically discover and run all test files ending in `.bats` recursively under `tests/` on the ubuntu-latest CI job.
- **FR-002**: System MUST automatically discover and run all test files ending in `.Tests.ps1` recursively under `tests/` on the same ubuntu-latest CI job using PowerShell 7 + Pester v5+.
- **FR-003**: CI MUST fail the job if zero `.bats` tests are discovered (explicit guard message).
- **FR-004**: CI MUST fail the job if zero `.Tests.ps1` tests are discovered (explicit guard message).
- **FR-005**: CI MUST execute both frameworks sequentially in a single job (no OS matrix) and surface independent summaries.
- **FR-006**: Legacy execution of `test_*.sh` scripts MUST be removed from CI workflow once dual-framework adoption is in place.
- **FR-007**: Contributors MUST NOT be required to modify workflow YAML to add new tests; placing correctly named files is sufficient.
- **FR-008**: System MUST surface per-test pass/fail output in CI logs for both frameworks (human-readable summary).
- **FR-009**: System SHOULD allow grouping tests under subdirectories (`contract`, `integration`, etc.) without additional configuration.
- **FR-010**: Documentation MUST define naming conventions for test discovery and single-runner trade-offs.
- **FR-011**: System MUST maintain existing repository security posture (no network calls added during test execution beyond current behavior, aside from framework installs).
- **FR-012**: Migration MUST preserve current behavioral coverage (no tests lost; legacy ones should be ported or explicitly retired with rationale tracked in PR).
- **FR-013**: System MUST produce a non-zero exit code for any failing test causing CI job failure.
- **FR-014**: System MUST clearly differentiate "zero tests" failure from "tests failed" in log messaging.
- **FR-015**: Test discovery MUST be case-sensitive according to Linux filesystem semantics.
- **FR-016**: CI MUST install (or ensure presence of) PowerShell 7 and Pester before executing `.Tests.ps1` tests if not preinstalled.
- **FR-017**: Documentation MUST explicitly call out the limitation of not executing on a native Windows runner.

### Key Entities
(No persistent business/data entities; test files are filesystem artifacts only.)

---

## Review & Acceptance Checklist

### Content Quality
- [ ] No implementation details (languages, frameworks, APIs) beyond high-level WHAT/WHY
- [ ] Focused on user value (contributor simplicity, reliability) and governance (prevent false greens)
- [ ] Written for stakeholders deciding on test strategy
- [ ] All mandatory sections completed

### Requirement Completeness
- [ ] No [NEEDS CLARIFICATION] markers remain (assumptions below are acceptable for scope)
- [ ] Requirements are testable and unambiguous
- [ ] Success criteria are measurable (guards, dual-framework execution, discovery behavior)
- [ ] Scope is clearly bounded (no sharding, no performance optimization yet)
- [ ] Dependencies and assumptions identified

---

## Execution Status
- [ ] User description parsed
- [ ] Key concepts extracted
- [ ] Ambiguities marked (none critical)
- [ ] User scenarios defined
- [ ] Requirements generated
- [ ] Entities identified
- [ ] Review checklist passed

---

## Assumptions & Dependencies (Supporting, Non-mandatory Section)
- Bats-core available via package manager or GitHub release (installation approach decided during planning, not specified here).
- Pester v5+ available in GitHub-hosted Windows runners by default (verify version during planning; if not, install minimal dependency).
- Existing `tests/contract` and `tests/integration` shell scripts will be migrated to new naming patterns or retained temporarily until removed in the same PR with rationale.
- No need for macOS runner currently (can be added later by extending matrix; out of current scope).

## Out of Scope
- Test result artifact uploads (JUnit XML conversion) for this iteration.
- Sharded or parallelized test splitting beyond framework defaults.
- Code coverage tooling integration.
- Automatic migration tooling for legacy `test_*.sh` scripts (manual porting expected).

## Success Metrics
- First CI run after merge shows both matrix legs executing new frameworks.
- Attempted run with all `.bats` files temporarily renamed triggers guard failure (validated in PR checks).
- Median added test onboarding time reduced (qualitative; contributor simply adds file with correct extension).

## Risk & Mitigations
- Risk: Forgetting to port an existing `test_*.sh` leads to silent coverage loss. Mitigation: Temporary checklist in PR description enumerating legacy scripts migrated or retired; FR-003/004 ensure at least some tests exist.
- Risk: Pester or Bats installation flakiness. Mitigation: Pin minimal known-good versions in workflow setup (planning phase detail, not spec-level requirement beyond availability assumption).
- Risk: Contributor misnames file and expects execution. Mitigation: Document naming; optional pre-commit lint (future enhancement, not required now).
- Risk: Increased CI time (both frameworks sequential). Mitigation: Optimize install steps; cache module if needed.
- Risk: Undetected Windows-specific path/case issues. Mitigation: Document limitation (FR-017); reintroduce Windows runner if such issues surface.

## Open Questions
(No blocking ambiguities identified; proceeding to planning.)
