# Feature Specification: Automated Static Analysis Quality Gate on Pull Requests

**Feature Branch**: `001-static-analysis-on`
**Created**: 2025-09-10
**Status**: Draft
**Input**: User description: "Static analysis on every PR to improve code quality; first step toward later integration tests (out of scope)."

## Execution Flow (main)
```
1. Parse user description from Input
   → If empty: ERROR "No feature description provided"
2. Extract key concepts from description
   → Identify: actors, actions, data, constraints
3. For each unclear aspect:
   → Mark with [NEEDS CLARIFICATION: specific question]
4. Fill User Scenarios & Testing section
   → If no clear user flow: ERROR "Cannot determine user scenarios"
5. Generate Functional Requirements
   → Each requirement must be testable
   → Mark ambiguous requirements
6. Identify Key Entities (if data involved)
7. Run Review Checklist
   → If any [NEEDS CLARIFICATION]: WARN "Spec has uncertainties"
   → If implementation details found: ERROR "Remove tech details"
8. Return: SUCCESS (spec ready for planning)
```

---

## ⚡ Quick Guidelines
- ✅ Focus on WHAT users need and WHY
- ❌ Avoid HOW to implement (no tech stack, APIs, code structure)
- 👥 Written for business stakeholders, not developers

### Section Requirements
- **Mandatory sections**: Must be completed for every feature
- **Optional sections**: Include only when relevant to the feature
- When a section doesn't apply, remove it entirely (don't leave as "N/A")

### For AI Generation
When creating this spec from a user prompt:
1. **Mark all ambiguities**: Use [NEEDS CLARIFICATION: specific question] for any assumption you'd need to make
2. **Don't guess**: If the prompt doesn't specify something (e.g., "login system" without auth method), mark it
3. **Think like a tester**: Every vague requirement should fail the "testable and unambiguous" checklist item
4. **Common underspecified areas**:
   - User types and permissions
   - Data retention/deletion policies
   - Performance targets and scale
   - Error handling behaviors
   - Integration requirements
   - Security/compliance needs

---

## User Scenarios & Testing *(mandatory)*

### Primary User Story
As a maintainer, when a contributor opens or updates a pull request, an automated quality gate statically analyzes changed (and relevant) build and bootstrap tooling files (under `overlay/` and `bootstrap/`) so that obvious defects, style issues, and policy or security concerns are surfaced early and must be addressed before merge.

### Acceptance Scenarios
1. **Given** a new pull request touching any file under `overlay/` or `bootstrap/`, **When** the pull request is opened, **Then** an automated static analysis run is triggered and its pass/fail status is attached to the pull request.
2. **Given** a pull request where static analysis finds no blocking violations, **When** maintainers view the pull request, **Then** the quality gate shows success and does not block merge.
3. **Given** a pull request modifying a shell script in `overlay/scripts/` or `bootstrap/`, **When** analysis executes, **Then** syntax or static rule violations (if any) are reported with file and line references.
4. **Given** a pull request modifying a PowerShell script, **When** analysis executes, **Then** any syntactic errors or identified rule violations are reported with file and line references.
5. **Given** a pull request with only documentation changes (e.g., `README.md`), **When** analysis runs, **Then** it completes quickly and reports success (no spurious failures) unless global invariants are violated.
6. **Given** a pull request previously failing the quality gate, **When** the author pushes a fix, **Then** the analysis re-runs automatically and updates status.
7. **Given** a pull request changing a bootstrap installer script, **When** analysis runs, **Then** it validates that static policies (e.g., absence of disallowed patterns) still hold.
8. **Given** a pull request modifying a JSON file (e.g., configuration or ruleset) within `overlay/` or `bootstrap/`, **When** analysis runs, **Then** it validates the file is well‑formed UTF-8 JSON and enforces repository JSON policy: disallow duplicate object keys, require stable ordering for keys where documented (if present), and flag presence of empty string values for mandatory descriptive fields as violations.
9. **Given** a pull request modifying `overlay/al.ruleset.json`, **When** analysis runs, **Then** it validates that only documented top-level properties (`name`, `description`, `generalAction`, `includedRuleSets`, `enableExternalRulesets`, `rules`) are present, that each rule object contains unique `id` values with allowed `action` from {`Error`,`Warning`,`Info`,`Hidden`,`None`,`Default`}, and that duplicate rule IDs are reported as blocking.

### Edge Cases
- Transient environment/tool unavailability (e.g., analyzer executable missing) → Should produce a clear failure reason, not silent pass.
- File renames of scripts → Should not produce duplicate or stale diagnostics after rename.
- Addition of new script files → Only analyzed individually; no cross-platform comparison required (parity handled in future phases).
- Non-script file changes should not generate false positives; only `.sh`, `.ps1`, `.json` (policy / configuration) files in `overlay/` and `bootstrap/` are in scope for analysis.
- Experimental / draft scripts: No opt-out mechanism in this phase; all in-scope files (`.sh`, `.ps1`, `.json` under `overlay/` and `bootstrap/`) are always analyzed uniformly.
- Modification to `al.ruleset.json` introducing duplicate rule IDs → Reported as blocking (prevents merge) to avoid ambiguous diagnostic severity mapping.
- Introduction of unsupported top-level keys in `al.ruleset.json` → Reported as blocking to preserve compatibility and prevent silent ignore.
- Missing optional but recommended descriptive fields (e.g., empty or absent `description`) → Reported as advisory (non-blocking) to encourage documentation without impeding iteration.

## Requirements *(mandatory)*

### Functional Requirements
- **FR-001**: The system MUST automatically trigger a static analysis quality gate on every pull request open, synchronize (new commits), and reopen event.
- **FR-002**: The system MUST evaluate all modified and newly added relevant files under `overlay/` and `bootstrap/` (scripts, configuration, and installer artifacts) for syntactic correctness and stated static policy adherence (WHAT only; HOW unspecified).
- **FR-003**: The system MUST classify detected issues into these categories: Syntax (structural / parse correctness), Style (format & naming consistency), Policy (repository-specific conventions & required metadata), Security (patterns with potential risk), Configuration (JSON/ruleset structural & content violations). Categories are mutually exclusive at reporting time.
- **FR-004**: The system MUST surface a clear, human‑readable summary of violations (file path, category, short description) directly in the pull request status context or associated report.
 - **FR-005**: The system MUST block merge (fail the quality gate) upon any violation in the following categories unless that specific rule is explicitly designated Advisory: Syntax (parse / structural failure), Security (potential exploit or unsafe pattern), Configuration (invalid JSON/ruleset structure, disallowed/unknown top-level key, duplicate rule ID, invalid action value), Policy (violations that break a defined repository invariant such as mandatory metadata), Style (format/naming deviations), or any explicitly designated Blocking rule.
 - **FR-006**: The system MUST succeed (non‑blocking) only when all detected issues are explicitly designated Advisory (e.g., low‑impact stylistic nuances intentionally deferred, optional descriptive metadata omissions, or format normalization suggestions). Advisory issues MUST still be reported for visibility.
 - **FR-007**: The system MUST complete each analysis run within a fast feedback budget: 95% of runs (typical diffs) MUST finish in ≤30 seconds wall‑clock and NO run may exceed a hard cap of 60 seconds; exceeding the cap constitutes a blocking failure (quality status indeterminate). Rationale: preserve rapid reviewer feedback and prevent long-tail stalls.
- **FR-008**: The system MUST re-run automatically after each new commit to the pull request until all blocking violations are resolved.
- **FR-009**: The system MUST provide deterministic results given the same commit (no flaky diagnostics).
- **FR-010**: The system MUST allow maintainers to expand or refine the set of enforced rule categories in future iterations without changing the overall trigger model (extensibility requirement—implementation deferred).
- **FR-011**: The system MUST ignore changes limited to non-relevant file types (e.g., markdown docs); in-scope file types are restricted to `.sh`, `.ps1`, and `.json` under `overlay/` and `bootstrap/`.
- **FR-012**: The system MUST document the scope of analyzed files, categories, and pass/fail meaning in a dedicated subsection of `CONTRIBUTING.md` (authoritative location), referenced as needed from other repository entry points.
 - **FR-013**: The system MUST validate JSON files in scope (syntactic correctness; prohibition of duplicate object keys; non-empty mandatory descriptive fields where defined by repository policy) and report violations with file and JSON pointer path context.
 - **FR-014**: The system MUST validate `al.ruleset.json` against the documented ruleset object structure (allowed top-level properties only; each rule must contain a unique `id` and an `action` belonging to {`Error`,`Warning`,`Info`,`Hidden`,`None`,`Default`}; duplicate `id` values are blocking) and report deviations categorized by severity (blocking vs advisory per defined policy).

### Scope Boundaries (Non-Goals)
- Integration or end-to-end execution tests (future phase explicitly out of scope here).
- Automated remediation or auto-fix of violations (reporting only in this phase).
- Performance benchmarking beyond ensuring completion within agreed time budget.
- Cross-platform parity verification (deferred to later testing phase).
- Adding new language/tool specific rules beyond foundational correctness, style, and basic security/policy checks (future enhancements).

### Assumptions
- Contributors already open pull requests through a platform capable of reporting a status check.
- Repository maintainers desire an enforced (blocking) gate rather than optional reporting.
- All scripts intended for distribution reside under `overlay/` and follow existing naming conventions.

### Dependencies
- Existing repository directory structure stability; significant restructuring would require rule updates.
- Baseline tooling MUST already be present in the CI environment: required script interpreters (for `.sh` and `.ps1` files), JSON validation capability, and static rule evaluation tooling for syntax, policy, security, style, and configuration categories. The analysis process MUST explicitly verify presence of each required capability at start and, if any are missing, emit a single consolidated blocking Configuration diagnostic (no partial / silent skips; no auto-install in this phase).

### Risks / Open Questions
- Comprehensive strict initial scope (Style included as blocking unless explicitly waived) may increase early PR failure rate; monitoring and possible future reclassification of noisy Style rules may be required to prevent contributor fatigue.
- Extended runtime for large diffs could slow contributor feedback loops.
- Overly broad file inclusion could dilute signal-to-noise ratio if scope not tightly defined.
- Need for secret handling or environmental isolation likely minimal, but failure to scope properly could expose environment variance.

---

## Review & Acceptance Checklist
*GATE: Manual/automated review prior to planning phase*

### Content Quality
- [x] No implementation details (specific linters, CI service names) beyond WHAT requirements
- [x] Focused on user value (early defect detection, merge confidence)
- [x] Written for non-technical stakeholders (business rationale apparent)
- [x] All mandatory sections completed

### Requirement Completeness
- [x] No [NEEDS CLARIFICATION] markers remain (resolve before implementation)
- [x] Requirements are testable and unambiguous
- [x] Success criteria measurable (latency, determinism, defined coverage scope) once clarified
- [x] Scope clearly bounded (excludes integration tests, auto-fixes)
- [x] Dependencies and assumptions identified

---

## Execution Status
Initial draft populated; open clarification items enumerated.

- [x] User description parsed
- [x] Key concepts extracted
- [x] Ambiguities marked
- [x] User scenarios defined
- [x] Requirements generated
- [x] Entities identified (none needed; data-store neutral)
- [x] Review checklist passed (pending resolution of clarification markers)

---
